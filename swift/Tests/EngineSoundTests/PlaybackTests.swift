import XCTest
@testable import EngineSound

final class PlaybackTests: XCTestCase {
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
        XCTAssertEqual(player.underrunCount, 0)
        player.stop() // Waits for the producer thread to finish.
        #endif
    }
}
