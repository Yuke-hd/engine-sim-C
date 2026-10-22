import EngineSoundRing

/// One producer and one consumer may call write and read concurrently.
public final class RingBuffer {
    private let storage: OpaquePointer
    public let capacity: Int

    public init?(capacity: Int) {
        guard capacity > 0, let storage = engine_sound_ring_create(capacity) else { return nil }
        self.capacity = capacity
        self.storage = storage
    }

    deinit { engine_sound_ring_destroy(storage) }

    public var available: Int { Int(engine_sound_ring_available(storage)) }
    public var underrunCount: Int { Int(engine_sound_ring_underruns(storage)) }

    @discardableResult
    public func write(_ samples: UnsafeBufferPointer<Int16>) -> Int {
        guard let base = samples.baseAddress else { return 0 }
        return Int(engine_sound_ring_write(storage, base, samples.count))
    }

    /// Reads available samples and fills the remainder with silence.
    @discardableResult
    public func read(into output: UnsafeMutableBufferPointer<Int16>) -> Int {
        guard let base = output.baseAddress else { return 0 }
        let count = Int(engine_sound_ring_read(storage, base, output.count))
        if count < output.count {
            for index in count..<output.count { output[index] = 0 }
        }
        return count
    }

    /// Reads one sample without allocating. Intended for an audio render callback.
    @inline(__always)
    public func readSample() -> Int16 {
        var value: Int16 = 0
        _ = engine_sound_ring_read(storage, &value, 1)
        return value
    }
}
