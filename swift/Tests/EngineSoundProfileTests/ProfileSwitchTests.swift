import EngineSimCore
@testable import EngineSound
import Foundation
import XCTest

final class ProfileSwitchTests: XCTestCase {
    /// Feeds offline LS and F136 renders through the player's gain stage at the
    /// LS/F136 splice with the largest level jump, so an abrupt switch would click.
    func testLsToF136CrossfadeHasNoClick() throws {
        let block = 256
        let ls = try Self.render(ENGINE_SIM_PROFILE_LS_V8, rpm: 3_000, frames: 22_050)
        let f136 = try Self.render(ENGINE_SIM_PROFILE_F136_V8, rpm: 3_000, frames: 22_050)
        func maxStep(_ samples: ArraySlice<Int16>) -> Int {
            zip(samples, samples.dropFirst()).map { abs(Int($1) - Int($0)) }.max() ?? 0
        }

        // Leave the startup fade behind, then pick the LS block boundary and F136
        // starting offset whose splice is the largest step between the sources.
        var switchBlock = 8
        var f136Offset = 0
        var spliceJump = -1
        for blockIndex in 8..<(ls.count / block - 8) {
            let last = Int(ls[blockIndex * block - 1])
            for offset in 0..<(f136.count - 8 * block) where abs(Int(f136[offset]) - last) > spliceJump {
                spliceJump = abs(Int(f136[offset]) - last)
                switchBlock = blockIndex
                f136Offset = offset
            }
        }

        var mixer = CrossfadeMixer(fadeFrames: Int(44_100 * 0.02))
        var output: [Int16] = []
        var mixed = [Int16](repeating: 0, count: block)
        let silence = [Int16](repeating: 0, count: block)
        for blockIndex in 0..<switchBlock {
            let primary = Array(ls[(blockIndex * block)..<((blockIndex + 1) * block)])
            _ = mixer.mix(primary: primary, secondary: silence, into: &mixed)
            output += mixed
        }
        let switchFrame = output.count
        mixer.beginSwitch()
        var lsIndex = switchBlock * block
        var f136Index = f136Offset
        var completed = false
        while !completed {
            let primary = Array(ls[lsIndex..<(lsIndex + block)])
            let secondary = Array(f136[f136Index..<(f136Index + block)])
            completed = mixer.mix(primary: primary, secondary: secondary, into: &mixed).switchCompleted
            output += mixed
            lsIndex += block
            f136Index += block
        }
        XCTAssertFalse(mixer.isSwitching)
        for _ in 0..<4 {
            _ = mixer.mix(primary: Array(f136[f136Index..<(f136Index + block)]), secondary: silence, into: &mixed)
            output += mixed
            f136Index += block
        }

        // A linear fade adds at most |b - a| / fadeFrames per sample to the steps
        // already present in either scaled source; an abrupt splice adds |b - a|.
        let sourceStep = max(maxStep(ls[(switchFrame - block)..<lsIndex]), maxStep(f136[f136Offset..<f136Index]))
        let bound = Int((0.8 * Double(sourceStep) + 0.8 * 65_535 / Double(mixer.fadeFrames)).rounded(.up)) + 1
        let abruptStep = Int((0.8 * Double(spliceJump)).rounded())
        let transitionStep = maxStep(output[(switchFrame - block)...])
        print("LS->F136 splice jump \(spliceJump), abrupt step \(abruptStep), source step \(sourceStep), "
              + "cross-fade step \(transitionStep), bound \(bound)")
        XCTAssertGreaterThan(abruptStep, bound, "the chosen splice would not expose an abrupt switch")
        XCTAssertLessThanOrEqual(transitionStep, bound, "the LS-to-F136 cross-fade produced a click")
        let fadeOutput = output[switchFrame...]
        XCTAssertTrue(fadeOutput.contains { $0 != 0 }, "the cross-fade was silent")
        XCTAssertFalse(fadeOutput.contains { $0 == .max || $0 == .min }, "the cross-fade clipped")
    }

    private static func render(_ profile: EngineSimProfile, rpm: Double, frames: Int) throws -> [Int16] {
        let core = try XCTUnwrap(engine_sim_create(profile, 1_000))
        defer { engine_sim_destroy(core) }
        engine_sim_hold_rpm(core, rpm)
        var warmup = [Int16](repeating: 0, count: 22_050)
        var samples = [Int16](repeating: 0, count: frames)
        XCTAssertEqual(engine_sim_render(core, &warmup, Int32(warmup.count)), Int32(warmup.count))
        XCTAssertEqual(engine_sim_render(core, &samples, Int32(frames)), Int32(frames))
        return samples
    }

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
