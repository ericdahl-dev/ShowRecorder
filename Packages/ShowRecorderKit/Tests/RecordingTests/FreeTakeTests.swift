import AudioIO
import Destinations
import Foundation
@testable import Recording
@testable import ShowReport
import Testing

/// A Take on Free records only the 2 USB Channels the operator chose (ADR 0004).
@MainActor
@Suite("Free Take")
struct FreeTakeTests {
    let root: URL
    let show = "2026-10-06 Show"

    init() {
        root = FileManager.default.temporaryDirectory.appending(path: "FreeTakeTests-\(UUID().uuidString)")
    }

    func allowance(_ channels: Set<Int>) -> TakeAllowance {
        TakeAllowance(recordedChannels: channels, showReport: false, reaperExport: false, namingByHand: false)
    }

    @Test("Only the chosen USB Channels get Stems, and Take.json lists only them, with their levels")
    func onlyChosenStems() throws {
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 4)
        try recorder.arm(audio)
        try recorder.startTake(allowance: allowance([2, 4]))
        audio.deliver((0..<4).map { c in Array(repeating: Float(c + 1) / 10, count: 480) })
        try recorder.stopTake()

        let take = root.appending(path: "\(show)/Take 01")
        let files = try FileManager.default.contentsOfDirectory(atPath: take.path).filter { $0.hasSuffix(".wav") }.sorted()
        #expect(files == ["02 USB 02.wav", "04 USB 04.wav"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(TakeMetadata.self, from: Data(contentsOf: take.appending(path: "Take.json")))
        #expect(metadata.usbChannels.map(\.usbChannel) == [2, 4])
        #expect(metadata.usbChannels.allSatisfy { $0.peakDbfs != nil })
        // Channel 4 is louder than channel 2 in what was delivered, and the levels must follow the right channel.
        #expect((metadata.usbChannels[1].peakDbfs ?? -100) > (metadata.usbChannels[0].peakDbfs ?? -100))
        #expect(try StemFile(contentsOf: take.appending(path: "04 USB 04.wav")).samples.count == 480)
    }

    @Test("With a Drive both Copies get only the chosen Stems, and a report and Reaper project list just those channels")
    func bothCopiesAndOutputs() throws {
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let device = root.appending(path: "Device")
        let recorder = Recorder(deviceFolder: device, driveFolder: { DestinationAccess(folder: drive) }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 3)
        try recorder.arm(audio)
        // Two recorded channels with the report and project on (the report itself is a Pro extra, see ProExtrasTests).
        try recorder.startTake(allowance: TakeAllowance(recordedChannels: [1, 3], showReport: true, reaperExport: true, namingByHand: false))
        audio.deliver((0..<3).map { _ in Array(repeating: 0.2, count: 480) })
        try recorder.stopTake()

        for parent in [device, drive] {
            let take = parent.appending(path: "\(show)/Take 01")
            let files = try FileManager.default.contentsOfDirectory(atPath: take.path).filter { $0.hasSuffix(".wav") }.sorted()
            #expect(files == ["01 USB 01.wav", "03 USB 03.wav"], "\(parent.lastPathComponent)")
        }
        let report = try ShowReport(showFolder: device.appending(path: show))
        #expect(report.takes.first?.usbChannels.map(\.usbChannel) == [1, 3])
        let project = try String(contentsOf: device.appending(path: "\(show)/\(show).RPP"), encoding: .utf8)
        #expect(project.contains("03 USB 03.wav") && !project.contains("02 USB 02.wav"))
    }

    @Test("A Drive that joins mid-Take gets only the chosen Stems; each Take keeps the allowance it started with")
    func driveJoinsAndAllowanceIsPerTake() throws {
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let device = root.appending(path: "Device")
        final class Plug: @unchecked Sendable { var connected = false }
        let plug = Plug()
        let recorder = Recorder(deviceFolder: device, driveFolder: { plug.connected ? DestinationAccess(folder: drive) : nil }, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 3)
        try recorder.arm(audio)
        try recorder.startTake(allowance: allowance([2, 3]))
        audio.deliver((0..<3).map { _ in Array(repeating: 0.2, count: 480) })
        plug.connected = true
        recorder.checkDestinations()
        audio.deliver((0..<3).map { _ in Array(repeating: 0.2, count: 480) })
        try recorder.stopTake()
        let joined = try FileManager.default.contentsOfDirectory(atPath: drive.appending(path: "\(show)/Take 01").path).filter { $0.hasSuffix(".wav") }.sorted()
        #expect(joined == ["02 USB 02.wav", "03 USB 03.wav"])

        // The next Take is pressed with every channel allowed (bought Pro, say): only that Take changes.
        try recorder.startTake(allowance: TakeAllowance(recordedChannels: [1, 2, 3], showReport: true, reaperExport: true, namingByHand: true))
        audio.deliver((0..<3).map { _ in Array(repeating: 0.2, count: 480) })
        try recorder.stopTake()
        let second = try FileManager.default.contentsOfDirectory(atPath: device.appending(path: "\(show)/Take 02").path).filter { $0.hasSuffix(".wav") }
        let first = try FileManager.default.contentsOfDirectory(atPath: device.appending(path: "\(show)/Take 01").path).filter { $0.hasSuffix(".wav") }
        #expect(second.count == 3 && first.count == 2)
    }
}
