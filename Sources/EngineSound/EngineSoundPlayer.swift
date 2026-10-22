import AVFoundation
import Foundation

public enum AudioSessionMixPolicy {
    case duckOthers
    case mixWithOthers
}

public enum EngineSoundPlayerError: Error {
    case invalidSampleRate
    case incompatibleSampleRate
    case allocationFailed
}

#if os(iOS)
/// AVAudioSession belongs to the process, so active players share one activation.
enum AudioSessionCoordinator {
    private static let lock = NSLock()
    private static var duckPlayers = 0
    private static var mixPlayers = 0

    static func acquire(policy: AudioSessionMixPolicy) throws {
        lock.lock()
        defer { lock.unlock() }
        let session = AVAudioSession.sharedInstance()
        let activePlayers = duckPlayers + mixPlayers
        let effectiveDuckPlayers = duckPlayers + (policy == .duckOthers ? 1 : 0)
        try session.setCategory(.playback, mode: .default,
                                options: effectiveDuckPlayers > 0 ? [.duckOthers] : [.mixWithOthers])
        if activePlayers == 0 { try session.setActive(true) }
        if policy == .duckOthers { duckPlayers += 1 } else { mixPlayers += 1 }
    }

    static func release(policy: AudioSessionMixPolicy) {
        lock.lock()
        defer { lock.unlock() }
        if policy == .duckOthers {
            guard duckPlayers > 0 else { return }
            duckPlayers -= 1
        } else {
            guard mixPlayers > 0 else { return }
            mixPlayers -= 1
        }
        let session = AVAudioSession.sharedInstance()
        if duckPlayers + mixPlayers == 0 {
            // A later first acquire reasserts activation if deactivation fails.
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        } else {
            try? session.setCategory(.playback, mode: .default,
                                     options: duckPlayers > 0 ? [.duckOthers] : [.mixWithOthers])
        }
    }
}
#endif

/// Playback for a mono PCM16 source. Source controls must be serialized with
/// `render(into:)` by the caller; a host can instead replace the whole source.
public final class EngineSoundPlayer {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var worker: PlaybackWorker?
    private var lastRing: RingBuffer?
    private let controlQueue = DispatchQueue(label: "EngineSound player control")
    private let controlQueueKey = DispatchSpecificKey<Bool>()
    private let session: EngineSoundSession
    private var sessionPolicy: AudioSessionMixPolicy?
    private var requestedSource: EngineSoundSource?
    private var requestedSampleRate: Double = 0
    private var requestedPolicy: AudioSessionMixPolicy = .duckOthers
    private var interrupted = false
    /// False after the system declines resumption or the output is removed; only `start` restores it.
    private var resumeAllowed = true
    private var outputAvailable: Bool
    private var thermalState: EngineSoundThermalState
    private var playbackFailure: Error?
    private var failureHandler: ((Error) -> Void)?

    public init(session: EngineSoundSession? = nil) {
        #if os(iOS)
        self.session = session ?? IOSAudioSession()
        #else
        self.session = session ?? NoopAudioSession()
        #endif
        outputAvailable = self.session.isOutputAvailable
        thermalState = self.session.thermalState
        controlQueue.setSpecific(key: controlQueueKey, value: true)
        self.session.onEvent = { [weak self] event in
            self?.controlQueue.async { [weak self] in self?.handle(event) }
        }
    }
    deinit {
        session.onEvent = nil
        withControl {
            requestedSource = nil
            stopPlayback(immediate: true)
        }
    }

    private func withControl<T>(_ body: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: controlQueueKey) == true { return try body() }
        return try controlQueue.sync(execute: body)
    }

    public var isPlaying: Bool {
        withControl { worker != nil }
    }

    public var underrunCount: Int {
        withControl { lastRing?.underrunCount ?? 0 }
    }

    public var consumedFrameCount: Int {
        withControl { lastRing?.consumedFrameCount ?? 0 }
    }

    /// Set after an automatic resume fails. A later eligible event retries playback.
    public var lastPlaybackFailure: Error? { withControl { playbackFailure } }

    /// Called on the main queue when automatic resume fails.
    public var onPlaybackFailure: ((Error) -> Void)? {
        get { withControl { failureHandler } }
        set { withControl { failureHandler = newValue } }
    }

    public func start(_ source: EngineSoundSource, policy: AudioSessionMixPolicy = .duckOthers) throws {
        let sampleRate = source.sampleRate
        try withControl { try requestStart(source, sampleRate: sampleRate, policy: policy) }
    }

    private func requestStart(_ source: EngineSoundSource, sampleRate: Double, policy: AudioSessionMixPolicy) throws {
        requestedSource = nil
        stopPlayback(immediate: false)
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
              AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) != nil
        else { throw EngineSoundPlayerError.invalidSampleRate }
        requestedSource = source
        requestedSampleRate = sampleRate
        requestedPolicy = policy
        resumeAllowed = true
        playbackFailure = nil
        guard canPlay else { return }
        do { try startPlayback(source, sampleRate: sampleRate, policy: policy) }
        catch { requestedSource = nil; playbackFailure = error; throw error }
    }

    private var canPlay: Bool {
        requestedSource != nil && !interrupted && resumeAllowed && outputAvailable && thermalState != .critical
    }

    private func startPlayback(_ source: EngineSoundSource, sampleRate: Double, policy: AudioSessionMixPolicy) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        else { throw EngineSoundPlayerError.invalidSampleRate }
        guard let ring = RingBuffer(capacity: 8192) else { throw EngineSoundPlayerError.allocationFailed }
        let worker = PlaybackWorker(source: source, sampleRate: sampleRate, ring: ring,
                                    initialFrequencyScale: thermalState.simulationFrequencyScale)
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, buffers in
            let channels = UnsafeMutableAudioBufferListPointer(buffers)
            for frame in 0..<Int(frameCount) {
                let sample = Float(ring.readSample()) / 32768
                for channel in channels {
                    channel.mData!.assumingMemoryBound(to: Float.self)[frame] = sample
                }
            }
            return noErr
        }

        // Engine-only restarts keep the session, so other apps are not un-ducked.
        if sessionPolicy == nil {
            try session.acquire(policy: policy)
            sessionPolicy = policy
        }

        worker.start()
        // Prebuffer before connecting the device callback.
        while ring.available < 2048 { Thread.sleep(forTimeInterval: 0.001) }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            engine.detach(node)
            worker.abort()
            deactivateSessionIfNeeded()
            throw error
        }
        self.node = node
        self.worker = worker
        self.lastRing = ring
        playbackFailure = nil
    }

    /// Replaces the source with a 20 ms crossfade on the producer thread.
    public func switchSource(to source: EngineSoundSource) throws {
        let sampleRate = source.sampleRate
        try withControl {
            guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate) else {
                throw EngineSoundPlayerError.invalidSampleRate
            }
            guard let worker else {
                guard requestedSource != nil else {
                    return try requestStart(source, sampleRate: sampleRate, policy: requestedPolicy)
                }
                // Paused: update the request without overriding a system do-not-resume.
                guard AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) != nil
                else { throw EngineSoundPlayerError.invalidSampleRate }
                requestedSource = source
                requestedSampleRate = sampleRate
                return
            }
            guard sampleRate == worker.sampleRate else { throw EngineSoundPlayerError.incompatibleSampleRate }
            requestedSource = source
            requestedSampleRate = sampleRate
            worker.switchSource(to: source, frequencyScale: thermalState.simulationFrequencyScale)
        }
    }

    public func stop() {
        withControl {
            requestedSource = nil
            playbackFailure = nil
            stopPlayback(immediate: false)
        }
    }

    private func stopPlayback(immediate: Bool, releasingSession: Bool = true) {
        let worker = self.worker
        self.worker = nil
        let node = self.node
        self.node = nil
        if immediate { engine.stop(); worker?.abort() }
        else { worker?.stop() }
        // Let the last queued fade reach the output before stopping the engine.
        if !immediate, let worker { Thread.sleep(forTimeInterval: Double(worker.ring.capacity) / worker.sampleRate) }
        engine.stop()
        if let node { engine.detach(node) }
        if releasingSession { deactivateSessionIfNeeded() }
    }

    private func deactivateSessionIfNeeded() {
        guard let policy = sessionPolicy else { return }
        sessionPolicy = nil
        session.release(policy: policy)
    }

    private func handle(_ event: EngineSoundSessionEvent) {
        switch event {
        case .interruptionBegan:
            interrupted = true
            stopPlayback(immediate: true)
        case .interruptionEnded(let shouldResume):
            interrupted = false
            if !shouldResume { resumeAllowed = false }
        case .outputRouteChanged(let reason, let isAvailable):
            outputAvailable = isAvailable
            switch reason {
            case .sessionConfiguration where isAvailable:
                break
            case .oldDeviceUnavailable:
                // Do not move sound to the fallback output; the host must request it again.
                resumeAllowed = false
                stopPlayback(immediate: true)
            default:
                stopPlayback(immediate: true, releasingSession: !isAvailable)
            }
        case .thermalStateChanged(let state):
            thermalState = state
            if state == .critical { stopPlayback(immediate: true) }
            else { worker?.setSimulationFrequencyScale(state.simulationFrequencyScale) }
        }
        if canPlay, worker == nil, let source = requestedSource {
            do { try startPlayback(source, sampleRate: requestedSampleRate, policy: requestedPolicy) }
            catch {
                playbackFailure = error
                if let failureHandler {
                    DispatchQueue.main.async { failureHandler(error) }
                }
            }
        }
        if worker == nil { deactivateSessionIfNeeded() }
    }
}

private final class PlaybackWorker {
    let sampleRate: Double
    let ring: RingBuffer
    private let lock = NSLock()
    private let finished = DispatchSemaphore(value: 0)
    private var thread: Thread?
    private var source: EngineSoundSource
    private var nextSource: EngineSoundSource?
    private var stopping = false
    private var aborted = false
    private var running = false
    private var pendingFrequencyScale: Double?
    private var frequencyScale: Double
    private let initialFrequencyScale: Double
    private let framesPerBlock = 256
    private let fadeFrames: Int

    init(source: EngineSoundSource, sampleRate: Double, ring: RingBuffer, initialFrequencyScale: Double) {
        self.source = source
        self.sampleRate = sampleRate
        self.ring = ring
        frequencyScale = initialFrequencyScale
        self.initialFrequencyScale = initialFrequencyScale
        fadeFrames = max(1, Int(sampleRate * 0.02))
    }

    func start() {
        lock.lock()
        running = true
        lock.unlock()
        let thread = Thread { [self] in run() }
        self.thread = thread
        thread.name = "EngineSound producer"
        thread.start()
    }

    func switchSource(to source: EngineSoundSource, frequencyScale: Double) {
        lock.lock()
        nextSource = source
        pendingFrequencyScale = frequencyScale
        self.frequencyScale = frequencyScale
        lock.unlock()
    }

    func setSimulationFrequencyScale(_ scale: Double) {
        lock.lock()
        pendingFrequencyScale = scale
        frequencyScale = scale
        lock.unlock()
    }

    func stop() {
        lock.lock()
        let wasRunning = running
        stopping = true
        lock.unlock()
        if wasRunning, finished.wait(timeout: .now() + 2) == .timedOut {
            // A stopped audio device cannot drain a full ring for the fade.
            abort()
        }
        thread = nil
    }

    func abort() {
        lock.lock()
        aborted = true
        lock.unlock()
        finished.wait()
        thread = nil
    }

    private func run() {
        defer {
            lock.lock()
            running = false
            lock.unlock()
            finished.signal()
        }
        (source as? EngineSoundThermalControllable)?.setSimulationFrequencyScale(initialFrequencyScale)
        var primary = [Int16](repeating: 0, count: framesPerBlock)
        var secondary = [Int16](repeating: 0, count: framesPerBlock)
        var mixed = [Int16](repeating: 0, count: framesPerBlock)
        var startupFrame = 0
        var switchFrame = 0
        var stopFrame = 0
        var fadingSource: EngineSoundSource?

        while true {
            if ring.capacity - ring.available < framesPerBlock {
                lock.lock()
                let shouldAbort = aborted
                lock.unlock()
                if shouldAbort { break }
                Thread.sleep(forTimeInterval: 0.002)
                continue
            }
            lock.lock()
            if aborted { lock.unlock(); break }
            let shouldStop = stopping
            let frequencyScale = pendingFrequencyScale
            pendingFrequencyScale = nil
            var beganSwitch = false
            if fadingSource == nil, let pending = nextSource {
                fadingSource = pending
                nextSource = nil
                switchFrame = 0
                beganSwitch = true
            }
            let currentFrequencyScale = self.frequencyScale
            lock.unlock()

            if beganSwitch {
                (fadingSource as? EngineSoundThermalControllable)?.setSimulationFrequencyScale(currentFrequencyScale)
            }
            if let frequencyScale {
                (source as? EngineSoundThermalControllable)?.setSimulationFrequencyScale(frequencyScale)
                (fadingSource as? EngineSoundThermalControllable)?.setSimulationFrequencyScale(frequencyScale)
            }

            primary.withUnsafeMutableBufferPointer { buffer in
                let got = min(max(source.render(into: buffer), 0), buffer.count)
                if got < buffer.count { for index in got..<buffer.count { buffer[index] = 0 } }
            }
            if let fadingSource {
                secondary.withUnsafeMutableBufferPointer { buffer in
                    let got = min(max(fadingSource.render(into: buffer), 0), buffer.count)
                    if got < buffer.count { for index in got..<buffer.count { buffer[index] = 0 } }
                }
            }
            for index in 0..<framesPerBlock {
                let startGain = min(Double(startupFrame + index) / Double(fadeFrames), 1)
                let stopGain = shouldStop ? max(0, 1 - Double(stopFrame + index) / Double(fadeFrames)) : 1
                let switchGain = fadingSource == nil ? 0 : min(Double(switchFrame + index) / Double(fadeFrames), 1)
                let value = Double(primary[index]) * (1 - switchGain) + Double(secondary[index]) * switchGain
                // 0.8 bounds the output even if a source reaches full PCM16 scale.
                mixed[index] = Int16(max(-32768, min(32767, (value * startGain * stopGain * 0.8).rounded())))
            }
            mixed.withUnsafeBufferPointer { _ = ring.write($0) }
            startupFrame += framesPerBlock
            if fadingSource != nil {
                switchFrame += framesPerBlock
                if switchFrame >= fadeFrames {
                    source = fadingSource!
                    fadingSource = nil
                }
            }
            if shouldStop {
                stopFrame += framesPerBlock
                if stopFrame >= fadeFrames { break }
            }
        }
    }
}
