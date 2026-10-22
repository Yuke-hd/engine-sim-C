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

/// Playback for a mono PCM16 source. Source controls must be serialized with
/// `render(into:)` by the caller; a host can instead replace the whole source.
public final class EngineSoundPlayer {
    private let engine = AVAudioEngine()
    private var node: AVAudioSourceNode?
    private var worker: PlaybackWorker?
    private var lastRing: RingBuffer?
    private let stateLock = NSRecursiveLock()

    public init() {}
    deinit { stop() }

    public var underrunCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastRing?.underrunCount ?? 0
    }

    public func start(_ source: EngineSoundSource, policy: AudioSessionMixPolicy = .duckOthers) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        stop()
        guard source.sampleRate.isFinite, source.sampleRate > 0 else { throw EngineSoundPlayerError.invalidSampleRate }
        guard let ring = RingBuffer(capacity: 8192) else { throw EngineSoundPlayerError.allocationFailed }
        let worker = PlaybackWorker(source: source, ring: ring)
        let format = AVAudioFormat(standardFormatWithSampleRate: source.sampleRate, channels: 2)!
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

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default,
                                options: policy == .duckOthers ? [.duckOthers] : [.mixWithOthers])
        try session.setActive(true)
        #endif

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
            #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
            throw error
        }
        self.node = node
        self.worker = worker
        self.lastRing = ring
    }

    /// Replaces the source with a 20 ms crossfade on the producer thread.
    public func switchSource(to source: EngineSoundSource) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let worker else { return try start(source) }
        guard source.sampleRate == worker.sampleRate else { throw EngineSoundPlayerError.incompatibleSampleRate }
        worker.switchSource(to: source)
    }

    public func stop() {
        stateLock.lock()
        defer { stateLock.unlock() }
        let worker = self.worker
        self.worker = nil
        let node = self.node
        self.node = nil
        worker?.stop()
        // Let the last queued fade reach the output before stopping the engine.
        if let worker { Thread.sleep(forTimeInterval: Double(worker.ring.capacity) / worker.sampleRate) }
        engine.stop()
        if let node { engine.detach(node) }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
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
    private let framesPerBlock = 256
    private let fadeFrames: Int

    init(source: EngineSoundSource, ring: RingBuffer) {
        self.source = source
        self.sampleRate = source.sampleRate
        self.ring = ring
        fadeFrames = max(1, Int(source.sampleRate * 0.02))
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

    func switchSource(to source: EngineSoundSource) {
        lock.lock()
        nextSource = source
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
            if fadingSource == nil, let pending = nextSource {
                fadingSource = pending
                nextSource = nil
                switchFrame = 0
            }
            lock.unlock()

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
