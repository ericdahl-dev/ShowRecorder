import AudioIO
import Destinations
import Foundation
@testable import Recording
import Telemetry
import Testing

/// Usage events from Takes (ADR 0007, #1026): `TakeTelemetry` turns the sequencer's `TakeEvent`s into telemetry
/// events, so the sequencer and the audio path don't change.
@MainActor
@Suite("Take telemetry")
struct TakeTelemetryTests {
    @Test("A Take starting sends take_started with its channel count, Destinations and Mixer family")
    func takeStarted() {
        var sent: [TelemetryEvent] = []
        let telemetry = TakeTelemetry(send: { sent.append($0) })
        telemetry.handle(.takeStarted(take: 1), context: TakeContext(channelCount: 18, destinations: .both, mixerFamily: "xair"))
        #expect(sent == [.takeStarted(channelCount: 18, destinations: .both, mixerFamily: "xair")])
    }

    @Test("A Take ending sends take_stopped with its length, its Dropouts and why it ended")
    func takeStopped() {
        var sent: [TelemetryEvent] = []
        var now = Date(timeIntervalSince1970: 1_000)
        let telemetry = TakeTelemetry(send: { sent.append($0) }, now: { now })
        let context = TakeContext(channelCount: 18, destinations: .both, mixerFamily: "xair", dropouts: 2)
        telemetry.handle(.takeStarted(take: 1), context: context)
        now += 95
        telemetry.handle(.takeEnded(TakeEnd(take: 1, reason: .outOfSpace)), context: context)
        #expect(sent.last == .takeStopped(seconds: 95, channelCount: 18, dropouts: 2, cause: .outOfSpace))
    }

    @Test("A Take's context comes from the Ready recorder: its USB Channels, Record to and Dropouts")
    func contextFromRecorder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TakeTelemetryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let recorder = Recorder(
            deviceFolder: root.appending(path: "Device"), driveFolder: { DriveAccess(folder: drive) },
            now: { RecordingTakeTests.showDay })
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 2))
        recorder.recordTo = .drive

        #expect(TakeContext(recorder: recorder, mixerFamily: "x32")
            == TakeContext(channelCount: 2, destinations: .driveOnly, mixerFamily: "x32", dropouts: 0))
    }
}
