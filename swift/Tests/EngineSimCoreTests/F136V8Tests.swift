import EngineSimCore
import XCTest

final class F136V8Tests: XCTestCase {
    func testProfileCreationBoundsSwitchingAndCleanup() throws {
        XCTAssertEqual(engine_sim_profile_max_rpm(ENGINE_SIM_PROFILE_F136_V8), 9000)
        XCTAssertEqual(engine_sim_profile_min_rpm(ENGINE_SIM_PROFILE_F136_V8), 0)
        XCTAssertEqual(engine_sim_profile_max_rpm(EngineSimProfile(rawValue: 99)), 0)

        for profile in [ENGINE_SIM_PROFILE_LS_V8, ENGINE_SIM_PROFILE_F136_V8,
                        ENGINE_SIM_PROFILE_LS_V8, ENGINE_SIM_PROFILE_F136_V8] {
            let core = try XCTUnwrap(engine_sim_create(profile, 5000))
            XCTAssertEqual(engine_sim_profile(core), profile)
            XCTAssertEqual(engine_sim_simulation_frequency(core), 5000)
            engine_sim_hold_rpm(core, 12000)
            var samples = [Int16](repeating: 0, count: 22050)
            XCTAssertEqual(engine_sim_render(core, &samples, Int32(samples.count)), Int32(samples.count))
            XCTAssertEqual(engine_sim_rpm(core), engine_sim_profile_max_rpm(profile), accuracy: 180)
            engine_sim_destroy(core)
        }
    }

    func testRepresentativeFiringFrequencyAndAudioLevel() throws {
        for rpm in [3000.0, 6000.0] {
            let core = try XCTUnwrap(engine_sim_create(ENGINE_SIM_PROFILE_F136_V8, 5000))
            defer { engine_sim_destroy(core) }
            engine_sim_hold_rpm(core, rpm)
            var warmup = [Int16](repeating: 0, count: 22050)
            XCTAssertEqual(engine_sim_render(core, &warmup, 22050), 22050)
            var samples = [Int16](repeating: 0, count: 22050)
            XCTAssertEqual(engine_sim_render(core, &samples, 22050), 22050)

            let peak = samples.map { abs(Int32($0)) }.max() ?? 0
            let rms = (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
            XCTAssertGreaterThan(rms, 100)
            XCTAssertLessThan(peak, Int32(Int16.max))
            XCTAssertEqual(engine_sim_rpm(core), rpm, accuracy: rpm * 0.02)

            // Find the strongest spectral component near the expected four
            // firing events per crankshaft revolution.
            let expected = rpm / 60 * 4
            let count = 16384
            let start = (samples.count - count) / 2
            func power(at frequency: Double) -> Double {
                let step = 2 * Double.pi * frequency / 44100
                var re = 0.0
                var im = 0.0
                for i in 0..<count {
                    let x = Double(samples[start + i])
                    re += x * cos(Double(i) * step)
                    im += x * sin(Double(i) * step)
                }
                return re * re + im * im
            }
            let frequencies = stride(from: expected * 0.9, through: expected * 1.1, by: 1.0)
            let dominant = frequencies.max { power(at: $0) < power(at: $1) } ?? 0
            print("F136 \(Int(rpm)) RPM: firing peak \(dominant) Hz; expected \(expected) Hz; RMS \(rms); peak \(peak)")
            XCTAssertEqual(dominant, expected, accuracy: expected * 0.03)
        }
    }

    func testIPhoneRenderBenchmark() throws {
        #if os(iOS) && !targetEnvironment(simulator)
        let core = try XCTUnwrap(engine_sim_create(ENGINE_SIM_PROFILE_F136_V8, 1000))
        defer { engine_sim_destroy(core) }
        engine_sim_hold_rpm(core, 3000)
        let seconds = 3
        var samples = [Int16](repeating: 0, count: seconds * 44100)
        let started = DispatchTime.now().uptimeNanoseconds
        XCTAssertEqual(engine_sim_render(core, &samples, Int32(samples.count)), Int32(samples.count))
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1e9
        XCTAssertTrue(samples.contains { $0 != 0 })
        XCTAssertLessThan(samples.map { abs(Int32($0)) }.max() ?? 0, Int32(Int16.max))
        print("F136 iPhone benchmark: 1000 Hz physics, 44.1 kHz audio, \(elapsed / Double(seconds)) compute/audio ratio")
        XCTAssertLessThanOrEqual(elapsed / Double(seconds), 0.5)
        #else
        throw XCTSkip("iPhone hardware required for the 2x real-time acceptance criterion")
        #endif
    }
}
