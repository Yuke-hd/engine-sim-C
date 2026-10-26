import AVFoundation
import EngineSimCore

/// Exhaust overrun (pops, bangs, crackle and burble) mixed over the simulated
/// engine after the throttle is lifted at speed. The samples come from the
/// procedural v8-overrun pack; the timing follows the pack README's suggested
/// tuning. Not thread-safe: the player's worker thread owns it.
final class OverrunLayer {
    private struct Clip {
        let samples: [Float]
        let sampleRate: Double
    }

    private struct Voice {
        let clip: Clip
        let startAt: Int  // output sample index
        let step: Double  // source samples per output sample
        let gain: Float
        var position = 0.0
    }

    private enum Kind: CaseIterable { case bang, pop, crackle, burble }

    private let outputRate = Double(ENGINE_SIM_SAMPLE_RATE)
    private var clips: [Kind: [Clip]] = [:]
    private var lastVariant: [Kind: Int] = [:]
    private var loop: Clip?
    private var loopPosition = 0.0

    private var voices: [Voice] = []
    private var now = 0  // output samples rendered so far
    private var armed = true
    private var active = false
    private var activeSince = 0
    private var burstEnd = 0
    private var nextEventAt = 0
    private var envelope: Float = 0

    // Starting points from the pack README, not measurements of a real car.
    private let liftThrottle = 0.05
    private let rearmThrottle = 0.2
    private let minRpm = 2000.0
    private let stopRpm = 1500.0
    private let fadeSeconds = 0.06

    init() {
        for kind in Kind.allCases {
            clips[kind] = (1...4).compactMap { Self.load(String(format: "%@-%02d", "\(kind)", $0)) }
        }
        loop = Self.load("deep-burble-8s")
    }

    var isActive: Bool { active }

    /// Adds the overrun layer, scaled by `gain`, to `out` (full scale = 1).
    func mix(into out: UnsafeMutablePointer<Float>, count: Int, throttle: Double, rpm: Double,
             maxRpm: Double, gain: Float) {
        updateState(throttle: throttle, rpm: rpm)
        let intensity = active ? Self.clamp((rpm - stopRpm) / (maxRpm - stopRpm), 0.2, 1) : 0
        if active { scheduleEvents(until: now + count, intensity: intensity) }

        let fadeStep = Float(1 / (fadeSeconds * outputRate))
        let target: Float = active ? 1 : 0
        let loopGain = Float(0.6 * intensity)
        for i in 0..<count {
            envelope += max(-fadeStep, min(fadeStep, target - envelope))
            if envelope == 0 { continue }
            var sample: Float = 0
            if let loop {
                sample += loopGain * Self.read(loop, at: loopPosition, wrap: true)
                loopPosition += loop.sampleRate / outputRate
                if loopPosition >= Double(loop.samples.count) { loopPosition -= Double(loop.samples.count) }
            }
            let t = now + i
            for v in voices.indices where t >= voices[v].startAt {
                sample += voices[v].gain * Self.read(voices[v].clip, at: voices[v].position)
                voices[v].position += voices[v].step
            }
            out[i] += gain * envelope * sample
        }
        now += count
        voices.removeAll { Int($0.position) >= $0.clip.samples.count - 1 }
        if envelope == 0 && !active { voices.removeAll() }
    }

    private func updateState(throttle: Double, rpm: Double) {
        if throttle > rearmThrottle { armed = true }
        if active && (throttle > liftThrottle * 2 || rpm < stopRpm) { active = false }
        if armed && !active && throttle < liftThrottle && rpm > minRpm {
            armed = false
            active = true
            activeSince = now
            nextEventAt = now
            let rpmShare = Self.clamp(rpm / 7000, 0.3, 1)
            burstEnd = now + Int(Double.random(in: 0.4...2.5) * rpmShare * outputRate)
            if let loop { loopPosition = Double.random(in: 0..<Double(loop.samples.count)) }
        }
    }

    private func scheduleEvents(until end: Int, intensity: Double) {
        while nextEventAt < end {
            let inBurst = nextEventAt < burstEnd
            // 4-8 events/s in the initial burst, thinning to about one a second.
            let afterBurst = Double(max(0, nextEventAt - burstEnd)) / outputRate
            let rate = inBurst
                ? Double.random(in: 4...8) * (0.5 + 0.5 * intensity)
                : 1 + 4 * exp(-afterBurst / 1.5) * intensity
            let kind = pickKind(inBurst: inBurst)
            let level = Float((0.5 + 0.5 * intensity) * Double.random(in: 0.8...1))
            spawn(kind, at: nextEventAt, gain: level)
            // A few quieter crackles trail the primary event.
            if inBurst || Double.random(in: 0..<1) < 0.4 {
                for _ in 0..<Int.random(in: 1...3) {
                    let delay = Int(Double.random(in: 0.025...0.09) * outputRate)
                    spawn(.crackle, at: nextEventAt + delay, gain: level * Float.random(in: 0.3...0.5))
                }
            }
            nextEventAt += Int(Double.random(in: 0.6...1.4) / rate * outputRate)
        }
    }

    private func pickKind(inBurst: Bool) -> Kind {
        let r = Double.random(in: 0..<1)
        if inBurst { return r < 0.15 ? .bang : r < 0.55 ? .pop : r < 0.9 ? .crackle : .burble }
        return r < 0.5 ? .burble : r < 0.8 ? .pop : .crackle
    }

    private func spawn(_ kind: Kind, at start: Int, gain: Float) {
        guard let variants = clips[kind], !variants.isEmpty else { return }
        var index = Int.random(in: 0..<variants.count)
        if variants.count > 1 && index == lastVariant[kind] { index = (index + 1) % variants.count }
        lastVariant[kind] = index
        let clip = variants[index]
        let step = clip.sampleRate / outputRate * Double.random(in: 0.92...1.08)
        voices.append(Voice(clip: clip, startAt: start, step: step, gain: gain))
    }

    private static func read(_ clip: Clip, at position: Double, wrap: Bool = false) -> Float {
        let i = Int(position)
        guard i < clip.samples.count else { return 0 }
        // Loops interpolate across their seam; one-shots end at digital zero.
        let next = i + 1 < clip.samples.count ? clip.samples[i + 1] : (wrap ? clip.samples[0] : 0)
        let f = Float(position - Double(i))
        return clip.samples[i] + f * (next - clip.samples[i])
    }

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }

    private static func load(_ name: String) -> Clip? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Overrun"),
              let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let data = buffer.floatChannelData?[0] else {
            print("overrun: failed to load \(name)")
            return nil
        }
        return Clip(samples: Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength))),
                    sampleRate: file.processingFormat.sampleRate)
    }
}
