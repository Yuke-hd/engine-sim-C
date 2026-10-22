/// The source's view of RPM freshness. An unverified reading is usable until
/// its supplied age and sample time exceed the follower's age limit.
public enum RPMFreshness: Sendable {
    case verified
    case unverified
    case stale
    case disconnected
}

/// A neutral, timestamped engine reading. Times and ages are in seconds.
/// The sample time must use the same monotonic clock passed to `output(at:)`.
/// A nil age starts at zero and still expires by sample time.
public struct RPMFollowerInput: Sendable {
    public let rpm: Double?
    public let freshness: RPMFreshness
    public let age: Double?
    public let acceleratorThrottle: Double?
    public let sampleTime: Double

    public init(rpm: Double?, freshness: RPMFreshness, age: Double?,
                acceleratorThrottle: Double?, sampleTime: Double) {
        self.rpm = rpm
        self.freshness = freshness
        self.age = age
        self.acceleratorThrottle = acceleratorThrottle
        self.sampleTime = sampleTime
    }
}

/// Controls for one render/update instant. Throttle and gain are in 0...1.
public struct RPMFollowerOutput: Sendable {
    public let targetRPM: Double
    public let throttle: Double
    public let gain: Double
    public let isThrottleDerived: Bool
}

/// Follows timestamped engine readings without retaining a stale RPM target.
///
/// Feed readings with `update(_:)`, then evaluate at the desired playback
/// clock time with `output(at:)`. A new reading interpolates from the current
/// output over `interpolationDuration`. Invalid or expired RPM immediately
/// resets the target to the profile minimum while gain fades to silence.
public struct RPMFollower {
    public let rpmRange: ClosedRange<Double>
    public let maxReadingAge: Double
    public let interpolationDuration: Double
    public let fadeDuration: Double
    public let derivedThrottleRPMPerSecond: Double

    private var latestInput: RPMFollowerInput?
    private var transitionTime = 0.0
    private var fromRPM = 0.0
    private var toRPM = 0.0
    private var fromThrottle = 0.0
    private var toThrottle = 0.0
    private var fromGain = 0.0
    private var toGain = 0.0
    private var derived = false
    private var previousLiveRPM: Double?
    private var previousLiveTime: Double?

    public init(rpmRange: ClosedRange<Double>, maxReadingAge: Double = 0.5,
                interpolationDuration: Double = 0.1, fadeDuration: Double = 0.2,
                derivedThrottleRPMPerSecond: Double = 2_000) {
        precondition(rpmRange.lowerBound.isFinite && rpmRange.lowerBound >= 0
                     && rpmRange.upperBound.isFinite)
        precondition(maxReadingAge.isFinite && maxReadingAge > 0)
        precondition(interpolationDuration.isFinite && interpolationDuration >= 0)
        precondition(fadeDuration.isFinite && fadeDuration >= 0)
        precondition(derivedThrottleRPMPerSecond.isFinite && derivedThrottleRPMPerSecond > 0)
        self.rpmRange = rpmRange
        self.maxReadingAge = maxReadingAge
        self.interpolationDuration = interpolationDuration
        self.fadeDuration = fadeDuration
        self.derivedThrottleRPMPerSecond = derivedThrottleRPMPerSecond
        fromRPM = rpmRange.lowerBound
        toRPM = rpmRange.lowerBound
    }

    @discardableResult
    public mutating func update(_ input: RPMFollowerInput) -> RPMFollowerOutput {
        guard input.sampleTime.isFinite,
              latestInput.map({ input.sampleTime >= $0.sampleTime }) ?? true else {
            return output(at: latestInput?.sampleTime ?? 0)
        }

        let previousInput = latestInput
        let before = output(at: input.sampleTime)
        let hadLiveReading = previousInput.map { isLive($0, at: input.sampleTime) } ?? false
        let expiry = previousInput.flatMap { previous -> Double? in
            guard isLive(previous, at: previous.sampleTime), !hadLiveReading else { return nil }
            return previous.sampleTime + maxReadingAge - (previous.age ?? 0)
        }
        let gainAtExpiry = expiry.map { output(at: $0).gain }
        latestInput = input

        guard isLive(input, at: input.sampleTime), let rpm = input.rpm else {
            fromRPM = rpmRange.lowerBound
            toRPM = rpmRange.lowerBound
            fromThrottle = 0
            toThrottle = 0
            if let expiry, let gainAtExpiry {
                transitionTime = expiry
                fromGain = gainAtExpiry
            } else if hadLiveReading || previousInput == nil {
                transitionTime = input.sampleTime
                fromGain = before.gain
            }
            toGain = 0
            derived = false
            previousLiveRPM = nil
            previousLiveTime = nil
            return output(at: input.sampleTime)
        }

        let clampedRPM = clamp(rpm, to: rpmRange)
        let throttle: Double
        if let accelerator = input.acceleratorThrottle, accelerator.isFinite {
            throttle = clamp(accelerator, to: 0...1)
            derived = false
        } else {
            let rate: Double
            if hadLiveReading, let previousLiveRPM, let previousLiveTime,
               input.sampleTime > previousLiveTime {
                rate = max(0, (rpm - previousLiveRPM) / (input.sampleTime - previousLiveTime))
            } else {
                rate = 0
            }
            throttle = clamp(rate / derivedThrottleRPMPerSecond, to: 0...1)
            derived = true
        }

        transitionTime = input.sampleTime
        fromRPM = hadLiveReading ? before.targetRPM : clampedRPM
        toRPM = clampedRPM
        fromThrottle = hadLiveReading ? before.throttle : throttle
        toThrottle = throttle
        fromGain = previousInput == nil ? 1 : before.gain
        toGain = 1
        previousLiveRPM = rpm
        previousLiveTime = input.sampleTime
        return output(at: input.sampleTime)
    }

    public func output(at time: Double) -> RPMFollowerOutput {
        let idle = rpmRange.lowerBound
        guard let input = latestInput, time.isFinite else {
            return .init(targetRPM: idle, throttle: 0, gain: 0, isThrottleDerived: false)
        }

        if !isLive(input, at: input.sampleTime) {
            let gain = interpolate(fromGain, toGain, fraction: progress(time, since: transitionTime,
                                                                        duration: fadeDuration))
            return .init(targetRPM: idle, throttle: 0, gain: gain, isThrottleDerived: false)
        }

        let fraction = progress(time, since: transitionTime, duration: interpolationDuration)
        let liveGain = interpolate(fromGain, toGain, fraction: fraction)
        let expiry = input.sampleTime + maxReadingAge - (input.age ?? 0)
        if time >= expiry {
            let gainAtExpiry = interpolate(fromGain, toGain,
                                           fraction: progress(expiry, since: transitionTime,
                                                              duration: interpolationDuration))
            let gain = interpolate(gainAtExpiry, 0,
                                   fraction: progress(time, since: expiry, duration: fadeDuration))
            return .init(targetRPM: idle, throttle: 0, gain: gain, isThrottleDerived: false)
        }

        return .init(targetRPM: interpolate(fromRPM, toRPM, fraction: fraction),
                     throttle: interpolate(fromThrottle, toThrottle, fraction: fraction),
                     gain: liveGain, isThrottleDerived: derived)
    }

    private func isLive(_ input: RPMFollowerInput, at time: Double) -> Bool {
        guard input.freshness == .verified || input.freshness == .unverified,
              let rpm = input.rpm, rpm.isFinite, rpm > 0,
              (input.age ?? 0).isFinite, (input.age ?? 0) >= 0 else { return false }
        return (input.age ?? 0) + max(0, time - input.sampleTime) < maxReadingAge
    }

    private func progress(_ time: Double, since start: Double, duration: Double) -> Double {
        guard duration > 0 else { return 1 }
        return clamp((time - start) / duration, to: 0...1)
    }

    private func interpolate(_ start: Double, _ end: Double, fraction: Double) -> Double {
        start + (end - start) * fraction
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
