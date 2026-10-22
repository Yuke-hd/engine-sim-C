import XCTest
#if os(iOS)
import AVFoundation
#endif
@testable import EngineSound

final class PlaybackTests: XCTestCase {
    func testExtremeFiniteSampleRateIsRejected() {
        let player = EngineSoundPlayer()
        XCTAssertThrowsError(try player.start(ToneSource(sampleRate: 1e20))) { error in
            guard case EngineSoundPlayerError.invalidSampleRate = error else {
                return XCTFail("Expected invalidSampleRate, got \(error)")
            }
        }
    }

    func testSwitchSourceAndStop() throws {
        #if !os(iOS)
        throw XCTSkip("Requires an audio-enabled iOS Simulator")
        #else
        let player = EngineSoundPlayer()
        try player.start(ToneSource(frequency: 110), policy: .mixWithOthers)
        try player.switchSource(to: ToneSource(frequency: 130))
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(player.underrunCount, 0)
        player.stop()
        #endif
    }

    func testStoppingOnePlayerKeepsOtherPlayerActive() throws {
        #if !os(iOS)
        throw XCTSkip("Requires an audio-enabled iOS Simulator")
        #else
        let first = EngineSoundPlayer()
        let second = EngineSoundPlayer()
        try first.start(ToneSource(frequency: 110), policy: .mixWithOthers)
        defer { first.stop() }
        try second.start(ToneSource(frequency: 130), policy: .mixWithOthers)
        defer { second.stop() }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertGreaterThan(first.consumedFrameCount, 2_205)
        XCTAssertGreaterThan(second.consumedFrameCount, 2_205)
        first.stop()
        let before = second.consumedFrameCount
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertGreaterThan(second.consumedFrameCount - before, 4_410)
        #endif
    }

    func testStoppingDuckPlayerRestoresMixPolicy() throws {
        #if !os(iOS)
        throw XCTSkip("Requires an audio-enabled iOS Simulator")
        #else
        let mixPlayer = EngineSoundPlayer()
        let duckPlayer = EngineSoundPlayer()
        let session = AVAudioSession.sharedInstance()
        try mixPlayer.start(ToneSource(frequency: 110), policy: .mixWithOthers)
        defer { mixPlayer.stop() }
        try duckPlayer.start(ToneSource(frequency: 130), policy: .duckOthers)
        defer { duckPlayer.stop() }
        XCTAssertTrue(session.categoryOptions.contains(.duckOthers))
        duckPlayer.stop()
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers))
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers))
        #endif
    }

    func testStartReadsSampleRateOnce() throws {
        #if !os(iOS)
        throw XCTSkip("Requires an audio-enabled iOS Simulator")
        #else
        let source = ChangingRateSource()
        let player = EngineSoundPlayer()
        try player.start(source)
        XCTAssertEqual(source.sampleRateReads, 1)
        player.stop()
        #endif
    }

    func testTonePlaysForSixtySecondsWithoutUnderruns() throws {
        #if !os(iOS)
        throw XCTSkip("Requires an audio-enabled iOS Simulator")
        #else
        let player = EngineSoundPlayer()
        let tone = ToneSource(frequency: 110)
        try player.start(tone)
        defer { player.stop() }
        var previousFrames = 0
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 10)
            let frames = player.consumedFrameCount
            XCTAssertGreaterThan(frames - previousFrames, Int(tone.sampleRate * 8))
            previousFrames = frames
        }
        XCTAssertGreaterThan(previousFrames, Int(tone.sampleRate * 55))
        XCTAssertEqual(player.underrunCount, 0)
        #endif
    }
}

#if os(iOS)
private final class ChangingRateSource: EngineSoundSource {
    private let tone = ToneSource()
    private(set) var sampleRateReads = 0
    var sampleRate: Double {
        sampleRateReads += 1
        return sampleRateReads == 1 ? 44_100 : 1e20
    }

    func setTargetRPM(_ rpm: Double) { tone.setTargetRPM(rpm) }
    func setThrottle(_ throttle: Double) { tone.setThrottle(throttle) }
    func setIgnition(_ enabled: Bool) { tone.setIgnition(enabled) }
    func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int { tone.render(into: frames) }
}
#endif
