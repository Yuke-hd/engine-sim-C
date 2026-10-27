import AVFoundation
import EngineSimCore

enum EngineChoice: String, CaseIterable, Identifiable {
    case lsV8 = "GM LS V8"
    case f136 = "Ferrari F136"
    case m177 = "Mercedes-AMG M177"
    var id: String { rawValue }

    var profile: EngineSimProfile {
        switch self {
        case .lsV8: return ENGINE_SIM_PROFILE_LS_V8
        case .f136: return ENGINE_SIM_PROFILE_F136_V8
        case .m177: return ENGINE_SIM_PROFILE_M177_V8
        }
    }

    /// Top of the slider and the sweep: a little past each engine's redline.
    var maxRpm: Double {
        switch self {
        case .lsV8: return 6500
        case .f136: return 9000
        case .m177: return 7200
        }
    }

    var sweepTopRpm: Double {
        switch self {
        case .lsV8: return 6000
        case .f136: return 8500
        case .m177: return 7000
        }
    }

    func create(frequency: Int32) -> OpaquePointer? {
        engine_sim_create(profile, frequency)
    }
}

enum LevelerChoice: String, CaseIterable, Identifiable {
    case rpmScaled = "New (RMS)"
    case peak = "Old (peak)"
    var id: String { rawValue }

    var mode: Int32 {
        switch self {
        case .rpmScaled: return ENGINE_SIM_LEVELER_RPM_SCALED
        case .peak: return ENGINE_SIM_LEVELER_PEAK
        }
    }
}

/// Runs the simulator on a background thread and streams its audio through
/// AVAudioEngine, keeping a few short buffers queued ahead of playback.
final class EnginePlayer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var actualRpm: Double = 0
    @Published private(set) var realTimeFactor: Double = 0
    @Published private(set) var overrunActive = false

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: Double(ENGINE_SIM_SAMPLE_RATE),
        channels: 1, interleaved: false)!

    private let chunk = 1024
    private let queuedBuffers = 4

    private let lock = NSLock()
    private var targetRpm: Double = 1000
    private var throttle: Double = 0.5
    private var overrunEnabled = true
    private var overrunGain: Float = 1
    private var levelerMode: Int32 = ENGINE_SIM_LEVELER_RPM_SCALED
    private var shouldStop = false
    private var worker: Thread?
    private var statusTimer: Timer?
    private var latestRpm: Double = 0
    private var latestFactor: Double = 0
    private var latestOverrun = false

    init() {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }

    func setTargetRpm(_ rpm: Double) {
        lock.lock(); targetRpm = rpm; lock.unlock()
    }

    func setThrottle(_ value: Double) {
        lock.lock(); throttle = value; lock.unlock()
    }

    func setOverrun(enabled: Bool, gain: Double) {
        lock.lock(); overrunEnabled = enabled; overrunGain = Float(gain); lock.unlock()
    }

    func setLeveler(_ leveler: LevelerChoice) {
        lock.lock(); levelerMode = leveler.mode; lock.unlock()
    }

    func start(engine: EngineChoice, frequency: Int32) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            try audioEngine.start()
        } catch {
            print("audio start failed: \(error)")
            return
        }
        playerNode.play()

        lock.lock(); shouldStop = false; lock.unlock()
        let thread = Thread { [weak self] in self?.run(engine: engine, frequency: frequency) }
        thread.qualityOfService = .userInteractive
        worker = thread
        thread.start()
        isRunning = true

        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.lock.lock()
            let rpm = self.latestRpm, factor = self.latestFactor, overrun = self.latestOverrun
            self.lock.unlock()
            self.overrunActive = overrun
            self.actualRpm = rpm
            self.realTimeFactor = factor
        }
    }

    func stop() {
        guard let worker else { return }
        lock.lock(); shouldStop = true; lock.unlock()
        while !worker.isFinished { usleep(1000) }
        self.worker = nil
        statusTimer?.invalidate()
        statusTimer = nil
        playerNode.stop()
        audioEngine.stop()
        isRunning = false
    }

    private func run(engine: EngineChoice, frequency: Int32) {
        guard let core = engine.create(frequency: frequency) else { return }
        defer { engine_sim_destroy(core) }

        // Start at 0 and signal up: libdispatch traps if a semaphore is freed with
        // a value below its initial one, which in-flight buffers would cause.
        let slots = DispatchSemaphore(value: 0)
        for _ in 0..<queuedBuffers { slots.signal() }
        var samples = [Int16](repeating: 0, count: chunk)
        var mixed = [Float](repeating: 0, count: chunk)
        let overrun = OverrunLayer()
        var appliedRpm = -1.0
        var appliedThrottle = -1.0
        var appliedMode: Int32 = -1
        var renderSeconds = 0.0

        while true {
            lock.lock()
            let stopNow = shouldStop, rpm = targetRpm, mode = levelerMode, open = throttle
            let overrunOn = overrunEnabled, overrunLevel = overrunGain
            lock.unlock()
            if stopNow { break }

            // hold_rpm resets the throttle to 0.5, so reapply ours after it.
            if rpm != appliedRpm { engine_sim_hold_rpm(core, rpm); appliedRpm = rpm; appliedThrottle = -1 }
            if open != appliedThrottle { engine_sim_set_throttle(core, open); appliedThrottle = open }
            if mode != appliedMode { engine_sim_set_leveler_mode(core, mode); appliedMode = mode }

            if slots.wait(timeout: .now() + .milliseconds(100)) == .timedOut { continue }

            let start = CFAbsoluteTimeGetCurrent()
            let written = Int(engine_sim_render(core, &samples, Int32(chunk)))
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            renderSeconds = 0.9 * renderSeconds + 0.1 * elapsed

            for i in 0..<written { mixed[i] = Float(samples[i]) / 32768 }
            overrun.mix(into: &mixed, count: written, throttle: open, rpm: abs(engine_sim_rpm(core)),
                        maxRpm: engine.maxRpm, gain: overrunOn ? overrunLevel : 0)

            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk))!
            buffer.frameLength = AVAudioFrameCount(written)
            let out = buffer.floatChannelData![0]
            for i in 0..<written { out[i] = Self.softLimit(mixed[i]) }
            playerNode.scheduleBuffer(buffer) { slots.signal() }

            lock.lock()
            latestRpm = engine_sim_rpm(core)
            latestOverrun = overrunOn && overrun.isActive
            latestFactor = renderSeconds > 0 ? Double(chunk) / Double(ENGINE_SIM_SAMPLE_RATE) / renderSeconds : 0
            lock.unlock()
        }

        // Let queued buffers drain or be dropped before the core goes away.
        playerNode.stop()
    }

    /// The core soft-limits the engine alone; this bends the engine plus overrun
    /// mix with the same knee (20000 and 12000 of 32768) so overlaps don't clip.
    private static func softLimit(_ x: Float) -> Float {
        let knee: Float = 0.61, headroom: Float = 0.37
        let magnitude = abs(x)
        if magnitude <= knee { return x }
        return copysign(knee + headroom * tanh((magnitude - knee) / headroom), x)
    }
}
