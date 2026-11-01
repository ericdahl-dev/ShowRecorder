import AudioIO
import Foundation
@testable import Recording
import Testing

/// The record screen's Dropout count, as the recorder exposes it.
@MainActor
@Suite("Dropout count")
struct DropoutCountTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "DropoutCountTests-\(UUID().uuidString)")


    /// Records a Take in which the ring drops one block: 480 frames, then 200,000 at once (more than a
    /// ring holds), then 480 more.
    func recordWithADropout(_ recorder: Recorder, on device: FakeAudioDevice) async throws {
        try recorder.startTake()
        device.deliver([Array(repeating: 0, count: 480)])
        device.deliver([Array(repeating: 0, count: 200_000)])
        device.deliver([Array(repeating: 0, count: 480)])
        try await waitUntil { recorder.bufferedFrameCount == 0 }
    }

    @Test("A Take that lost audio shows one Dropout once the recorder has looked")
    func countsADropout() async throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        try recorder.getReady(device)
        #expect(recorder.dropoutCount == 0)

        try await recordWithADropout(recorder, on: device)
        try await waitUntilAsync { await recorder.checkDestinations(); return recorder.dropoutCount == 1 }
        #expect(recorder.dropoutCount == 1)
        #expect(recorder.markerEntries.map(\.kind) == [.dropout])
        #expect(recorder.markerEntries.map(\.isDropout) == [true])
        try await recorder.stopTake()
    }

    @Test("The operator's Marker count doesn't include Dropout Markers")
    func markerCountIsTheOperators() async throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        try recorder.getReady(device)
        try await recordWithADropout(recorder, on: device)
        try await waitUntilAsync { await recorder.checkDestinations(); return recorder.dropoutCount == 1 }

        recorder.addMarker()
        #expect(recorder.takeMarkers.count == 1)
        #expect(recorder.takeMarkers.first?.origin == .operator)
        try await recorder.stopTake()
    }

    @Test("The count stays after the Take ends and starts again at zero for the next one")
    func staysThenResets() async throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, destinationCheckInterval: nil)
        try recorder.getReady(device)
        try await recordWithADropout(recorder, on: device)
        try await recorder.stopTake()
        #expect(recorder.dropoutCount == 1)

        try recorder.startTake()
        #expect(recorder.dropoutCount == 0)
        try await recorder.stopTake()
    }
}
