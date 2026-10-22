import EngineSimCore
import EngineSound
import SwiftUI
import UIKit

private enum Benchmark {
    static let simulationFrequency = 1_000
    static let sampleRate = 44_100
    // Only 3000 RPM: at 1000 Hz simulation, 1000 RPM (both profiles), 6000 and
    // 7500 RPM (LS) and 8500 RPM (F136) trip combustion_chamber.cpp's assertion.
    static let targetRPM = 3_000.0
    static let audioSeconds = 3
    static let timedRuns = 5
    /// Issue #6 gate: the median F136 compute/audio ratio must be strictly below this.
    static let limit = 0.7

    struct Measurement {
        let name: String
        let ratios: [Double]
        let measuredRPM: Double
        let validAudio: Bool
        let error: String?

        var sorted: [Double] { ratios.sorted() }
        var median: Double { sorted.isEmpty ? .infinity : sorted[sorted.count / 2] }
    }

    static func measure(_ profile: EngineSimProfile, name: String) -> Measurement {
        func failed(_ error: String) -> Measurement {
            Measurement(name: name, ratios: [], measuredRPM: 0, validAudio: false, error: error)
        }
        guard let core = engine_sim_create(profile, Int32(simulationFrequency)) else {
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
                           validAudio: validAudio, error: nil)
    }

    static func format(_ value: Double) -> String { String(format: "%.3f", value) }

    static func describe(_ measurement: Measurement) -> String {
        if let error = measurement.error { return "\(measurement.name): \(error)" }
        let sorted = measurement.sorted
        return """
        \(measurement.name) @ \(Int(targetRPM)) RPM (measured \(Int(measurement.measuredRPM.rounded())) RPM)
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
        let baseline = measure(ENGINE_SIM_PROFILE_LS_V8, name: "LS V8 (baseline)")
        let f136 = measure(ENGINE_SIM_PROFILE_F136_V8, name: "F136 V8")
        let passes = f136.error == nil && f136.validAudio && f136.median < limit
        let maxRatio = f136.sorted.last.map(format) ?? "n/a"
        return """
        Device: \(device) (\(system)); build: \(configuration)
        Simulation: \(simulationFrequency) Hz; audio: \(sampleRate) Hz mono PCM16
        Per profile: 1 discarded warm-up + \(timedRuns) timed \(audioSeconds) s renders
        Gate: F136 V8 median compute/audio ratio < \(format(limit)) (max is reported, not gated)

        \(describe(baseline))

        \(describe(f136))

        Result: \(passes ? "PASS" : "FAIL") (F136 median \(format(f136.median)) vs < \(format(limit)); \
        F136 max \(maxRatio))
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

/// Live engine audio for the listening controls. The player's worker thread is
/// the only caller of render; RPM changes replace the source instead.
private final class LiveEngineSource: EngineSoundSource {
    let sampleRate = Double(ENGINE_SIM_SAMPLE_RATE)
    private let core: OpaquePointer

    init?(profile: EngineSimProfile, rpm: Double) {
        guard let core = engine_sim_create(profile, Int32(Benchmark.simulationFrequency)) else { return nil }
        self.core = core
        engine_sim_hold_rpm(core, rpm)
    }

    deinit { engine_sim_destroy(core) }

    func setTargetRPM(_ rpm: Double) { engine_sim_set_target_rpm(core, rpm) }
    func setThrottle(_ throttle: Double) { engine_sim_set_throttle(core, throttle) }
    func setIgnition(_ enabled: Bool) { engine_sim_set_ignition(core, enabled ? 1 : 0) }

    func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int {
        guard let base = frames.baseAddress else { return 0 }
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
    // RPMs that render without tripping combustion_chamber.cpp at 1000 Hz.
    static let rpmPresets = [2_000.0, 3_000.0, 4_000.0, 5_000.0]

    @Published private(set) var playing: Engine?
    @Published private(set) var status = "Stopped"
    @Published var rpm = Benchmark.targetRPM

    private let player = EngineSoundPlayer()
    // Player start and stop block while buffering, so keep them off the main thread.
    private let queue = DispatchQueue(label: "F136DeviceBenchmark.listen")

    func play(_ engine: Engine) {
        playing = engine
        let rpm = rpm
        report("Starting \(engine.name) @ \(Int(rpm)) RPM…")
        queue.async { [player] in
            guard let source = LiveEngineSource(profile: engine.profile, rpm: rpm) else {
                Task { @MainActor in self.report("Playback error: \(engine.name) creation failed") }
                return
            }
            do {
                // Starts the player, or cross-fades from the current engine.
                try player.switchSource(to: source)
                Task { @MainActor in self.report("Playing \(engine.name) @ \(Int(rpm)) RPM") }
            } catch {
                Task { @MainActor in self.report("Playback error: \(error)") }
            }
        }
    }

    func selectRPM(_ value: Double) {
        rpm = value
        if let playing { play(playing) }
    }

    func stop() {
        playing = nil
        queue.async { [player] in
            let underruns = player.underrunCount
            player.stop()
            Task { @MainActor in self.report("Stopped (underruns: \(underruns))") }
        }
    }

    /// Plays each engine briefly and logs the outcome for console verification.
    func selfTest() async {
        play(Self.ls)
        try? await Task.sleep(for: .seconds(4))
        play(Self.f136)
        try? await Task.sleep(for: .seconds(4))
        let (underruns, frames) = await withCheckedContinuation { continuation in
            queue.async { [player] in
                continuation.resume(returning: (player.underrunCount, player.consumedFrameCount))
            }
        }
        report("Self-test: consumed \(frames) frames, underruns \(underruns)")
        stop()
    }

    private func report(_ message: String) {
        status = message
        log("[listen] \(message)")
    }
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
                Picker("RPM", selection: Binding(get: { listener.rpm }, set: listener.selectRPM)) {
                    ForEach(Listener.rpmPresets, id: \.self) { Text("\(Int($0))").tag($0) }
                }
                .pickerStyle(.segmented)
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
