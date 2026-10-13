import AudioIO
import Foundation
import MixerLink
@testable import Recording
import TakeFile
import Testing

/// Every gain change ShowRecorder makes on the Mixer is logged (#450): in the Take during a Take, with a Marker, and
/// in the Show between Takes.
@MainActor
@Suite("Gain log")
struct GainLogTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "GainLogTests-\(UUID().uuidString)")
    var show: URL { root.appending(path: "2026-10-06 Show") }

    static let change = TakeMetadata.GainChange(
        usbChannel: 1, channel: 1, headamp: 1, fromGainDb: 14.5, toGainDb: 17.5, reason: .autoGain,
        compensations: [.init(channel: 1, setting: "fader", fromDb: -6.2, toDb: -9.2)])

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test("During a Take: logged in Take.json at its sample position, with a Marker that says what changed")
    func duringATake() async throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        try recorder.startTake(sources: [Source(name: "Kick", color: .off), Source(name: "Snare", color: .off)])
        for _ in 0..<3 { device.deliver(Array(repeating: [0, 0, 0, 0], count: 2)) }

        recorder.logGainChange(Self.change)
        try recorder.stopTake()
        await recorder.waitForRepair()

        let metadata = try Self.decoder().decode(TakeMetadata.self, from: Data(contentsOf: show.appending(path: "Take 01/Take.json")))
        let logged = try #require(metadata.gainChanges?.first)
        #expect(logged.usbChannel == 1 && logged.fromGainDb == 14.5 && logged.toGainDb == 17.5 && logged.reason == .autoGain)
        #expect(logged.position != nil)
        #expect(logged.compensations == Self.change.compensations)
        let marker = try #require(metadata.markers.first { $0.origin == .gain })
        #expect(marker.name == "Kick: gain +3.0 dB (auto-gain)")
        #expect(marker.position == logged.position)
        #expect(metadata.operatorMarkers.isEmpty, "a gain Marker isn't one of the operator's")
    }

    @Test("Between Takes: logged in Show.json, with no position")
    func betweenTakes() async throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        try recorder.startTake()
        device.deliver(Array(repeating: [0], count: 2))
        try recorder.stopTake()
        await recorder.waitForRepair()

        recorder.logGainChange(Self.change)

        let file = try #require(ShowFile.read(from: show))
        let logged = try #require(file.gainChanges?.first)
        #expect(logged.toGainDb == 17.5)
        #expect(logged.position == nil)
    }
}
