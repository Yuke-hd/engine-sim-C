import EngineSimCore
import XCTest

final class ControlAPITests: XCTestCase {
    func testProfilesAndInvalidHandles() throws {
        XCTAssertNil(engine_sim_create(EngineSimProfile(rawValue: 99), 0))
        engine_sim_destroy(nil)
        engine_sim_set_target_rpm(nil, 3000)
        engine_sim_set_throttle(nil, 0.5)
        engine_sim_set_ignition(nil, 1)
        XCTAssertEqual(engine_sim_render(nil, nil, 1), 0)
        XCTAssertEqual(engine_sim_rpm(nil), 0)
        XCTAssertEqual(engine_sim_simulation_frequency(nil), 0)
        let core = try XCTUnwrap(engine_sim_create(ENGINE_SIM_PROFILE_LS_V8, 0))
        defer { engine_sim_destroy(core) }
        XCTAssertEqual(engine_sim_simulation_frequency(core), ENGINE_SIM_DEFAULT_FREQUENCY)
        XCTAssertEqual(engine_sim_render(core, nil, 1), 0)
    }

    func testIndependentControlsAndInvalidNumbers() throws {
        let core = try XCTUnwrap(engine_sim_create(ENGINE_SIM_PROFILE_LS_V8, 0))
        defer { engine_sim_destroy(core) }
        engine_sim_set_target_rpm(core, 3000)
        engine_sim_set_throttle(core, 10) // Clamps to one.
        engine_sim_set_target_rpm(core, .nan)
        engine_sim_set_target_rpm(core, .infinity)
        engine_sim_set_throttle(core, .nan)
        engine_sim_set_throttle(core, -.infinity)
        var samples = [Int16](repeating: 123, count: 22050)
        XCTAssertEqual(engine_sim_render(core, &samples, 22050), 22050)
        XCTAssertTrue(samples.allSatisfy { $0 == 0 }, "controls must not enable ignition")
        XCTAssertEqual(engine_sim_rpm(core), 3000, accuracy: 60)
        engine_sim_set_ignition(core, 1)
        XCTAssertEqual(engine_sim_render(core, &samples, 22050), 22050)
        XCTAssertTrue(samples.contains { $0 != 0 })
        engine_sim_set_ignition(core, 0)
        XCTAssertEqual(engine_sim_render(core, &samples, 22050), 22050)
        XCTAssertTrue(samples.allSatisfy { $0 == 0 })
    }

    func testTargetRPMClampsToDocumentedBounds() throws {
        let core = try XCTUnwrap(engine_sim_create(ENGINE_SIM_PROFILE_LS_V8, 0))
        defer { engine_sim_destroy(core) }
        // Advance the same half-second at each bound in producer-sized frames.
        // A single large offline request can hit render's wall-clock timeout on
        // slow simulator hosts even while physics is still producing samples.
        let frameCount: Int32 = ENGINE_SIM_SAMPLE_RATE / 60
        var samples = [Int16](repeating: 0, count: Int(frameCount))
        for (requested, expected) in [(-100.0, 0.0), (10000.0, 8000.0)] {
            engine_sim_set_target_rpm(core, requested)
            for _ in 0..<30 {
                XCTAssertEqual(engine_sim_render(core, &samples, frameCount), frameCount)
            }
            XCTAssertEqual(engine_sim_rpm(core), expected, accuracy: expected == 0 ? 1 : 160)
        }
    }

    func testNonpositiveRenderPreservesOutput() throws {
        let core = try XCTUnwrap(engine_sim_create(ENGINE_SIM_PROFILE_LS_V8, 0))
        defer { engine_sim_destroy(core) }
        var frame: Int16 = 123
        XCTAssertEqual(engine_sim_render(core, &frame, -1), 0)
        XCTAssertEqual(engine_sim_render(core, &frame, 0), 0)
        XCTAssertEqual(frame, 123)
    }
}
