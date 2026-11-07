#if canImport(AVFoundation)
import AVFoundation
#endif
@testable import BroadcastWave
import Foundation
import Testing

/// A stereo pair recorded as one interleaved 24-bit Broadcast WAV (#1088): a 2-input interface's Take is one "Stereo" file,
/// not two mono Stems. Frames count left and right together; samples go in and come out interleaved (L, R, L, R ...).
@Suite("Stereo Stems")
struct StereoStemTests {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "StereoStemTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static let info = StemWriter.Info(
        sampleRate: 48_000, description: "Stereo", originator: "ShowRecorder", timeReference: 0, originationDate: .now, channels: 2)

    /// Interleaved frames, exactly representable in 24 bits: left counts up, right counts down.
    static func frames(_ range: Range<Int>) -> [Float] {
        range.flatMap { [Float($0 % 100_000) / 8_388_608, -Float($0 % 100_000) / 8_388_608] }
    }

    func write(_ name: String, frames: Int, rf64Threshold: UInt64? = nil) throws -> URL {
        let url = folder.appending(path: name)
        let writer = try rf64Threshold.map { try StemWriter(url: url, info: Self.info, rf64Threshold: $0) } ?? StemWriter(url: url, info: Self.info)
        try Self.frames(0..<frames).withUnsafeBufferPointer { try writer.append($0) }
        #expect(writer.frameCount == UInt64(frames))
        try writer.finalize()
        return url
    }

    @Test("A stereo Stem's header says 2 channels, and its length is counted in frames")
    func header() throws {
        let url = try write("stereo.wav", frames: 1_000)
        let data = try Data(contentsOf: url)
        let fmt = try #require(data.range(of: Data("fmt ".utf8)))
        let body = fmt.upperBound + 4
        func uint16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }
        func uint32(_ at: Int) -> Int { uint16(at) | uint16(at + 2) << 16 }
        #expect(uint16(body + 2) == 2)             // channels
        #expect(uint32(body + 8) == 48_000 * 6)    // bytes per second
        #expect(uint16(body + 12) == 6)            // block align
        #expect(uint16(body + 14) == 24)           // bits per sample
        let stem = try StemFile.inspect(url)
        #expect(stem.channelCount == 2)
        #expect(stem.bytesPerFrame == 6)
        #expect(stem.frameCount == 1_000)
        #expect(stem.framesOnDisk == 1_000)
        #expect(stem.declaredBytes == 6_000)
    }

    @Test("A stereo Stem reads back exactly what was written, interleaved, whole or in any range, with silence past its end")
    func roundTrip() throws {
        let url = try write("stereo.wav", frames: 5_000)
        #expect(try StemWriter.readSamples(url: url, frames: 0..<5_000) == Self.frames(0..<5_000))
        #expect(try StemWriter.readSamples(url: url, frames: 1_234..<4_321) == Self.frames(1_234..<4_321))
        #expect(try StemWriter.readSamples(url: url, frames: 4_990..<5_010) == Self.frames(4_990..<5_000) + [Float](repeating: 0, count: 20))
    }

    @Test("A stereo Stem promoted to RF64 keeps its frames and reads back every sample")
    func rf64() throws {
        let url = try write("big.wav", frames: 20_000, rf64Threshold: 60_000 + UInt64(StemWriter.markerRegionSize))
        #expect(try Data(contentsOf: url).prefix(4) == Data("RF64".utf8))
        let stem = try StemFile.inspect(url)
        #expect(stem.frameCount == 20_000)
        #expect(stem.declaredBytes == 120_000)
        #expect(try StemWriter.readSamples(url: url, frames: 0..<20_000) == Self.frames(0..<20_000))
    }

    @Test("A stereo Stem cut off mid-frame counts only whole frames, and resuming it carries on stereo after them")
    func cutOffAndResume() throws {
        let url = folder.appending(path: "cut.wav")
        let writer = try StemWriter(url: url, info: Self.info)
        try Self.frames(0..<1_000).withUnsafeBufferPointer { try writer.append($0) }
        try writer.commitHeader()
        try Self.frames(1_000..<1_500).withUnsafeBufferPointer { try writer.append($0) }
        // The app dies with half a frame (one 24-bit sample of two) on disk past 1,500 frames.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: [UInt8](repeating: 0x7F, count: 3))
        try handle.close()
        let cut = try StemFile.inspect(url)
        #expect(cut.frameCount == 1_000)
        #expect(cut.framesOnDisk == 1_500)

        // Crash recovery resumes with a mono Info: the file's own header keeps it stereo.
        let mono = StemWriter.Info(sampleRate: 48_000, description: "Stereo", originator: "ShowRecorder", timeReference: 0, originationDate: .now)
        let resumed = try StemWriter.open(url: url, info: mono, resumingAt: cut.framesOnDisk)
        #expect(resumed.channels == 2)
        try Self.frames(1_500..<2_000).withUnsafeBufferPointer { try resumed.append($0) }
        try resumed.finalize()
        #expect(try StemFile.inspect(url).frameCount == 2_000)
        #expect(try StemWriter.readSamples(url: url, frames: 0..<2_000) == Self.frames(0..<2_000))
    }

    @Test("Repair fills a stereo Stem's Gap and missing tail from the other Copy's stereo Stem, both channels")
    func repair() throws {
        let source = try write("source.wav", frames: 10_000)
        let target = folder.appending(path: "target.wav")
        let writer = try StemWriter(url: target, info: Self.info)
        var gapped = Self.frames(0..<8_000)
        for index in 2_000 * 2..<3_000 * 2 { gapped[index] = 0 }  // a Gap written as silence
        try gapped.withUnsafeBufferPointer { try writer.append($0) }
        try writer.finalize()

        try StemRepair.fill(target: target, from: source, ranges: [2_000..<3_000], length: 10_000, markers: [])
        #expect(try StemFile.inspect(target).frameCount == 10_000)
        #expect(try StemWriter.readSamples(url: target, frames: 0..<10_000) == Self.frames(0..<10_000))
        #expect(try Data(contentsOf: target) == Data(contentsOf: source))
    }

    @Test("Markers in a stereo Stem are frame positions, and reopening it to rewrite them keeps its audio")
    func markers() throws {
        let url = try write("marked.wav", frames: 3_000)
        let reopened = try StemWriter.reopen(url: url)
        #expect(reopened.channels == 2)
        #expect(reopened.frameCount == 3_000)
        try reopened.setMarkers([StemMarker(position: 1_500, label: "Chorus")])
        try reopened.finalize()
        #expect(try StemWriter.readSamples(url: url, frames: 0..<3_000) == Self.frames(0..<3_000))
        let data = try Data(contentsOf: url)
        let cue = try #require(data.range(of: Data("cue ".utf8)))
        // One cue point; its sample offset (the last field of the 24-byte point) is the frame, not frame × 2.
        let offset = cue.upperBound + 4 + 4 + 20
        #expect(Int(data[offset]) | Int(data[offset + 1]) << 8 == 1_500)
    }

    #if canImport(AVFoundation)
    @Test("Core Audio, as a DAW or the Files app would, reads a stereo Stem as two channels")
    func coreAudio() throws {
        let url = try write("stereo.wav", frames: 4_800)
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        #expect(file.processingFormat.channelCount == 2)
        #expect(file.length == 4_800)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_800))
        try file.read(into: buffer)
        let left = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 4_800))
        let right = Array(UnsafeBufferPointer(start: buffer.floatChannelData![1], count: 4_800))
        let expected = Self.frames(0..<4_800)
        #expect(left == stride(from: 0, to: expected.count, by: 2).map { expected[$0] })
        #expect(right == stride(from: 1, to: expected.count, by: 2).map { expected[$0] })
    }
    #endif
}
