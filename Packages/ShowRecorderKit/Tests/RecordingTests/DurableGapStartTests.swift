import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
import Testing

/// A Stem on a Drive that is pulled after `healthyFrames` (#595): what was appended since its last commit never
/// reached the Drive, so its file ends at that commit.
final class LossyStem: StemSink, @unchecked Sendable {
    struct Pulled: Error {}
    private let real: StemWriter
    private let healthyFrames: Int
    private var pending: [Float] = []
    private var pulled = false
    var frameCount: UInt64 { real.frameCount + UInt64(pending.count) }
    /// Samples that reached the Drive.
    var committedFrameCount: UInt64 { real.frameCount }

    init(_ real: StemWriter, healthyFrames: Int) {
        self.real = real
        self.healthyFrames = healthyFrames
    }

    func append(_ samples: UnsafeBufferPointer<Float>) throws {
        if pulled || Int(frameCount) + samples.count > healthyFrames {
            pulled = true
            throw Pulled()
        }
        pending += samples
    }
    func commitHeader() throws {
        if pulled { throw Pulled() }
        try pending.withUnsafeBufferPointer { try real.append($0) }
        pending = []
        try real.commitHeader()
    }
    func finalize() throws { try real.finalize() }
    @discardableResult func setMarkers(_ markers: [StemMarker]) throws -> Int { try real.setMarkers(markers) }
}

extension GapTests {
    final class Lossy: @unchecked Sendable {
        var stem: LossyStem?
        var driveResumes: [UInt64?] = []
    }

    /// A recorder whose first Drive Stem is a `LossyStem`.
    func lossyDriveRecorder(_ lossy: Lossy, healthyFrames: Int) -> Recorder {
        let drive = drive
        return Recorder(
            deviceFolder: device,
            driveFolder: { DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                guard url.path.contains("/Drive/") else { return real }
                lossy.driveResumes.append(resuming)
                guard resuming == nil else { return real }
                let stem = LossyStem(real, healthyFrames: healthyFrames)
                lossy.stem = stem
                return stem
            }, destinationCheckInterval: nil)
    }

    @Test("A pulled Drive that comes back resumes from its last commit, and Repair fills everything it lost (#595)")
    func rejoinResumesFromLastCommit() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let lossy = Lossy()
        let recorder = lossyDriveRecorder(lossy, healthyFrames: 120_000)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliver(144_000, to: audio, recorder, block: 4800, sample: counting())
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }
        let committed = try #require(lossy.stem).committedFrameCount
        let appended = try #require(lossy.stem).frameCount
        #expect(committed > 0 && committed < appended)

        try await waitUntil { recorder.checkDestinations(); return lossy.driveResumes.count == 2 }
        try await deliver(4800, from: 144_000, to: audio, recorder, block: 480, sample: counting())
        try recorder.stopTake()
        await recorder.waitForRepair()

        #expect(lossy.driveResumes.last == committed)
        let gaps = try decodedTake(device).gaps
        #expect(gaps.map(\.copy) == [.drive])
        #expect(gaps.first?.start == Int(committed))
        let deviceFiles = try takeFiles(in: device)
        let driveFiles = try takeFiles(in: drive)
        for (name, data) in deviceFiles { #expect(driveFiles[name] == data, "\(name) differs between the Copies") }
    }

    @Test("A pulled Drive that never comes back is missing everything from its last commit, and Repair fills it (#595)")
    func trailingGapStartsAtLastCommit() async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        let lossy = Lossy()
        let recorder = lossyDriveRecorder(lossy, healthyFrames: 120_000)
        try recorder.arm(audio)

        try recorder.startTake()
        try await deliver(144_000, to: audio, recorder, block: 4800, sample: counting())
        try await waitUntil { recorder.copyStatus(.drive) == .interrupted }
        let committed = try #require(lossy.stem).committedFrameCount
        #expect(committed > 0)
        try recorder.stopTake()
        await recorder.waitForRepair()

        let gaps = try decodedTake(device).gaps
        #expect(gaps.map(\.copy) == [.drive])
        #expect(gaps.first?.start == Int(committed))
        let deviceFiles = try takeFiles(in: device)
        let driveFiles = try takeFiles(in: drive)
        for (name, data) in deviceFiles { #expect(driveFiles[name] == data, "\(name) differs between the Copies") }
    }
}
