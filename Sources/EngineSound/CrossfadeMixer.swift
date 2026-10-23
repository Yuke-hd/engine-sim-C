/// The producer thread's deterministic gain stage: linear startup, source
/// replacement and stop fades over `fadeFrames`, then 0.8 output headroom.
struct CrossfadeMixer {
    let fadeFrames: Int
    private var startupFrame = 0
    private var switchFrame: Int?
    private var stopFrame: Int?

    init(fadeFrames: Int) {
        self.fadeFrames = max(1, fadeFrames)
    }

    var isSwitching: Bool { switchFrame != nil }

    /// Starts fading from the primary to the secondary input on the next block.
    mutating func beginSwitch() { switchFrame = 0 }

    /// Starts fading the output to silence on the next block.
    mutating func beginStop() { if stopFrame == nil { stopFrame = 0 } }

    /// Mixes one block. Returns whether the switch and stop fades completed;
    /// after a completed switch the caller must feed the new source as primary.
    mutating func mix(primary: [Int16], secondary: [Int16], into mixed: inout [Int16])
        -> (switchCompleted: Bool, stopCompleted: Bool) {
        let count = mixed.count
        for index in 0..<count {
            let startGain = min(Double(startupFrame + index) / Double(fadeFrames), 1)
            let stopGain = stopFrame.map { max(0, 1 - Double($0 + index) / Double(fadeFrames)) } ?? 1
            let switchGain = switchFrame.map { min(Double($0 + index) / Double(fadeFrames), 1) } ?? 0
            let value = Double(primary[index]) * (1 - switchGain) + Double(secondary[index]) * switchGain
            // 0.8 bounds the output even if a source reaches full PCM16 scale.
            mixed[index] = Int16(max(-32768, min(32767, (value * startGain * stopGain * 0.8).rounded())))
        }
        startupFrame += count
        var switchCompleted = false
        if let frame = switchFrame {
            switchFrame = frame + count
            if frame + count >= fadeFrames {
                switchFrame = nil
                switchCompleted = true
            }
        }
        var stopCompleted = false
        if let frame = stopFrame {
            stopFrame = frame + count
            stopCompleted = frame + count >= fadeFrames
        }
        return (switchCompleted, stopCompleted)
    }
}
