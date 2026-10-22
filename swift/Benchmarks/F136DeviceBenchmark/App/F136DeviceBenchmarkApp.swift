import EngineSimCore
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

private struct BenchmarkView: View {
    @State private var isRunning = false
    @State private var result = "Run on a signed physical iPhone. Simulator results do not satisfy issue #6."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("F136 device benchmark").font(.title.bold())
                Button(isRunning ? "Running…" : "Run LS and F136 benchmark") {
                    isRunning = true
                    let device = UIDevice.current.name
                    let system = "iOS \(UIDevice.current.systemVersion)"
                    Task.detached(priority: .userInitiated) {
                        let report = Benchmark.run(device: device, system: system)
                        await MainActor.run {
                            result = report
                            isRunning = false
                        }
                    }
                }
                .disabled(isRunning)
                Text(result).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            .padding()
        }
    }
}
