import XCTest
@testable import AES67Core

final class Capture: FrameSink {
    var out: [Int] = [] // first byte of each frame, 0 for silence
    func write(payload: ArraySlice<UInt8>, frames: Int) {
        for f in 0..<frames { out.append(Int(payload[payload.startIndex + f * 3])) }
    }
    func writeSilence(frames: Int) { out += Array(repeating: 0, count: frames) }
}

/// A mono L24 packet of `frames` frames, every sample's top byte = `mark`.
func packet(_ mark: UInt8, frames: Int = 2) -> ArraySlice<UInt8> {
    Array((0..<frames).flatMap { _ in [mark, 0, 0] })[...]
}

final class AES67CoreTests: XCTestCase {
    func testParsesAnAES67SDP() throws {
        let sdp = """
        v=0
        o=- 1 0 IN IP4 192.168.1.10
        s=Stage box
        c=IN IP4 239.69.83.67/32
        t=0 0
        m=audio 5004 RTP/AVP 98
        a=rtpmap:98 L24/48000/8
        a=ptime:1
        a=ts-refclk:ptp=IEEE1588-2008:39-A7-94-FF-FE-07-CB-D0:0
        a=mediaclk:direct=0
        """
        let d = try parseSDP(sdp)
        XCTAssertEqual(d.group, "239.69.83.67")
        XCTAssertEqual(d.port, 5004)
        XCTAssertEqual(d.payloadType, 98)
        XCTAssertEqual(d.channels, 8)
        XCTAssertEqual(d.sampleRate, 48000)
        XCTAssertEqual(d.ptimeMs, 1)
        XCTAssertEqual(d.mediaClock, "direct=0")
        XCTAssertEqual(d.refClock, "ptp=IEEE1588-2008:39-A7-94-FF-FE-07-CB-D0:0")
    }

    func testParsesRTPHeader() {
        let bytes: [UInt8] = [0x80, 0xE2, 0x12, 0x34, 0xFF, 0xFF, 0xFF, 0xF0, 0, 0, 0, 7, 1, 2, 3]
        let h = bytes.withUnsafeBytes { parseRTP($0) }!
        XCTAssertEqual(h.payloadType, 98)
        XCTAssertTrue(h.marker)
        XCTAssertEqual(h.sequence, 0x1234)
        XCTAssertEqual(h.timestamp, 0xFFFF_FFF0)
        XCTAssertEqual(h.ssrc, 7)
        XCTAssertEqual(h.payload, 12..<15)
    }

    func testUnwrapsAcrossTheWrapAndBack() {
        var u = Unwrapper(bits: 16)
        XCTAssertEqual(u.extend(65534), 65534)
        XCTAssertEqual(u.extend(1), 65537)
        XCTAssertEqual(u.extend(65535), 65535) // reordered packet from before the wrap
        XCTAssertEqual(u.extend(2), 65538)
        var t = Unwrapper(bits: 32)
        XCTAssertEqual(t.extend(0xFFFF_FFD0), 0xFFFF_FFD0)
        XCTAssertEqual(t.extend(0x10), 0x1_0000_0010)
    }

    func testReordersWithinTheWindow() {
        let c = Capture()
        let r = Reassembler(bytesPerFrame: 3, windowFrames: 10, sink: c)
        r.insert(timestamp: 100, payload: packet(1))
        r.insert(timestamp: 104, payload: packet(3))
        r.insert(timestamp: 102, payload: packet(2))
        r.finish()
        XCTAssertEqual(c.out, [1, 1, 2, 2, 3, 3])
        XCTAssertEqual(r.gapEvents, 0)
    }

    func testFillsALostPacketWithSilenceOnceTheWindowPasses() {
        let c = Capture()
        let r = Reassembler(bytesPerFrame: 3, windowFrames: 4, sink: c)
        r.insert(timestamp: 0, payload: packet(1))
        // 2..<4 lost
        r.insert(timestamp: 4, payload: packet(3))
        XCTAssertEqual(c.out, [1, 1], "waits inside the window")
        r.insert(timestamp: 6, payload: packet(4))
        r.insert(timestamp: 8, payload: packet(5)) // newest end 10 - cursor 2 > 4
        XCTAssertEqual(c.out, [1, 1, 0, 0, 3, 3, 4, 4, 5, 5])
        XCTAssertEqual(r.gapEvents, 1)
        XCTAssertEqual(r.gapFrames, 2)
        r.insert(timestamp: 2, payload: packet(2)) // too late
        XCTAssertEqual(r.lateDropped, 1)
    }

    func testDropsDuplicates() {
        let c = Capture()
        let r = Reassembler(bytesPerFrame: 3, windowFrames: 10, sink: c)
        r.insert(timestamp: 0, payload: packet(1))
        r.insert(timestamp: 4, payload: packet(3))
        r.insert(timestamp: 4, payload: packet(3))
        r.insert(timestamp: 0, payload: packet(1))
        r.insert(timestamp: 2, payload: packet(2))
        r.finish()
        XCTAssertEqual(c.out, [1, 1, 2, 2, 3, 3])
        XCTAssertEqual(r.pendingDuplicates, 1)
        XCTAssertEqual(r.lateDropped, 1)
    }

    func testSequenceStatsCountLossReorderAndDuplicates() {
        var s = SequenceStats()
        for q: UInt16 in [65533, 65534, 0, 65535, 1, 1, 3] { s.record(q) }
        XCTAssertEqual(s.received, 7)
        XCTAssertEqual(s.duplicates, 1)
        XCTAssertEqual(s.reordered, 1)
        XCTAssertEqual(s.expected, 7) // 65533 ... 3
        XCTAssertEqual(s.lost, 1) // 2
    }

    func testWAVSetWritesLittleEndianPerChannel() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let w = try WAVSet(directory: dir, prefix: "t", channels: 2, sampleRate: 48000, inBytesPerSample: 3)
        w.write(payload: [0x11, 0x22, 0x33, 0xAA, 0xBB, 0xCC][...], frames: 1)
        w.writeSilence(frames: 1)
        try w.close()
        let a = try Data(contentsOf: dir.appendingPathComponent("t-ch01.wav"))
        let b = try Data(contentsOf: dir.appendingPathComponent("t-ch02.wav"))
        XCTAssertEqual(Array(a.suffix(6)), [0x33, 0x22, 0x11, 0, 0, 0])
        XCTAssertEqual(Array(b.suffix(6)), [0xCC, 0xBB, 0xAA, 0, 0, 0])
        XCTAssertEqual(a.count, 44 + 6)
        XCTAssertEqual(Array(a[40..<44]), [6, 0, 0, 0])
    }
}
