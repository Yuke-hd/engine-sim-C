import XCTest
#if os(iOS)
import AVFoundation
#endif
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
            session.send(.outputRouteChanged(reason: .other, isAvailable: false))
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(session.releases, 1)
            session.send(.outputRouteChanged(reason: .newDeviceAvailable, isAvailable: true))
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
            session.send(.outputRouteChanged(reason: .other, isAvailable: false))
            session.send(.interruptionEnded(shouldResume: true))
            XCTAssertFalse(player.isPlaying)
            session.send(.outputRouteChanged(reason: .newDeviceAvailable, isAvailable: true))
            XCTAssertTrue(player.isPlaying)
            player.stop()
        }
    }

    func testOutputRemovalPausesUntilHostRequestsPlayback() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let player = EngineSoundPlayer(session: session)
            try player.start(ToneSource())
            // iOS falls back to the speaker, so the route stays available.
            session.send(.outputRouteChanged(reason: .oldDeviceUnavailable, isAvailable: true))
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(session.releases, 1)
            session.send(.outputRouteChanged(reason: .newDeviceAvailable, isAvailable: true))
            session.send(.interruptionBegan)
            session.send(.interruptionEnded(shouldResume: true))
            try player.switchSource(to: ToneSource())
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(session.acquires, 1)
            try player.start(ToneSource())
            XCTAssertTrue(player.isPlaying)
            XCTAssertEqual(session.acquires, 2)
            player.stop()
        }
    }

    func testSessionConfigurationRouteChangeKeepsPlayback() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let source = AdjustableSource()
            let player = EngineSoundPlayer(session: session)
            try player.start(source)
            XCTAssertEqual(source.controlThreadNames.count, 1)
            session.send(.outputRouteChanged(reason: .sessionConfiguration, isAvailable: true))
            XCTAssertTrue(player.isPlaying)
            // Each producer applies the initial scale once; no new producer means no restart.
            XCTAssertEqual(source.controlThreadNames.count, 1)
            XCTAssertEqual(session.acquires, 1)
            XCTAssertEqual(session.releases, 0)
            player.stop()
            XCTAssertEqual(session.releases, 1)
        }
    }

    func testRouteChangeRestartsEngineWithoutReleasingSession() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let source = AdjustableSource()
            let player = EngineSoundPlayer(session: session)
            try player.start(source)
            session.send(.outputRouteChanged(reason: .newDeviceAvailable, isAvailable: true))
            XCTAssertTrue(player.isPlaying)
            XCTAssertEqual(source.controlThreadNames.count, 2)
            XCTAssertEqual(session.acquires, 1)
            XCTAssertEqual(session.releases, 0)
            player.stop()
            XCTAssertEqual(session.releases, 1)
        }
    }

    func testSwitchSourceWhilePausedKeepsSystemDoNotResume() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let player = EngineSoundPlayer(session: session)
            try player.start(ToneSource())
            session.send(.interruptionBegan)
            session.send(.interruptionEnded(shouldResume: false))
            try player.switchSource(to: ToneSource())
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(session.acquires, 1)
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
            XCTAssertTrue(source.controlThreadNames.allSatisfy { $0 == "EngineSound producer" })
            player.stop()
        }
    }

    func testInitialAndPausedThermalControlsRunOnProducer() throws {
        try withAudioSimulator {
            let session = FakeSession()
            session.thermalState = .serious
            let source = AdjustableSource()
            let player = EngineSoundPlayer(session: session)
            try player.start(source)
            XCTAssertTrue(source.waitForScale(0.5))
            session.send(.interruptionBegan)
            XCTAssertFalse(player.isPlaying)
            let controlsBeforePause = source.controlThreadNames.count
            session.send(.thermalStateChanged(.nominal))
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(source.controlThreadNames.count, controlsBeforePause)
            session.send(.interruptionEnded(shouldResume: true))
            XCTAssertTrue(source.waitForScale(1))
            XCTAssertTrue(source.controlThreadNames.allSatisfy { $0 == "EngineSound producer" })
            player.stop()
        }
    }

    func testSlowSourceDoesNotBlockNotificationDelivery() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let source = SlowSource()
            let player = EngineSoundPlayer(session: session)
            try player.start(source)
            source.arm()
            XCTAssertEqual(source.entered.wait(timeout: .now() + 2), .success)
            let start = Date()
            session.send(.interruptionBegan)
            XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
            XCTAssertFalse(player.isPlaying)
            player.stop()
        }
    }

    func testFailedAutomaticResumeIsReportedAndCanRetry() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let player = EngineSoundPlayer(session: session)
            try player.start(ToneSource())
            session.send(.interruptionBegan)
            XCTAssertFalse(player.isPlaying)
            session.failNextAcquire = true
            let reported = expectation(description: "automatic restart failure")
            player.onPlaybackFailure = { _ in reported.fulfill() }
            session.send(.interruptionEnded(shouldResume: true))
            XCTAssertFalse(player.isPlaying)
            XCTAssertNotNil(player.lastPlaybackFailure)
            wait(for: [reported], timeout: 2)
            session.send(.outputRouteChanged(reason: .newDeviceAvailable, isAvailable: true))
            XCTAssertTrue(player.isPlaying)
            XCTAssertNil(player.lastPlaybackFailure)
            player.stop()
        }
    }

    func testSwitchAndRestartUseOneSampleRateSnapshot() throws {
        try withAudioSimulator {
            let session = FakeSession()
            let player = EngineSoundPlayer(session: session)
            try player.start(ToneSource())
            let source = ChangingRateSwitchSource()
            try player.switchSource(to: source)
            XCTAssertEqual(source.sampleRateReads, 1)
            session.send(.outputRouteChanged(reason: .other, isAvailable: false))
            XCTAssertFalse(player.isPlaying)
            session.send(.outputRouteChanged(reason: .newDeviceAvailable, isAvailable: true))
            XCTAssertTrue(player.isPlaying)
            XCTAssertEqual(source.sampleRateReads, 1)
            player.stop()
        }
    }

    #if os(iOS)
    func testIOSRouteReasonsMapToNeutralEvents() {
        XCTAssertEqual(IOSAudioSession.routeChangeEvent(reason: .oldDeviceUnavailable, category: .playback, hasOutputs: true),
                       .outputRouteChanged(reason: .oldDeviceUnavailable, isAvailable: true))
        XCTAssertEqual(IOSAudioSession.routeChangeEvent(reason: .newDeviceAvailable, category: .playback, hasOutputs: true),
                       .outputRouteChanged(reason: .newDeviceAvailable, isAvailable: true))
        XCTAssertEqual(IOSAudioSession.routeChangeEvent(reason: .categoryChange, category: .playback, hasOutputs: true),
                       .outputRouteChanged(reason: .sessionConfiguration, isAvailable: true))
        XCTAssertEqual(IOSAudioSession.routeChangeEvent(reason: .categoryChange, category: .ambient, hasOutputs: true),
                       .outputRouteChanged(reason: .other, isAvailable: true))
        XCTAssertEqual(IOSAudioSession.routeChangeEvent(reason: .noSuitableRouteForCategory, category: .playback,
                                                        hasOutputs: true),
                       .outputRouteChanged(reason: .other, isAvailable: false))
    }

    func testIOSNotificationDeliveryCanOverlapPlayerTeardown() {
        let session = IOSAudioSession()
        let ready = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = expectation(description: "player teardown")
        DispatchQueue.global().async {
            do {
                // The player's last strong reference ends with this scope.
                let player = EngineSoundPlayer(session: session)
                ready.signal()
                release.wait()
                withExtendedLifetime(player) {}
            }
            finished.fulfill()
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 2), .success)
        let center = NotificationCenter.default
        let audioSession = AVAudioSession.sharedInstance()
        for _ in 0..<20 {
            center.post(name: AVAudioSession.routeChangeNotification, object: audioSession)
        }
        release.signal()
        for _ in 0..<20 {
            center.post(name: AVAudioSession.routeChangeNotification, object: audioSession)
        }
        wait(for: [finished], timeout: 2)
        // A queued control block can briefly keep the player alive, and a weak
        // reference clears before deinit runs, so wait for the detach itself.
        let deadline = Date().addingTimeInterval(2)
        while session.onEvent != nil, Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
        XCTAssertNil(session.onEvent)
        var delivered: [EngineSoundSessionEvent] = []
        session.onEvent = { delivered.append($0) }
        center.post(name: AVAudioSession.routeChangeNotification, object: audioSession,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue])
        XCTAssertEqual(delivered.last, .outputRouteChanged(reason: .oldDeviceUnavailable,
                                                           isAvailable: session.isOutputAvailable))
        session.onEvent = nil
    }
    #endif

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
    var failNextAcquire = false

    func acquire(policy: AudioSessionMixPolicy) throws {
        acquires += 1
        if failNextAcquire {
            failNextAcquire = false
            throw FakeSessionError.acquireFailed
        }
    }
    func release(policy: AudioSessionMixPolicy) { releases += 1 }
    func send(_ event: EngineSoundSessionEvent) { onEvent?(event) }
}

private enum FakeSessionError: Error { case acquireFailed }

private final class AdjustableSource: EngineSoundSource, EngineSoundThermalControllable {
    private let tone = ToneSource()
    private let lock = NSLock()
    private var scale = 1.0
    private var names: [String] = []
    var controlThreadNames: [String] {
        lock.lock()
        defer { lock.unlock() }
        return names
    }
    var sampleRate: Double { tone.sampleRate }
    func setTargetRPM(_ rpm: Double) { tone.setTargetRPM(rpm) }
    func setThrottle(_ throttle: Double) { tone.setThrottle(throttle) }
    func setIgnition(_ enabled: Bool) { tone.setIgnition(enabled) }
    func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int { tone.render(into: frames) }
    func setSimulationFrequencyScale(_ value: Double) {
        lock.lock()
        scale = value
        names.append(Thread.current.name ?? "")
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

private final class SlowSource: EngineSoundSource {
    private let tone = ToneSource()
    private let lock = NSLock()
    private var sleepOnNextRender = false
    let entered = DispatchSemaphore(value: 0)
    var sampleRate: Double { tone.sampleRate }
    func setTargetRPM(_ rpm: Double) { tone.setTargetRPM(rpm) }
    func setThrottle(_ throttle: Double) { tone.setThrottle(throttle) }
    func setIgnition(_ enabled: Bool) { tone.setIgnition(enabled) }
    func arm() {
        lock.lock()
        sleepOnNextRender = true
        lock.unlock()
    }
    func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int {
        lock.lock()
        let shouldSleep = sleepOnNextRender
        sleepOnNextRender = false
        lock.unlock()
        if shouldSleep {
            entered.signal()
            Thread.sleep(forTimeInterval: 0.4)
        }
        return tone.render(into: frames)
    }
}

private final class ChangingRateSwitchSource: EngineSoundSource {
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
