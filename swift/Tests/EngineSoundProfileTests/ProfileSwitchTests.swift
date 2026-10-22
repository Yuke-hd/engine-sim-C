import EngineSimCore
import EngineSound
import Foundation
import XCTest

final class ProfileSwitchTests: XCTestCase {
    func testPlayerCrossfadesFromLsToF136AndReleasesOldCore() throws {
        #if os(iOS) && targetEnvironment(simulator)
        let player = EngineSoundPlayer()
        var oldSource: ProfileSource? = try ProfileSource(profile: ENGINE_SIM_PROFILE_LS_V8)
        weak let releasedSource = oldSource
        var nextSource: ProfileSource? = try ProfileSource(profile: ENGINE_SIM_PROFILE_F136_V8)
        weak let releasedNextSource = nextSource
        try player.start(try XCTUnwrap(oldSource), policy: .mixWithOthers)
        defer { player.stop() }

        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertGreaterThan(try XCTUnwrap(oldSource).nonzeroFrames, 0)
        let framesBeforeSwitch = player.consumedFrameCount
        try player.switchSource(to: try XCTUnwrap(nextSource))
        oldSource = nil

        // The worker's 20 ms fade must finish and release its LS source.
        Thread.sleep(forTimeInterval: 0.5)
        XCTAssertNil(releasedSource, "the LS core was retained after the cross-fade")
        XCTAssertGreaterThan(try XCTUnwrap(nextSource).nonzeroFrames, 0, "the F136 source was silent")
        XCTAssertGreaterThan(player.consumedFrameCount - framesBeforeSwitch, 4_410)
        XCTAssertEqual(player.underrunCount, 0, "playback ran out of audio during replacement")
        player.stop()
        nextSource = nil
        XCTAssertNil(releasedNextSource, "the F136 core was retained after stopping")
        #else
        throw XCTSkip("Requires an audio-enabled iOS Simulator")
        #endif
    }
}

private final class ProfileSource: EngineSoundSource {
    let sampleRate = 44_100.0
    private let core: OpaquePointer
    private let samples: [Int16]
    private let lock = NSLock()
    private var nonzeroFrameTotal = 0
    private var offset = 0

    init(profile: EngineSimProfile) throws {
        guard let core = engine_sim_create(profile, 1_000) else {
            throw NSError(domain: "ProfileSwitchTests", code: 1)
        }
        self.core = core
        engine_sim_hold_rpm(core, 3_000)
        var warmup = [Int16](repeating: 0, count: 22_050)
        var rendered = [Int16](repeating: 0, count: 88_200)
        guard engine_sim_render(core, &warmup, Int32(warmup.count)) == Int32(warmup.count),
              engine_sim_render(core, &rendered, Int32(rendered.count)) == Int32(rendered.count) else {
            engine_sim_destroy(core)
            throw NSError(domain: "ProfileSwitchTests", code: 2)
        }
        samples = rendered
    }

    deinit { engine_sim_destroy(core) }

    var nonzeroFrames: Int {
        lock.lock()
        defer { lock.unlock() }
        return nonzeroFrameTotal
    }

    func setTargetRPM(_ rpm: Double) { engine_sim_set_target_rpm(core, rpm) }
    func setThrottle(_ throttle: Double) { engine_sim_set_throttle(core, throttle) }
    func setIgnition(_ enabled: Bool) { engine_sim_set_ignition(core, enabled ? 1 : 0) }

    func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int {
        let count = min(frames.count, samples.count - offset)
        guard count > 0 else { return 0 }
        for index in 0..<count { frames[index] = samples[offset + index] }
        offset += count
        let audible = frames.prefix(count).filter { $0 != 0 }.count
        lock.lock()
        nonzeroFrameTotal += audible
        lock.unlock()
        return count
    }
}
