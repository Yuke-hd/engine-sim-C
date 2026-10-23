import EngineSimCore
import EngineSound
import SwiftUI
import UIKit

private enum Benchmark {
    /// The gate runs at the production default: `engine_sim_create(profile, 0)`.
    /// Reports print the frequency each core reports, not this constant.
    static let simulationFrequency = Int(ENGINE_SIM_DEFAULT_FREQUENCY)
    /// Informational only, measured after the gate: 4000 Hz is the live demo's choice.
    static let referenceFrequencies = [1_000, 4_000]
    static let sampleRate = 44_100
    // Only 3000 RPM: at 1000 Hz simulation (a reference line), 1000 RPM (both
    // profiles), 6000 and 7500 RPM (LS) and 8500 RPM (F136) trip
    // combustion_chamber.cpp's assertion.
    static let targetRPM = 3_000.0
    static let audioSeconds = 3
    static let timedRuns = 5
    /// Issue #6 gate: the median F136 compute/audio ratio must be strictly below this.
    static let limit = 0.7

    struct Measurement {
        let name: String
        let ratios: [Double]
        let measuredRPM: Double
        /// Reported by the core (`engine_sim_simulation_frequency`), 0 if creation failed.
        let simulationFrequency: Int
        let validAudio: Bool
        let error: String?

        var sorted: [Double] { ratios.sorted() }
        var median: Double { sorted.isEmpty ? .infinity : sorted[sorted.count / 2] }
    }

    /// `frequency` 0 selects ENGINE_SIM_DEFAULT_FREQUENCY.
    static func measure(_ profile: EngineSimProfile, name: String, frequency: Int = 0) -> Measurement {
        func failed(_ error: String) -> Measurement {
            Measurement(name: name, ratios: [], measuredRPM: 0, simulationFrequency: 0,
                        validAudio: false, error: error)
        }
        guard let core = engine_sim_create(profile, Int32(frequency)) else {
            return failed("creation failed")
        }
        defer { engine_sim_destroy(core) }

        engine_sim_hold_rpm(core, targetRPM)
        let frameCount = audioSeconds * sampleRate
        var samples = [Int16](repeating: 0, count: frameCount)
        // Settle at the RPM hold, then discard one full-length warm-up render.
        var settle = [Int16](repeating: 0, count: sampleRate / 2)
        guard engine_sim_render(core, &settle, Int32(settle.count)) == Int32(settle.count),
              engine_sim_render(core, &samples, Int32(frameCount)) == Int32(frameCount) else {
            return failed("warm-up render was incomplete")
        }

        var ratios: [Double] = []
        var validAudio = true
        for _ in 0..<timedRuns {
            let start = DispatchTime.now().uptimeNanoseconds
            let rendered = engine_sim_render(core, &samples, Int32(frameCount))
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
            let peak = samples.map { abs(Int32($0)) }.max() ?? 0
            validAudio = validAudio && rendered == Int32(frameCount) && peak > 0 && peak < Int32(Int16.max)
            ratios.append(elapsed / (Double(max(rendered, 1)) / Double(sampleRate)))
        }
        return Measurement(name: name, ratios: ratios, measuredRPM: engine_sim_rpm(core),
                           simulationFrequency: Int(engine_sim_simulation_frequency(core)),
                           validAudio: validAudio, error: nil)
    }

    static func format(_ value: Double) -> String { String(format: "%.3f", value) }

    static func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    static func summarize(_ measurement: Measurement) -> String {
        if let error = measurement.error { return "\(measurement.name): \(error)" }
        let sorted = measurement.sorted
        return "\(measurement.name): min \(format(sorted.first!))  median \(format(measurement.median))  " +
            "max \(format(sorted.last!))  (core \(measurement.simulationFrequency) Hz)" +
            (measurement.validAudio ? "" : "  (audio invalid)")
    }

    static func describe(_ measurement: Measurement) -> String {
        if let error = measurement.error { return "\(measurement.name): \(error)" }
        let sorted = measurement.sorted
        return """
        \(measurement.name) @ \(Int(targetRPM)) RPM (measured \(Int(measurement.measuredRPM.rounded())) RPM)
          simulation (core-reported): \(measurement.simulationFrequency) Hz
          audio valid (complete, non-silent, unclipped): \(measurement.validAudio)
          compute/audio ratios: \(measurement.ratios.map(format).joined(separator: " "))
          min \(format(sorted.first!))  median \(format(measurement.median))  max \(format(sorted.last!))
        """
    }

    static func run(device: String, system: String) -> String {
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        // Heat shifts 10 kHz ratios by about 0.06, so record the thermal state.
        let thermalBefore = thermalState()
        let baseline = measure(ENGINE_SIM_PROFILE_LS_V8, name: "LS V8 (baseline)")
        let f136 = measure(ENGINE_SIM_PROFILE_F136_V8, name: "F136 V8")
        let thermalAfterGate = thermalState()
        let references = referenceFrequencies.flatMap { frequency in
            [(ENGINE_SIM_PROFILE_LS_V8, "LS V8"), (ENGINE_SIM_PROFILE_F136_V8, "F136 V8")].map {
                summarize(measure($0.0, name: "\($0.1) @ \(frequency) Hz", frequency: frequency))
            }
        }
        let passes = f136.error == nil && f136.validAudio && f136.median < limit
            && f136.simulationFrequency == simulationFrequency
        let maxRatio = f136.sorted.last.map(format) ?? "n/a"
        return """
        Device: \(device) (\(system)); build: \(configuration)
        Simulation: default requested (0 = ENGINE_SIM_DEFAULT_FREQUENCY, \(simulationFrequency) Hz), \
        core-reported per result below; audio: \(sampleRate) Hz mono PCM16
        Per profile: 1 discarded warm-up + \(timedRuns) timed \(audioSeconds) s renders
        Gate: F136 V8 median compute/audio ratio < \(format(limit)) at \(simulationFrequency) Hz \
        (max is reported, not gated)
        Thermal state: \(thermalBefore) before, \(thermalAfterGate) after the gate runs \
        (\(thermalBefore == "nominal" ? "cool" : "warm") start)

        \(describe(baseline))

        \(describe(f136))

        Result: \(passes ? "PASS" : "FAIL") (F136 median \(format(f136.median)) vs < \(format(limit)); \
        F136 max \(maxRatio))

        Reference only, not gated (measured after the gate):
        \(references.joined(separator: "\n"))
        Thermal state at end: \(thermalState())
        """
    }
}

@main
struct F136DeviceBenchmarkApp: App {
    var body: some Scene {
        WindowGroup { BenchmarkView() }
    }
}

/// Prints to stdout so `xcrun devicectl device process launch --console` captures it.
private func log(_ message: String) {
    print(message)
    fflush(stdout)
}

/// Throttle shared between the main thread (slider) and the player's render thread.
private final class ThrottleControl: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0.0

    var value: Double {
        get { lock.lock(); defer { lock.unlock() }; return storedValue }
        set { lock.lock(); storedValue = min(max(newValue, 0), 1); lock.unlock() }
    }
}

/// Live engine audio for the listening controls. The player's worker thread is
/// the only caller of render, so the core is driven only from there: each block
/// applies the shared throttle and slews the dyno-held RPM from idle (throttle 0)
/// toward `Listener.topRPM` (throttle 1). Changing idle RPM replaces the source.
private final class LiveEngineSource: EngineSoundSource {
    let sampleRate = Double(ENGINE_SIM_SAMPLE_RATE)
    private let core: OpaquePointer
    private let idleRPM: Double
    private let throttle: ThrottleControl
    private var heldRPM: Double

    init?(profile: EngineSimProfile, idleRPM: Double, throttle: ThrottleControl) {
        guard let core = engine_sim_create(profile, Int32(Listener.simulationFrequency)) else { return nil }
        self.core = core
        self.idleRPM = idleRPM
        self.throttle = throttle
        let value = throttle.value
        heldRPM = Listener.rpm(idle: idleRPM, throttle: value)
        engine_sim_hold_rpm(core, heldRPM)
        engine_sim_set_throttle(core, value)
    }

    deinit { engine_sim_destroy(core) }

    func setTargetRPM(_ rpm: Double) { engine_sim_set_target_rpm(core, rpm) }
    func setThrottle(_ throttle: Double) { engine_sim_set_throttle(core, throttle) }
    func setIgnition(_ enabled: Bool) { engine_sim_set_ignition(core, enabled ? 1 : 0) }

    func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int {
        guard let base = frames.baseAddress else { return 0 }
        let value = throttle.value
        let step = Listener.rpmSlewPerSecond * Double(frames.count) / sampleRate
        let target = Listener.rpm(idle: idleRPM, throttle: value)
        heldRPM += min(max(target - heldRPM, -step), step)
        engine_sim_set_throttle(core, value)
        engine_sim_set_target_rpm(core, heldRPM)
        return Int(engine_sim_render(core, base, Int32(frames.count)))
    }
}

@MainActor
private final class Listener: ObservableObject {
    struct Engine: Equatable {
        let profile: EngineSimProfile
        let name: String
    }

    static let ls = Engine(profile: ENGINE_SIM_PROFILE_LS_V8, name: "LS V8")
    static let f136 = Engine(profile: ENGINE_SIM_PROFILE_F136_V8, name: "F136 V8")
    // Live playback simulates at 4000 Hz, a demo choice (the gate runs at the 10 kHz
    // default): at 1000-2000 Hz low throttle and many RPMs trip combustion_chamber.cpp's
    // NaN-force assertion, which is compiled in for Release. Throttle 0...1 sweeps between idle and 6500
    // RPM at 4000 Hz without tripping it for either profile (checked on macOS).
    nonisolated static let simulationFrequency = 4_000
    nonisolated static let topRPM = 6_500.0
    nonisolated static let rpmSlewPerSecond = 3_000.0
    static let idlePresets = [1_000.0, 2_000.0, 3_000.0]

    nonisolated static func rpm(idle: Double, throttle: Double) -> Double {
        idle + throttle * (topRPM - idle)
    }

    @Published private(set) var playing: Engine?
    @Published private(set) var status = "Stopped"
    @Published var idleRPM = 2_000.0
    @Published private(set) var throttle = 0.0

    private let player = EngineSoundPlayer()
    private let throttleControl = ThrottleControl()
    // Player start and stop block while buffering, so keep them off the main thread.
    private let queue = DispatchQueue(label: "F136DeviceBenchmark.listen")

    var targetRPM: Double { Self.rpm(idle: idleRPM, throttle: throttle) }

    func play(_ engine: Engine) {
        playing = engine
        let idleRPM = idleRPM
        let control = throttleControl
        report("Starting \(engine.name), idle \(Int(idleRPM)) RPM…")
        queue.async { [player] in
            guard let source = LiveEngineSource(profile: engine.profile, idleRPM: idleRPM, throttle: control) else {
                Task { @MainActor in self.report("Playback error: \(engine.name) creation failed") }
                return
            }
            do {
                // Starts the player, or cross-fades from the current engine.
                try player.switchSource(to: source)
                Task { @MainActor in self.report("Playing \(engine.name), idle \(Int(idleRPM)) RPM") }
            } catch {
                Task { @MainActor in self.report("Playback error: \(error)") }
            }
        }
    }

    func selectIdleRPM(_ value: Double) {
        idleRPM = value
        if let playing { play(playing) }
    }

    /// Safe from the main thread: the render thread picks it up on its next block.
    func setThrottle(_ value: Double) {
        throttle = min(max(value, 0), 1)
        throttleControl.value = throttle
    }

    func stop() {
        playing = nil
        queue.async { [player] in
            let underruns = player.underrunCount
            player.stop()
            Task { @MainActor in self.report("Stopped (underruns: \(underruns))") }
        }
    }

    /// Plays each engine while sweeping the throttle, and logs the outcome for
    /// console verification.
    func selfTest() async {
        for engine in [Self.ls, Self.f136] {
            play(engine)
            try? await Task.sleep(for: .seconds(2))
            // 0 -> 1 -> 0 over 6 s, then a snap to full and back to closed.
            for step in 0...120 {
                setThrottle(step <= 60 ? Double(step) / 60 : Double(120 - step) / 60)
                try? await Task.sleep(for: .milliseconds(50))
            }
            setThrottle(1)
            try? await Task.sleep(for: .seconds(2))
            setThrottle(0)
            try? await Task.sleep(for: .seconds(2))
            let (underruns, frames) = await withCheckedContinuation { continuation in
                queue.async { [player] in
                    continuation.resume(returning: (player.underrunCount, player.consumedFrameCount))
                }
            }
            report("Self-test \(engine.name): consumed \(frames) frames, underruns \(underruns)")
        }
        stop()
    }

    private func report(_ message: String) {
        status = message
        log("[listen] \(message)")
    }
}

@MainActor
private enum HeadlessLaunch {
    static var started = false
}

private struct BenchmarkView: View {
    @State private var isRunning = false
    @State private var result = "Run on a signed physical iPhone. Simulator results do not satisfy issue #6."
    @StateObject private var listener = Listener()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("F136 device benchmark").font(.title.bold())
                Button(isRunning ? "Running…" : "Run LS and F136 benchmark", action: runBenchmark)
                    .disabled(isRunning || listener.playing != nil)
                Text(result).font(.system(.body, design: .monospaced)).textSelection(.enabled)

                Divider()
                Text("Listen").font(.title2.bold())
                Text("Idle RPM").font(.subheadline)
                Picker("Idle RPM", selection: Binding(get: { listener.idleRPM }, set: listener.selectIdleRPM)) {
                    ForEach(Listener.idlePresets, id: \.self) { Text("\(Int($0))").tag($0) }
                }
                .pickerStyle(.segmented)
                VStack(alignment: .leading) {
                    Text("Throttle \(Int((listener.throttle * 100).rounded()))% · target \(Int(listener.targetRPM)) RPM")
                        .font(.subheadline.monospacedDigit())
                    Slider(value: Binding(get: { listener.throttle }, set: listener.setThrottle), in: 0...1)
                }
                .disabled(listener.playing == nil)
                HStack {
                    ForEach([Listener.ls, Listener.f136], id: \.name) { engine in
                        Button("Play \(engine.name)") { listener.play(engine) }
                            .buttonStyle(.borderedProminent)
                            .tint(listener.playing == engine ? .green : .accentColor)
                    }
                    Button("Stop", role: .destructive, action: listener.stop)
                        .buttonStyle(.bordered)
                        .disabled(listener.playing == nil)
                }
                .disabled(isRunning)
                Text(listener.status).font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .task {
            // Headless runs: set DEVICECTL_CHILD_BENCHMARK_AUTORUN=1 or
            // DEVICECTL_CHILD_LISTEN_SELFTEST=1 when launching via devicectl.
            // `.task` can fire again when the view reappears; run these once per launch.
            guard !HeadlessLaunch.started else { return }
            HeadlessLaunch.started = true
            let environment = ProcessInfo.processInfo.environment
            if environment["BENCHMARK_AUTORUN"] == "1" { runBenchmark() }
            if environment["LISTEN_SELFTEST"] == "1" { await listener.selfTest() }
        }
    }

    private func runBenchmark() {
        isRunning = true
        let device = UIDevice.current.name
        let system = "iOS \(UIDevice.current.systemVersion)"
        Task.detached(priority: .userInitiated) {
            let report = Benchmark.run(device: device, system: system)
            log(report)
            await MainActor.run {
                result = report
                isRunning = false
            }
        }
    }
}
