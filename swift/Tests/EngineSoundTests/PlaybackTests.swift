import XCTest
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

    func testTonePlaysForSixtySecondsWithoutUnderruns() throws {
        #if !os(iOS)
        throw XCTSkip("Requires an audio-enabled iOS Simulator")
        #else
        let player = EngineSoundPlayer()
        let tone = ToneSource(frequency: 110)
        try player.start(tone)
        Thread.sleep(forTimeInterval: 60)
        XCTAssertGreaterThan(player.consumedFrameCount, Int(tone.sampleRate * 30))
        XCTAssertEqual(player.underrunCount, 0)
        player.stop() // Waits for the producer thread to finish.
        #endif
    }
}
