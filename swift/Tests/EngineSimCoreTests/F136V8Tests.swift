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

            // Report both the loudest audio component and the firing-order
            // component; a split-bank V8 can emphasize a lower engine order.
            let expected = rpm / 60 * 4
            let count = 16384
            let start = (samples.count - count) / 2
            var real = (0..<count).map { i in
                let window = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(count - 1))
                return Double(samples[start + i]) * window
            }
            var imaginary = [Double](repeating: 0, count: count)
            var j = 0
            for i in 1..<count {
                var bit = count >> 1
                while j & bit != 0 {
                    j ^= bit
                    bit >>= 1
                }
                j ^= bit
                if i < j {
                    real.swapAt(i, j)
                    imaginary.swapAt(i, j)
                }
            }
            var width = 2
            while width <= count {
                let half = width / 2
                let angle = -2 * Double.pi / Double(width)
                for base in stride(from: 0, to: count, by: width) {
                    for offset in 0..<half {
                        let phase = angle * Double(offset)
                        let cosine = cos(phase)
                        let sine = sin(phase)
                        let even = base + offset
                        let odd = even + half
                        let oddReal = real[odd] * cosine - imaginary[odd] * sine
                        let oddImaginary = real[odd] * sine + imaginary[odd] * cosine
                        real[odd] = real[even] - oddReal
                        imaginary[odd] = imaginary[even] - oddImaginary
                        real[even] += oddReal
                        imaginary[even] += oddImaginary
                    }
                }
                width <<= 1
            }
            var dominantBin = 1
            var dominantPower = 0.0
            for bin in 1..<(count / 2) {
                let power = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
                if power > dominantPower {
                    dominantPower = power
                    dominantBin = bin
                }
            }
            let dominant = Double(dominantBin) * 44100 / Double(count)
            let lowBin = Int((expected * 0.9 * Double(count) / 44100).rounded(.up))
            let highBin = Int((expected * 1.1 * Double(count) / 44100).rounded(.down))
            var firingBin = lowBin
            var firingPower = 0.0
            for bin in lowBin...highBin {
                let power = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
                if power > firingPower {
                    firingPower = power
                    firingBin = bin
                }
            }
            let firingFrequency = Double(firingBin) * 44100 / Double(count)
            print("F136 \(Int(rpm)) RPM: global peak \(dominant) Hz; firing-order peak \(firingFrequency) Hz; expected \(expected) Hz; firing/global power \(firingPower / dominantPower); RMS \(rms); peak \(peak)")
            XCTAssertGreaterThan(firingPower, 0)
            XCTAssertEqual(firingFrequency, expected, accuracy: expected * 0.03)
        }
    }
}
