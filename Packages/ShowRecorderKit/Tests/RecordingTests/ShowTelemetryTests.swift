import AudioIO
import Destinations
import Foundation
import Telemetry
import Testing

@testable import Recording

/// Usage events from Shows (ADR 0007, #1026): show_created once per Show made, show_deleted once per Show delete
/// that removed a Copy. No names, no venues: the events carry nothing.
@MainActor
@Suite("Show telemetry")
struct ShowTelemetryTests {
    let root: URL
    var device: URL { root.appending(path: "Device") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShowTelemetryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func recorder(sent: @escaping (TelemetryEvent) -> Void) -> Recorder {
        let recorder = Recorder(deviceFolder: device, driveFolder: { nil }, now: { RecordingTakeTests.showDay })
        recorder.sendEvent = sent
        return recorder
    }

    func record(_ recorder: Recorder) async throws {
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        audio.deliver([Array(repeating: 0.1, count: 480)])
        try await recorder.stopTake()
        recorder.standDown()
    }

    @Test("New Show sends show_created once, with nothing about its name or venue")
    func newShow() throws {
        var sent: [TelemetryEvent] = []
        let recorder = recorder { sent.append($0) }
        try recorder.startNewShow(name: "Sunday Service", venue: "Grace Church")
        #expect(sent == [.showCreated])
        #expect(TelemetryEvent.showCreated.properties.isEmpty)
    }

    @Test("A record press that makes the Show sends show_created; the next Take in the same Show sends none")
    func recordPressMakesShow() async throws {
        var sent: [TelemetryEvent] = []
        let recorder = recorder { sent.append($0) }
        try await record(recorder)
        try await record(recorder)
        #expect(sent.filter { $0 == .showCreated }.count == 1)
    }

    @Test("A refused New Show sends nothing")
    func refusedNewShow() async throws {
        var sent: [TelemetryEvent] = []
        let recorder = recorder { sent.append($0) }
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.getReady(audio)
        try recorder.startTake()
        sent = []
        #expect(throws: RecorderError.takeRunning) { try recorder.startNewShow(name: "Late", venue: "") }
        #expect(sent.isEmpty)
        try await recorder.stopTake()
    }

    @Test("Deleting a Show sends show_deleted once; a refused delete sends nothing")
    func deleteShow() async throws {
        var sent: [TelemetryEvent] = []
        let recorder = recorder { sent.append($0) }
        try await record(recorder)
        let first = try #require(recorder.currentShow?.name)
        try recorder.startNewShow(name: "Next", venue: "")
        sent = []

        #expect(recorder.deleteShow(named: "No Such Show", from: [.device]).deleted.isEmpty)
        #expect(sent.isEmpty)

        #expect(recorder.deleteShow(named: first, from: [.device]).deleted == [.device])
        #expect(sent == [.showDeleted])
    }
}
