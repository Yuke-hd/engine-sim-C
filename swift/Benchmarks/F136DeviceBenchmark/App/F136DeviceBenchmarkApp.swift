import EngineSimCore
import SwiftUI
import UIKit

private enum Benchmark {
    static let simulationFrequency = 1_000
    static let sampleRate = 44_100
    static let targetRPM = 3_000.0
    static let audioSeconds = 3

    static func run(device: String, system: String) -> String {
        guard let core = engine_sim_create(ENGINE_SIM_PROFILE_F136_V8, Int32(simulationFrequency)) else {
            return "F136 creation failed"
        }
        defer { engine_sim_destroy(core) }

        engine_sim_hold_rpm(core, targetRPM)
        var warmup = [Int16](repeating: 0, count: sampleRate / 2)
        guard engine_sim_render(core, &warmup, Int32(warmup.count)) == Int32(warmup.count) else {
            return "Warmup render was incomplete"
        }

        let frameCount = audioSeconds * sampleRate
        var samples = [Int16](repeating: 0, count: frameCount)
        let start = DispatchTime.now().uptimeNanoseconds
        let rendered = engine_sim_render(core, &samples, Int32(frameCount))
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
        let peak = samples.map { abs(Int32($0)) }.max() ?? 0
        let audioDuration = Double(rendered) / Double(sampleRate)
        let ratio = elapsed / audioDuration
        let validAudio = rendered == Int32(frameCount) && peak > 0 && peak < Int32(Int16.max)
        let passes = validAudio && ratio <= 0.5

        return """
        Device: \(device) (\(system))
        Profile: F136 V8; target RPM: \(Int(targetRPM)); measured RPM: \(Int(engine_sim_rpm(core)))
        Simulation: \(engine_sim_simulation_frequency(core)) Hz; audio: \(sampleRate) Hz mono PCM16
        Frames: \(rendered)/\(frameCount); peak: \(peak); audio valid: \(validAudio)
        Compute duration: \(String(format: "%.3f", elapsed)) s
        Audio duration: \(String(format: "%.3f", audioDuration)) s
        Compute/audio ratio: \(String(format: "%.3f", ratio)); limit: 0.500
        Result: \(passes ? "PASS" : "FAIL")
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
                Button(isRunning ? "Running…" : "Run 3-second render") {
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
