import AudioIO
import Foundation
import MixerLink
@testable import Recording
import Testing

/// A Take started with no Mixer Link adopts the first real Source names that arrive during it.
@MainActor
@Suite("Late Source names")
struct LateSourceNamesTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "LateSourceNamesTests-\(UUID().uuidString)")
    var take: URL { root.appending(path: "2026-10-06 Show/Take 01") }

    static let real = [
        Source(name: "Kick", color: MixerColor(hue: .red, inverted: false)),
        Source(name: "Lead Vocal", color: MixerColor(hue: .yellow, inverted: true)),
    ]

    func metadata() throws -> TakeMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: Data(contentsOf: take.appending(path: "Take.json")))
    }

    /// Records a 2-channel Take that starts with `startSources`; `during` runs while recording.
    func record(startSources: [Source] = [], typed: [Int: String] = [:], during: (Recorder) -> Void) async throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        for (number, name) in typed { _ = recorder.setChannelName(name, forChannel: number) }
        try recorder.startTake(sources: startSources)
        device.deliver(Array(repeating: [0], count: 2))
        during(recorder)
        try recorder.stopTake()
        await recorder.waitForRepair()
    }

    @Test("Source names that arrive during a Take started without a Mixer Link name its Stems when the Take finalizes")
    func adoptsLateNames() async throws {
        try await record { $0.offerSources(Self.real) }

        #expect(try StemFile(contentsOf: take.appending(path: "01 Kick.wav")).description == "Kick")
        #expect(try StemFile(contentsOf: take.appending(path: "02 Lead Vocal.wav")).description == "Lead Vocal")
        let channels = try metadata().usbChannels
        #expect(channels.map(\.name) == ["Kick", "Lead Vocal"])
        #expect(channels.map(\.hasMixerName) == [true, true])
    }

    @Test("Take.json notes which names arrived late; Takes without late names carry no note")
    func notesLateNames() async throws {
        try await record { $0.offerSources(Self.real) }
        #expect(try metadata().usbChannels.map(\.nameArrivedLate) == [true, true])

        let other = LateSourceNamesTests()
        try await other.record(startSources: Self.real) { _ in }
        #expect(try other.metadata().usbChannels.map(\.nameArrivedLate) == [nil, nil])
    }

    @Test("A Take that started with real names stays frozen, whatever arrives later")
    func realNamesStayFrozen() async throws {
        try await record(startSources: Self.real) { $0.offerSources([Source(name: "Snare", color: .off), Source(name: "Bass", color: .off)]) }
        #expect(try metadata().usbChannels.map(\.name) == ["Kick", "Lead Vocal"])
        #expect(FileManager.default.fileExists(atPath: take.appending(path: "01 Kick.wav").path))
    }

    @Test("Only the first real names received are adopted")
    func firstNamesOnly() async throws {
        try await record {
            $0.offerSources([Source.fallback(usbChannel: 1), Source.fallback(usbChannel: 2)])
            $0.offerSources(Self.real)
            $0.offerSources([Source(name: "Snare", color: .off), Source(name: "Bass", color: .off)])
        }
        #expect(try metadata().usbChannels.map(\.name) == ["Kick", "Lead Vocal"])
    }

    @Test("A channel with a typed name keeps it; the others take the Mixer's")
    func typedNameWins() async throws {
        try await record(typed: [1: "Bass Drum"]) { $0.offerSources(Self.real) }
        let channels = try metadata().usbChannels
        #expect(channels.map(\.name) == ["Bass Drum", "Lead Vocal"])
        #expect(channels.map(\.hasMixerName) == [false, true])
        #expect(channels.map(\.nameArrivedLate) == [nil, true])
    }

    @Test("A Take.json from before late names existed still decodes")
    func oldTakeDecodes() async throws {
        try await record { _ in }
        let json = try String(contentsOf: take.appending(path: "Take.json"), encoding: .utf8)
        #expect(!json.contains("nameArrivedLate"))
        #expect(try metadata().usbChannels.map(\.nameArrivedLate) == [nil, nil])
    }
}
