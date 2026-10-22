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
        var samples = [Int16](repeating: 0, count: 22050)
        engine_sim_set_target_rpm(core, -100)
        XCTAssertEqual(engine_sim_render(core, &samples, 22050), 22050)
        XCTAssertEqual(engine_sim_rpm(core), 0, accuracy: 1)
        engine_sim_set_target_rpm(core, 10000)
        XCTAssertEqual(engine_sim_render(core, &samples, 22050), 22050)
        XCTAssertEqual(engine_sim_rpm(core), 8000, accuracy: 160)
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
