/// A producer-thread source of mono PCM16 audio. Serialize control and render
/// calls; rendering can block and is unsuitable for an audio render callback.
public protocol EngineSoundSource: AnyObject {
    var sampleRate: Double { get }
    func setTargetRPM(_ rpm: Double)
    func setThrottle(_ throttle: Double)
    func setIgnition(_ enabled: Bool)
    @discardableResult func render(into frames: UnsafeMutableBufferPointer<Int16>) -> Int
}
