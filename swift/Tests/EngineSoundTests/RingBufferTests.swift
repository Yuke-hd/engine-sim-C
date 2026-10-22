import XCTest
@testable import EngineSound

final class RingBufferTests: XCTestCase {
    func testWrapAndOrdering() {
        let ring = RingBuffer(capacity: 4)!
        XCTAssertEqual([1, 2, 3].withUnsafeBufferPointer { ring.write($0) }, 3)
        var output = [Int16](repeating: -1, count: 2)
        XCTAssertEqual(output.withUnsafeMutableBufferPointer { ring.read(into: $0) }, 2)
        XCTAssertEqual(output, [1, 2])
        XCTAssertEqual([4, 5, 6].withUnsafeBufferPointer { ring.write($0) }, 3)
        output = [Int16](repeating: -1, count: 4)
        XCTAssertEqual(output.withUnsafeMutableBufferPointer { ring.read(into: $0) }, 4)
        XCTAssertEqual(output, [3, 4, 5, 6])
    }

    func testUnderrunFillsSilence() {
        let ring = RingBuffer(capacity: 4)!
        XCTAssertEqual([7].withUnsafeBufferPointer { ring.write($0) }, 1)
        var output = [Int16](repeating: -1, count: 3)
        XCTAssertEqual(output.withUnsafeMutableBufferPointer { ring.read(into: $0) }, 1)
        XCTAssertEqual(output, [7, 0, 0])
        XCTAssertEqual(ring.readSample(), 0)
    }

    func testOverrunDoesNotOverwriteUnreadSamples() {
        let ring = RingBuffer(capacity: 3)!
        XCTAssertEqual([1, 2, 3, 4].withUnsafeBufferPointer { ring.write($0) }, 3)
        XCTAssertEqual([5].withUnsafeBufferPointer { ring.write($0) }, 0)
        var output = [Int16](repeating: 0, count: 3)
        XCTAssertEqual(output.withUnsafeMutableBufferPointer { ring.read(into: $0) }, 3)
        XCTAssertEqual(output, [1, 2, 3])
    }
}
