import XCTest
import DDCBridge

final class DDCPacketTests: XCTestCase {
    func testGetAndSetPacketsHaveDDCChecksums() {
        var get = [UInt8](repeating: 0, count: 4)
        MBMakeGetPacket(0x10, &get)
        XCTAssertEqual(get, [0x82, 0x01, 0x10, 0xAC])

        var set = [UInt8](repeating: 0, count: 6)
        MBMakeSetPacket(0x10, 52, &set)
        XCTAssertEqual(set, [0x84, 0x03, 0x10, 0x00, 0x34, 0x9C])
    }

    func testReplyParserChecksCodeBoundsAndChecksum() {
        var reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x3A, 0]
        reply[10] = reply.prefix(10).reduce(UInt8(0x50), ^)
        var current: UInt16 = 0
        var maximum: UInt16 = 0
        XCTAssertTrue(MBParseReply(reply, reply.count, 0x10, &current, &maximum))
        XCTAssertEqual(current, 58)
        XCTAssertEqual(maximum, 100)

        XCTAssertFalse(MBParseReply(reply, reply.count, 0x12, &current, &maximum))
        reply[10] ^= 1
        XCTAssertFalse(MBParseReply(reply, reply.count, 0x10, &current, &maximum))
        reply[10] ^= 1
        reply[7] = 0
        reply[10] = reply.prefix(10).reduce(UInt8(0x50), ^)
        XCTAssertFalse(MBParseReply(reply, reply.count, 0x10, &current, &maximum))
    }
}
