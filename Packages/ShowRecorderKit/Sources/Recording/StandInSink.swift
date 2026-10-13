import BroadcastWave
import Foundation
import Synchronization

/// One USB Channel of a Drive only Take's standby on the Device (#196, ADR 0006). It keeps the last `heldFrames` of the
/// Take in memory and writes nothing, until it is told to stand in from a Take frame: then it opens a Stem whose first
/// frame is that one, writes the held frames from there and goes on writing everything after. Only the writer thread
/// calls the `StemSink` methods; `standIn(from:open:)` may be called from any thread and takes effect at the next append.
final class StandInSink: StemSink, @unchecked Sendable {
    /// Take frames appended so far, written to a file or not. Read from any thread.
    var frameCount: UInt64 { appended.load(ordering: .acquiring) }
    private let appended = Atomic<UInt64>(0)

    private let heldFrames: Int
    /// The last `heldFrames` samples, oldest overwritten first; `frameCount` is one past the newest.
    private var held: [Float]
    /// The stand-in asked for and not yet started: where it starts, and how to open its Stem.
    private let lock = NSLock()
    private var request: (start: Int, open: () throws -> any StemSink)?
    private var file: (stem: any StemSink, start: Int)?
    private var markers: [StemMarker] = []

    init(heldFrames: Int) {
        self.heldFrames = max(heldFrames, 1)
        held = [Float](repeating: 0, count: max(heldFrames, 1))
    }

    /// The oldest Take frame still held, which a stand-in can start from.
    var oldestHeld: Int { max(0, Int(frameCount) - heldFrames) }

    /// Starts writing from Take frame `start` (which must still be held) into the Stem `open` makes.
    func standIn(from start: Int, open: @escaping () throws -> any StemSink) {
        lock.withLock { request = (start, open) }
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws {
        try startIfAsked()
        var count = Int(frameCount)
        for sample in samples {
            held[count % heldFrames] = sample
            count += 1
        }
        appended.store(UInt64(count), ordering: .releasing)
        try file?.stem.append(samples)
    }

    func commitHeader() throws {
        try startIfAsked()
        try file?.stem.commitHeader()
    }

    func finalize() throws {
        try startIfAsked()
        try file?.stem.finalize()
    }

    /// Markers are Take frames; in the stand-in's Stem they count from its start, and earlier ones are left out.
    @discardableResult
    func setMarkers(_ markers: [StemMarker]) throws -> Int {
        self.markers = markers
        guard let file else { return markers.count }
        return try file.stem.setMarkers(Self.shifted(markers, by: file.start))
    }

    private func startIfAsked() throws {
        guard file == nil, let asked = lock.withLock({ () -> (start: Int, open: () throws -> any StemSink)? in
            defer { request = nil }
            return request
        }) else { return }
        let start = max(asked.start, oldestHeld)
        let stem = try asked.open()
        file = (stem, start)
        var samples: [Float] = []
        samples.reserveCapacity(Int(frameCount) - start)
        for frame in start..<Int(frameCount) { samples.append(held[frame % heldFrames]) }
        try samples.withUnsafeBufferPointer { try stem.append($0) }
        if !markers.isEmpty { try stem.setMarkers(Self.shifted(markers, by: start)) }
    }

    private static func shifted(_ markers: [StemMarker], by start: Int) -> [StemMarker] {
        markers.filter { Int($0.position) >= start }.map { StemMarker(position: $0.position - UInt32(start), label: $0.label) }
    }
}
