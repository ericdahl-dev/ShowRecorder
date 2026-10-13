import BroadcastWave
import Foundation
@testable import Recording
import Testing

/// The standby's per-channel memory (#196): it holds the last frames of the Take and, once asked, writes a stand-in.
@Suite("Stand-in sink")
struct StandInSinkTests {
    final class MemoryStem: StemSink, @unchecked Sendable {
        var samples: [Float] = []
        var markers: [StemMarker] = []
        var frameCount: UInt64 { UInt64(samples.count) }
        func append(_ samples: UnsafeBufferPointer<Float>) throws { self.samples += samples }
        func commitHeader() throws {}
        func finalize() throws {}
        @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { self.markers = markers; return markers.count }
    }

    func append(_ sink: StandInSink, _ range: Range<Int>) throws {
        try range.map(Float.init).withUnsafeBufferPointer { try sink.append($0) }
    }

    @Test("Writes nothing until asked, then the held frames from the start asked for, then everything after")
    func standsIn() throws {
        let sink = StandInSink(heldFrames: 600)
        let stem = MemoryStem()
        try append(sink, 0..<500)
        sink.standIn(from: 200) { stem }
        #expect(stem.samples.isEmpty)
        try append(sink, 500..<700)
        #expect(stem.samples == (200..<700).map(Float.init))
    }

    @Test("A start no longer held begins at the oldest frame held, and Markers count from the stand-in's start")
    func oldestHeldAndMarkers() throws {
        let sink = StandInSink(heldFrames: 600)
        let stem = MemoryStem()
        try append(sink, 0..<1_000)
        try sink.setMarkers([.init(position: 50, label: "Before"), .init(position: 700, label: "Chorus")])
        sink.standIn(from: 100) { stem }
        try append(sink, 1_000..<1_100)
        #expect(stem.samples.first == 400, "frames before 400 had been overwritten")
        #expect(stem.samples == (400..<1_100).map(Float.init))
        #expect(stem.markers == [.init(position: 300, label: "Chorus")])
    }
}
