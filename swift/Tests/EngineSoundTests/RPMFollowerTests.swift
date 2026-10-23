import XCTest
@testable import EngineSound

final class RPMFollowerTests: XCTestCase {
    private let range = 800.0...6_000.0

    func testInterpolatesBetweenLiveReadings() {
        var follower = RPMFollower(rpmRange: range, interpolationDuration: 0.2)
        _ = follower.update(.init(rpm: 1_000, freshness: .verified, age: 0,
                                  acceleratorThrottle: 0.2, sampleTime: 0))
        _ = follower.update(.init(rpm: 3_000, freshness: .verified, age: 0,
                                  acceleratorThrottle: 0.8, sampleTime: 0.1))
        let midpoint = follower.output(at: 0.2)
        XCTAssertEqual(midpoint.targetRPM, 2_000, accuracy: 0.001)
        XCTAssertEqual(midpoint.throttle, 0.5, accuracy: 0.001)
        XCTAssertEqual(midpoint.gain, 1, accuracy: 0.001)
        XCTAssertFalse(midpoint.isThrottleDerived)
    }

    func testClampsRPMAndAcceleratorThrottle() {
        var follower = RPMFollower(rpmRange: range, interpolationDuration: 0)
        let high = follower.update(.init(rpm: 9_000, freshness: .verified, age: 0,
                                         acceleratorThrottle: 2, sampleTime: 0))
        XCTAssertEqual(high.targetRPM, 6_000)
        XCTAssertEqual(high.throttle, 1)
        let low = follower.update(.init(rpm: 100, freshness: .verified, age: 0,
                                        acceleratorThrottle: -1, sampleTime: 1))
        XCTAssertEqual(low.targetRPM, 800)
        XCTAssertEqual(low.throttle, 0)
    }

    func testUnknownStaleAndDisconnectedReadingsDiscardRPMAndFadeToSilence() {
        for freshness in [RPMFreshness.stale, .disconnected] {
            var follower = RPMFollower(rpmRange: range, fadeDuration: 0.2)
            _ = follower.update(.init(rpm: 3_000, freshness: .verified, age: 0,
                                      acceleratorThrottle: 0.5, sampleTime: 0))
            let invalid = follower.update(.init(rpm: 5_000, freshness: freshness, age: 0,
                                                acceleratorThrottle: 1, sampleTime: 0.1))
            XCTAssertEqual(invalid.targetRPM, 800)
            XCTAssertEqual(invalid.throttle, 0)
            XCTAssertEqual(follower.output(at: 0.2).gain, 0.5, accuracy: 0.001)
            XCTAssertEqual(follower.output(at: 0.3).gain, 0, accuracy: 0.001)
        }
        var follower = RPMFollower(rpmRange: range)
        let unknown = follower.update(.init(rpm: nil, freshness: .verified, age: 0,
                                            acceleratorThrottle: nil, sampleTime: 0))
        XCTAssertEqual(unknown.targetRPM, 800)
        XCTAssertEqual(unknown.gain, 0)
    }

    func testRepeatedInvalidReadingsDoNotRestartTheFade() {
        var follower = RPMFollower(rpmRange: range, fadeDuration: 0.2)
        _ = follower.update(.init(rpm: 3_000, freshness: .verified, age: 0,
                                  acceleratorThrottle: 0.5, sampleTime: 0))
        _ = follower.update(.init(rpm: 3_000, freshness: .stale, age: 0,
                                  acceleratorThrottle: 0.5, sampleTime: 0.1))
        let disconnected = follower.update(.init(rpm: nil, freshness: .disconnected,
                                                 age: nil, acceleratorThrottle: nil,
                                                 sampleTime: 0.2))
        XCTAssertEqual(disconnected.gain, 0.5, accuracy: 0.001)
        let unknown = follower.update(.init(rpm: nil, freshness: .unverified,
                                            age: nil, acceleratorThrottle: nil,
                                            sampleTime: 0.3))
        XCTAssertEqual(unknown.targetRPM, 800)
        XCTAssertEqual(unknown.throttle, 0)
        XCTAssertEqual(unknown.gain, 0, accuracy: 0.001)
        XCTAssertEqual(follower.output(at: 1).gain, 0)
    }

    func testInvalidUpdateAfterAgeExpiryKeepsExpiryFadeDeadline() {
        var follower = RPMFollower(rpmRange: range, maxReadingAge: 0.2,
                                   fadeDuration: 0.2)
        _ = follower.update(.init(rpm: 3_000, freshness: .verified, age: 0,
                                  acceleratorThrottle: 0.5, sampleTime: 0))
        let stale = follower.update(.init(rpm: nil, freshness: .stale, age: nil,
                                          acceleratorThrottle: nil, sampleTime: 0.3))
        XCTAssertEqual(stale.gain, 0.5, accuracy: 0.001)
        XCTAssertEqual(follower.output(at: 0.4).gain, 0, accuracy: 0.001)
    }

    func testReadingExpiresWithoutAnotherUpdate() {
        var follower = RPMFollower(rpmRange: range, maxReadingAge: 0.3, fadeDuration: 0.2)
        _ = follower.update(.init(rpm: 3_000, freshness: .verified, age: 0.1,
                                  acceleratorThrottle: 0.5, sampleTime: 0))
        XCTAssertEqual(follower.output(at: 0.19).gain, 1)
        XCTAssertEqual(follower.output(at: 0.21).targetRPM, 800)
        XCTAssertEqual(follower.output(at: 0.41).gain, 0, accuracy: 0.001)
    }

    func testStallAndReconnect() {
        var follower = RPMFollower(rpmRange: range, interpolationDuration: 0.2,
                                   fadeDuration: 0.2)
        _ = follower.update(.init(rpm: 2_000, freshness: .verified, age: 0,
                                  acceleratorThrottle: 0.5, sampleTime: 0))
        _ = follower.update(.init(rpm: 0, freshness: .verified, age: 0,
                                  acceleratorThrottle: 0, sampleTime: 0.1))
        XCTAssertEqual(follower.output(at: 0.3).gain, 0, accuracy: 0.001)
        XCTAssertEqual(follower.output(at: 0.3).targetRPM, 800)
        let restart = follower.update(.init(rpm: 1_200, freshness: .verified, age: 0,
                                            acceleratorThrottle: 0.4, sampleTime: 0.4))
        XCTAssertEqual(restart.gain, 0, accuracy: 0.001)
        XCTAssertEqual(follower.output(at: 0.6).gain, 1, accuracy: 0.001)
        XCTAssertEqual(follower.output(at: 0.6).targetRPM, 1_200, accuracy: 0.001)
    }

    func testVerifiedUnverifiedStaleAndDisconnectedTransitions() {
        var follower = RPMFollower(rpmRange: range, interpolationDuration: 0)
        let verified = follower.update(.init(rpm: 1_000, freshness: .verified, age: 0,
                                             acceleratorThrottle: 0.3, sampleTime: 0))
        XCTAssertEqual(verified.gain, 1)
        let unverified = follower.update(.init(rpm: 1_100, freshness: .unverified, age: 0,
                                               acceleratorThrottle: 0.4, sampleTime: 0.1))
        XCTAssertEqual(unverified.gain, 1)
        XCTAssertEqual(unverified.targetRPM, 1_100)
        let stale = follower.update(.init(rpm: 2_000, freshness: .stale, age: 0,
                                          acceleratorThrottle: 0.9, sampleTime: 0.2))
        XCTAssertEqual(stale.targetRPM, 800)
        let disconnected = follower.update(.init(rpm: nil, freshness: .disconnected, age: nil,
                                                 acceleratorThrottle: nil, sampleTime: 0.5))
        XCTAssertEqual(disconnected.gain, 0)
        XCTAssertEqual(disconnected.targetRPM, 800)
    }

    func testUnverifiedReadingWithoutExplicitAgeStillExpires() {
        var follower = RPMFollower(rpmRange: range, maxReadingAge: 0.3,
                                   fadeDuration: 0.1)
        let unverified = follower.update(.init(rpm: 1_600, freshness: .unverified,
                                               age: nil, acceleratorThrottle: 0.3,
                                               sampleTime: 2))
        XCTAssertEqual(unverified.gain, 1)
        XCTAssertEqual(follower.output(at: 2.3).targetRPM, 800)
        XCTAssertEqual(follower.output(at: 2.4).gain, 0, accuracy: 0.001)
    }

    func testDisconnectAtSameSampleTimeImmediatelyDiscardsRPM() {
        var follower = RPMFollower(rpmRange: range)
        _ = follower.update(.init(rpm: 3_000, freshness: .verified, age: 0,
                                  acceleratorThrottle: 0.5, sampleTime: 1))
        let disconnected = follower.update(.init(rpm: nil, freshness: .disconnected, age: nil,
                                                 acceleratorThrottle: nil, sampleTime: 1))
        XCTAssertEqual(disconnected.targetRPM, 800)
        XCTAssertEqual(disconnected.throttle, 0)
    }

    func testDerivedThrottleDoesNotUseExpiredRPM() {
        var follower = RPMFollower(rpmRange: range, maxReadingAge: 0.3,
                                   interpolationDuration: 0,
                                   derivedThrottleRPMPerSecond: 2_000)
        _ = follower.update(.init(rpm: 1_000, freshness: .verified, age: 0,
                                  acceleratorThrottle: nil, sampleTime: 0))
        XCTAssertEqual(follower.output(at: 0.6).gain, 0)
        let reconnected = follower.update(.init(rpm: 3_000, freshness: .verified,
                                                age: 0, acceleratorThrottle: nil,
                                                sampleTime: 1))
        XCTAssertTrue(reconnected.isThrottleDerived)
        XCTAssertEqual(reconnected.throttle, 0)
        XCTAssertEqual(reconnected.targetRPM, 3_000)
    }

    func testDerivesThrottleOnlyWhenAcceleratorUnavailable() {
        var follower = RPMFollower(rpmRange: range, interpolationDuration: 0,
                                   derivedThrottleRPMPerSecond: 2_000)
        _ = follower.update(.init(rpm: 1_000, freshness: .verified, age: 0,
                                  acceleratorThrottle: nil, sampleTime: 0))
        let derived = follower.update(.init(rpm: 1_200, freshness: .verified, age: 0,
                                            acceleratorThrottle: nil, sampleTime: 0.2))
        XCTAssertTrue(derived.isThrottleDerived)
        XCTAssertEqual(derived.throttle, 0.5, accuracy: 0.001)
        let direct = follower.update(.init(rpm: 1_400, freshness: .verified, age: 0,
                                           acceleratorThrottle: 0.25, sampleTime: 0.4))
        XCTAssertFalse(direct.isThrottleDerived)
        XCTAssertEqual(direct.throttle, 0.25, accuracy: 0.001)
    }
}
