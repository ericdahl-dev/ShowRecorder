import AudioIO
import BroadcastWave
import Destinations
import Foundation
@testable import Recording
@testable import ShowReport
import Testing

/// A 2-input interface records its Take as one interleaved stereo Broadcast WAV named "Stereo", not two mono Stems (#1088,
/// Eric 2026-11-07). Automatic, no setting; with only one of the two channels armed it records mono as before. Behind
/// `StereoPairAvailability` (Debug + TestFlight); where the rule is off nothing changes.
@MainActor
@Suite("Stereo Take")
struct StereoTakeTests {
    let root: URL
    let show = "2026-10-06 Show"

    init() {
        root = FileManager.default.temporaryDirectory.appending(path: "StereoTakeTests-\(UUID().uuidString)")
    }

    func recorder(deviceFolder: URL? = nil, drive: (@Sendable () -> DriveAccess?)? = nil, stereo: Bool = true) -> Recorder {
        Recorder(
            deviceFolder: deviceFolder ?? root, driveFolder: drive ?? { nil }, now: { RecordingTakeTests.showDay },
            destinationCheckInterval: nil, stereoPairAvailable: { stereo })
    }

    /// A block of `count` frames: left rises from `start`, right falls, so the two can't be swapped unseen.
    static func block(from start: Int, count: Int = 480) -> [[Float]] {
        [(start..<start + count).map { Float($0 % 1_000) / 8_192 }, (start..<start + count).map { -Float($0 % 1_000) / 8_192 }]
    }

    static func interleaved(_ blocks: [[[Float]]]) -> [Float] {
        blocks.flatMap { block in zip(block[0], block[1]).flatMap { [$0, $1] } }
    }

    func wavs(in take: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: take.path).filter { $0.hasSuffix(".wav") }.sorted()
    }

    @Test("A 2-input interface's Take is one stereo file named Stereo, left and right interleaved, listed once in Take.json")
    func oneStereoFile() async throws {
        let recorder = recorder()
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)
        try recorder.startTake()
        let blocks = [Self.block(from: 0), Self.block(from: 480)]
        for block in blocks { audio.deliver(block) }
        try await recorder.stopTake()

        let take = root.appending(path: "\(show)/Take 01")
        #expect(try wavs(in: take) == ["Stereo.wav"])
        let url = take.appending(path: "Stereo.wav")
        let stem = try StemFile.inspect(url)
        #expect(stem.channelCount == 2)
        #expect(stem.frameCount == 960)
        #expect(try StemWriter.readSamples(url: url, frames: 0..<960) == Self.interleaved(blocks))
        let parsed = try ParsedStem(contentsOf: url)
        #expect(parsed.channelCount == 2)
        #expect(parsed.description == "Stereo")

        let metadata = try TakeMetadata.read(fromTakeFolder: take)
        #expect(metadata.usbChannels.count == 1)
        #expect(metadata.usbChannels.first?.usbChannel == 1)
        #expect(metadata.usbChannels.first?.channels == 2)
        #expect(metadata.usbChannels.first?.stemFile == "Stereo.wav")
        #expect(metadata.usbChannels.first?.name == "Stereo")
    }

    @Test("Where the rule is off, a 2-input interface records two mono Stems, as before")
    func ruleOff() async throws {
        let recorder = recorder(stereo: false)
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver(Self.block(from: 0))
        try await recorder.stopTake()
        let take = root.appending(path: "\(show)/Take 01")
        #expect(try wavs(in: take) == ["01 USB 01.wav", "02 USB 02.wav"])
        #expect(try TakeMetadata.read(fromTakeFolder: take).usbChannels.allSatisfy { $0.channels == nil })
    }

    @Test("With only one of the two channels armed, that channel is recorded mono, as before")
    func oneArmed() async throws {
        let recorder = recorder()
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)
        try recorder.startTake(allowance: TakeAllowance(recordedChannels: [2], showReport: false, reaperExport: false, namingByHand: false))
        audio.deliver(Self.block(from: 0))
        try await recorder.stopTake()
        let take = root.appending(path: "\(show)/Take 01")
        #expect(try wavs(in: take) == ["02 USB 02.wav"])
        #expect(try StemFile.inspect(take.appending(path: "02 USB 02.wav")).channelCount == 1)
    }

    @Test("An interface with more than two inputs records mono Stems, as before", arguments: [1, 3, 18])
    func notTwoInputs(count: Int) async throws {
        let recorder = recorder()
        let audio = FakeAudioDevice(inputChannelCount: count)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver((0..<count).map { _ in Array(repeating: 0.1, count: 480) })
        try await recorder.stopTake()
        let take = root.appending(path: "\(show)/Take 01")
        #expect(try wavs(in: take).count == count)
        #expect(!(try wavs(in: take)).contains("Stereo.wav"))
    }

    @Test("Markers are in the stereo file, at the frame they were placed")
    func markers() async throws {
        let recorder = recorder()
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver(Self.block(from: 0))
        #expect(recorder.addMarker(named: "Chorus"))
        audio.deliver(Self.block(from: 480))
        try await recorder.stopTake()
        let data = try Data(contentsOf: root.appending(path: "\(show)/Take 01/Stereo.wav"))
        #expect(data.range(of: Data("Chorus".utf8)) != nil)
        let cue = try #require(data.range(of: Data("cue ".utf8)))
        let offset = cue.upperBound + 4 + 4 + 20
        #expect(Int(data[offset]) | Int(data[offset + 1]) << 8 == 480)
    }

    @Test("With a Drive both Copies get the same stereo file, and the report and Reaper project have one stereo item")
    func bothCopiesReportAndReaper() async throws {
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let device = root.appending(path: "Device")
        let recorder = recorder(deviceFolder: device, drive: { DriveAccess(folder: drive) })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)
        try recorder.startTake(allowance: TakeAllowance(recordedChannels: [1, 2], showReport: true, reaperExport: true, namingByHand: false))
        audio.deliver(Self.block(from: 0))
        audio.deliver(Self.block(from: 480))
        try await recorder.stopTake()

        let onDevice = device.appending(path: "\(show)/Take 01/Stereo.wav")
        let onDrive = drive.appending(path: "\(show)/Take 01/Stereo.wav")
        #expect(try wavs(in: drive.appending(path: "\(show)/Take 01")) == ["Stereo.wav"])
        #expect(try Data(contentsOf: onDevice) == Data(contentsOf: onDrive))
        #expect(try StemFile.inspect(onDrive).frameCount == 960)

        let report = try ShowReport(showFolder: device.appending(path: show))
        #expect(report.takes.first?.usbChannels.map(\.usbChannel) == [1])
        let project = try String(contentsOf: device.appending(path: "\(show)/\(show).RPP"), encoding: .utf8)
        #expect(project.components(separatedBy: "Stereo.wav").count - 1 == 1)
        #expect(!project.contains("USB 02"))
    }

    @Test("A Drive that joins mid-Take gets a stereo file as long as the Device's, silence before it joined")
    func driveJoinsLate() async throws {
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let device = root.appending(path: "Device")
        final class Plug: @unchecked Sendable { var connected = false }
        let plug = Plug()
        let recorder = recorder(deviceFolder: device, drive: { plug.connected ? DriveAccess(folder: drive) : nil })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)
        try recorder.startTake()
        try await deliverBlocks(100, to: audio, recorder, sample: counting())
        plug.connected = true
        await recorder.checkDestinations()
        try await deliverBlocks(1, from: 48_000, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        let deviceURL = device.appending(path: "\(show)/Take 01/Stereo.wav")
        let driveURL = drive.appending(path: "\(show)/Take 01/Stereo.wav")
        let driveStem = try StemFile.inspect(driveURL)
        #expect(driveStem.channelCount == 2)
        #expect(try StemFile.inspect(deviceURL).frameCount == 48_480)
        #expect(driveStem.frameCount == 48_480)
        // What the Drive missed before it joined was filled by Repair from the Device: the two Copies are the same.
        let whole = (0..<48_480).flatMap { [counting()($0, 0), counting()($0, 1)] }
        #expect(try StemWriter.readSamples(url: driveURL, frames: 0..<48_480) == whole)
        #expect(try StemWriter.readSamples(url: deviceURL, frames: 0..<48_480) == whole)
    }

    @Test("Drive only: a Drive that fails mid-Take is stood in for by the Device in one stereo file, and Repair makes the Drive's whole")
    func driveOnlyStandIn() async throws {
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let device = root.appending(path: "Device")
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { DriveAccess(folder: drive) }, now: { RecordingTakeTests.showDay },
            makeStem: { url, info, resuming in
                let real = try StemWriter.open(url: url, info: info, resumingAt: resuming)
                // The Drive's file fails after 480 frames (960 interleaved samples).
                return url.path.hasPrefix(drive.path) && resuming == nil ? FailingStem(real, healthyFrames: 960) : real
            }, destinationCheckInterval: nil, writerStopTimeout: .milliseconds(300), stereoPairAvailable: { true })
        recorder.recordTo = .drive
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.getReady(audio)
        try recorder.startTake()
        try await deliverBlocks(10, to: audio, recorder, sample: counting())
        try await waitUntil { recorder.copies[.drive] == .interrupted }
        await recorder.checkDestinations()
        try await deliverBlocks(5, from: 10 * 480, to: audio, recorder, sample: counting())
        try await recorder.stopTake()
        await recorder.waitForRepair()

        let driveURL = drive.appending(path: "\(show)/Take 01/Stereo.wav")
        #expect(try StemFile.inspect(driveURL).channelCount == 2)
        let whole = (0..<7_200).flatMap { [counting()($0, 0), counting()($0, 1)] }
        #expect(try StemWriter.readSamples(url: driveURL, frames: 0..<7_200) == whole, "the Drive has the whole Take, both channels")
        #expect(recorder.copies[.drive] == .repaired)
    }

    @Test("A stereo file cut off by a crash is finished at its whole frames, still stereo")
    func crashRecovery() throws {
        let url = root.appending(path: "Stereo.wav")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let info = StemWriter.Info(sampleRate: 48_000, description: "Stereo", originator: "ShowRecorder", timeReference: 0, originationDate: .now, channels: 2)
        let writer = try StemWriter(url: url, info: info)
        let samples = Self.interleaved([Self.block(from: 0), Self.block(from: 480)])
        try samples.withUnsafeBufferPointer { try writer.append($0) }
        try writer.commitHeader()
        // The app dies here: the header covers 960 frames; add half a frame of junk past them.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: [1, 2, 3])
        try handle.close()

        let mono = StemWriter.Info(sampleRate: 48_000, description: "", originator: "ShowRecorder", timeReference: 0, originationDate: .now)
        #expect(CutOffTake.finishStem(at: url, info: mono) == 960)
        let finished = try StemFile.inspect(url)
        #expect(finished.channelCount == 2)
        #expect(finished.frameCount == 960)
        #expect(try StemWriter.readSamples(url: url, frames: 0..<960) == samples)
    }
}
