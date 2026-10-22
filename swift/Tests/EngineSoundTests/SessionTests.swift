import XCTest
@testable import EngineSound

final class SessionTests: XCTestCase {
    func testInterruptionResumesOnlyWhenRequestedAndAllowed() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let player = EngineSoundPlayer(session: session)
            try player.start(ToneSource())
            XCTAssertTrue(player.isPlaying)
            session.send(.interruptionBegan)
            XCTAssertFalse(player.isPlaying)
            session.send(.interruptionEnded(shouldResume: true))
            XCTAssertTrue(player.isPlaying)
            session.send(.interruptionBegan)
            session.send(.interruptionEnded(shouldResume: false))
            XCTAssertFalse(player.isPlaying)
            player.stop()
        }
    }

    func testUserStopWhileInterruptedDoesNotResume() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let player = EngineSoundPlayer(session: session)
            try player.start(ToneSource())
            session.send(.interruptionBegan)
            player.stop()
            session.send(.interruptionEnded(shouldResume: true))
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(session.acquires, 1)
            XCTAssertEqual(session.releases, 1)
        }
    }

    func testRouteLossStopsProducerAndRecoveryRestarts() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let player = EngineSoundPlayer(session: session)
            try player.start(ToneSource())
            session.send(.outputRouteChanged(isAvailable: false))
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(session.releases, 1)
            session.send(.outputRouteChanged(isAvailable: true))
            XCTAssertTrue(player.isPlaying)
            XCTAssertEqual(session.acquires, 2)
            player.stop()
        }
    }

    func testInterruptionEndWaitsForOutputRoute() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let player = EngineSoundPlayer(session: session)
            try player.start(ToneSource())
            session.send(.interruptionBegan)
            session.send(.outputRouteChanged(isAvailable: false))
            session.send(.interruptionEnded(shouldResume: true))
            XCTAssertFalse(player.isPlaying)
            session.send(.outputRouteChanged(isAvailable: true))
            XCTAssertTrue(player.isPlaying)
            player.stop()
        }
    }

    func testThermalTransitionsLowerFrequencyAndPauseAtCritical() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let source = AdjustableSource()
            let player = EngineSoundPlayer(session: session)
            try player.start(source)
            session.send(.thermalStateChanged(.serious))
            XCTAssertTrue(player.isPlaying)
            XCTAssertTrue(source.waitForScale(0.5))
            session.send(.thermalStateChanged(.critical))
            XCTAssertFalse(player.isPlaying)
            session.send(.thermalStateChanged(.nominal))
            XCTAssertTrue(player.isPlaying)
            XCTAssertTrue(source.waitForScale(1))
            player.stop()
        }
    }

    private func withAudioSimulator(_ body: () throws -> Void) throws {
        #if os(iOS)
        try body()
        #else
        throw XCTSkip("Requires an audio-enabled iOS Simulator")
        #endif
    }
}

private final class FakeSession: EngineSoundSession {
    var isOutputAvailable = true
    var thermalState: EngineSoundThermalState = .nominal
    var onEvent: ((EngineSoundSessionEvent) -> Void)?
    private(set) var acquires = 0
    private(set) var releases = 0

    func acquire(policy: AudioSessionMixPolicy) throws { acquires += 1 }
    func release(policy: AudioSessionMixPolicy) { releases += 1 }
    func send(_ event: EngineSoundSessionEvent) { onEvent?(event) }
}

private final class AdjustableSource: EngineSoundSource, EngineSoundThermalControllable {
    private let tone = ToneSource()
    private let lock = NSLock()
    private var scale = 1.0
    var sampleRate: Double { tone.sampleRate }
    func setTargetRPM(_ rpm: Double) { tone.setTargetRPM(rpm) }
    func setThrottle(_ throttle: Double) { tone.setThrottle(throttle) }
    func setIgnition(_ enabled: Bool) { tone.setIgnition(enabled) }
    func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int { tone.render(into: frames) }
    func setSimulationFrequencyScale(_ value: Double) {
        lock.lock()
        scale = value
        lock.unlock()
    }
    func waitForScale(_ expected: Double) -> Bool {
        for _ in 0..<100 {
            lock.lock()
            let matches = scale == expected
            lock.unlock()
            if matches { return true }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }
}
