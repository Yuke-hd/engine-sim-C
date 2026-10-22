import Foundation

/// A simple mono PCM16 source for playback checks and host previews.
public final class ToneSource: EngineSoundSource {
    public let sampleRate: Double
    public var frequency: Double {
        didSet { if !frequency.isFinite || frequency < 0 { frequency = 0 } }
    }
    private var phase = 0.0
    private var enabled = true
    private var throttle = 1.0

    public init(frequency: Double = 110, sampleRate: Double = 44_100) {
        self.frequency = frequency.isFinite ? max(0, frequency) : 0
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 44_100
    }

    public func setTargetRPM(_ rpm: Double) { frequency = rpm.isFinite ? max(0, rpm / 60) : 0 }
    public func setThrottle(_ throttle: Double) { self.throttle = throttle.isFinite ? min(max(throttle, 0), 1) : 0 }
    public func setIgnition(_ enabled: Bool) { self.enabled = enabled }

    @discardableResult
    public func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int {
        let amplitude = enabled ? 12_000 * throttle : 0
        let advance = 2 * Double.pi * frequency / sampleRate
        for index in frames.indices {
            frames[index] = Int16((sin(phase) * amplitude).rounded())
            phase += advance
            if phase >= 2 * Double.pi { phase.formTruncatingRemainder(dividingBy: 2 * Double.pi) }
        }
        return frames.count
    }
}
