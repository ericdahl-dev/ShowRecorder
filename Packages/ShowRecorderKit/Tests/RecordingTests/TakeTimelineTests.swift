import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// A Take's frame 0 is where its time stamp says: press minus Pre-roll (#915). When the Take starts late (the Drive was
/// being prepared), the head reaches from there to the first live block, so the audio matches the stamp.
@MainActor
@Suite("A Take's timeline and its time stamp")
struct TakeTimelineTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "TakeTimelineTests-\(UUID().uuidString)")
    var device: URL { root.appending(path: "Device") }
    static let rate = 48_000

    /// Delivers the ramp `start..<start+count` (each sample is its own index) to `capture`, one block.
    func receive(_ capture: Capture, from start: Int, count: Int) async throws {
        var samples = (0..<count).map { counting()(start + $0, 0) }
        samples.withUnsafeMutableBufferPointer { buffer in
            var pointer = UnsafePointer(buffer.baseAddress!)
            withUnsafePointer(to: &pointer) {
                capture.receive(AudioBlock(channels: $0, channelCount: 1, frameCount: count, hostTime: 0))
            }
        }
        try await waitUntil { capture.isDrained }
    }

    /// A session on the Device (and the Drive, with `withDrive`) as it is made some frames after the press.
    func session(_ capture: Capture, preRollFrames: Int, pressPosition: Int?, withDrive: Bool = false) throws -> TakeSession {
        var show = try Show.create(in: device, drive: nil, on: RecordingTakeTests.showDay)
        var folders = try show.createNextTakeFolder()
        if withDrive { folders[.drive] = try show.joinDrive(root.appending(path: "Drive")) }
        let metadata = TakeMetadata(
            show: show.name, take: show.takeCount, startedAt: RecordingTakeTests.showDay, sampleRate: Self.rate, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
        let info = StemWriter.Info(sampleRate: Self.rate, description: "", originator: "ShowRecorder", timeReference: 0, originationDate: RecordingTakeTests.showDay)
        return try TakeSession(
            show: show, folders: folders, drive: nil, metadata: metadata, stems: [StemSpec(file: "01 USB 01.wav", description: "USB 01")],
            info: info, capture: capture, preRollFrames: preRollFrames,
            makeStem: { try StemWriter.open(url: $0, info: $1, resumingAt: $2) }, freeSpace: { _ in .max }, pressPosition: pressPosition)
    }

    func samples(_ session: TakeSession) throws -> [Int32] {
        try ParsedStem(contentsOf: session.copies[0].folder.appending(path: "01 USB 01.wav")).samples
    }

    @Test("A Take that started late still begins at press minus Pre-roll: the head reaches to the first live block")
    func lateStartKeepsTheStampTrue() async throws {
        let capture = Capture(channelCount: 1, sampleRate: Double(Self.rate), preRollSeconds: 1, startHeadroomSeconds: 2)
        try await receive(capture, from: 0, count: 144_000)  // 3 s while Armed
        let press = try #require(capture.preRoll).totalWrittenFrames
        try await receive(capture, from: 144_000, count: 12_000)  // the Drive is being prepared
        let session = try session(capture, preRollFrames: 48_000, pressPosition: press)

        try await receive(capture, from: 156_000, count: 1_000)
        _ = session.finish()

        // Frame 0 is the audio a second before the press, and nothing is missing or repeated.
        #expect(try samples(session) == (96_000..<157_000).map { Int32($0) })
        #expect(capture.takeFrameCount == 61_000)
    }

    @Test("When the buffer no longer holds the start, the Take opens with silence of that length, and the audio stays where the stamp says")
    func missingStartIsSilence() async throws {
        let capture = Capture(channelCount: 1, sampleRate: Double(Self.rate), preRollSeconds: 1, startHeadroomSeconds: 0)
        try await receive(capture, from: 0, count: 144_000)
        let press = try #require(capture.preRoll).totalWrittenFrames
        try await receive(capture, from: 144_000, count: 24_000)
        let session = try session(capture, preRollFrames: 48_000, pressPosition: press)

        try await receive(capture, from: 168_000, count: 1_000)
        _ = session.finish()

        let stem = try samples(session)
        #expect(stem.count == 73_000)
        // The buffer (2 s, with a second of margin) holds the last second before the first live block: 120 000 on.
        #expect(stem.prefix(24_000).allSatisfy { $0 == 0 }, "silence for what the buffer lost")
        #expect(Array(stem.dropFirst(24_000)) == (120_000..<169_000).map { Int32($0) })
        #expect(session.copies[0].writer.leadGap == 0..<24_000, "recorded as a Gap")
    }

    @Test("The buffer is allocated when the Capture is made, with room for the start wait, even with Pre-roll off")
    func bufferExistsFromTheStart() {
        let capture = Capture(channelCount: 1, sampleRate: Double(Self.rate), preRollSeconds: 0, startHeadroomSeconds: 2)
        let buffer = capture.preRoll
        #expect(buffer?.capacity == 3 * Self.rate, "headroom, plus the second of margin")
        #expect(Capture(channelCount: 1, sampleRate: Double(Self.rate), preRollSeconds: 0).preRoll == nil, "nothing for a Capture that asks for none")
    }

    @Test("With Pre-roll off the Take still begins at the press: the head covers the wait")
    func preRollOffCoversTheWait() async throws {
        let capture = Capture(channelCount: 1, sampleRate: Double(Self.rate), preRollSeconds: 0, startHeadroomSeconds: 2)
        try await receive(capture, from: 0, count: 144_000)
        let press = try #require(capture.preRoll).totalWrittenFrames
        try await receive(capture, from: 144_000, count: 12_000)
        let session = try session(capture, preRollFrames: 0, pressPosition: press)

        try await receive(capture, from: 156_000, count: 1_000)
        _ = session.finish()

        #expect(try samples(session) == (144_000..<157_000).map { Int32($0) })
        #expect(capture.takeFrameCount == 13_000)
    }

    @Test("A press position with no buffer to read is ignored: the Take starts at its first live block")
    func noBufferNoHead() async throws {
        let capture = Capture(channelCount: 1, sampleRate: Double(Self.rate), preRollSeconds: 0)
        try await receive(capture, from: 0, count: 1_000)
        let session = try session(capture, preRollFrames: 0, pressPosition: 1_000)

        try await receive(capture, from: 1_000, count: 500)
        _ = session.finish()

        #expect(try samples(session) == (1_000..<1_500).map { Int32($0) })
    }

    @Test("The Device and the Drive Copies get the same head and the same timeline")
    func twoCopies() async throws {
        let capture = Capture(channelCount: 1, sampleRate: Double(Self.rate), preRollSeconds: 1, startHeadroomSeconds: 2)
        try await receive(capture, from: 0, count: 144_000)
        let press = try #require(capture.preRoll).totalWrittenFrames
        try await receive(capture, from: 144_000, count: 12_000)
        let session = try session(capture, preRollFrames: 48_000, pressPosition: press, withDrive: true)

        try await receive(capture, from: 156_000, count: 1_000)
        _ = session.finish()

        let expected = (96_000..<157_000).map { Int32($0) }
        for copy in session.copies {
            #expect(try ParsedStem(contentsOf: copy.folder.appending(path: "01 USB 01.wav")).samples == expected, "\(copy.kind)")
        }
        #expect(session.copies.count == 2)
    }
}
