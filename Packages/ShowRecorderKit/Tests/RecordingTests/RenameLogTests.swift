import AudioIO
import Foundation
import MixerLink
@testable import Recording
import Testing

/// A Mixer rename during a Take leaves the Stems alone and is logged in `Take.json`.
@MainActor
@Suite("Rename log")
struct RenameLogTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "RenameLogTests-\(UUID().uuidString)")
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
    func record(startSources: [Source] = Self.real, typed: [Int: String] = [:], during: (Recorder, FakeAudioDevice) -> Void) async throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        for (number, name) in typed { _ = recorder.setChannelName(name, forChannel: number) }
        try recorder.startTake(sources: startSources)
        device.deliver(Array(repeating: [0], count: 2))
        during(recorder, device)
        try recorder.stopTake()
        await recorder.waitForRepair()
    }

    @Test("A rename during a Take is logged with its sample position, old and new name, and the Stem keeps its name")
    func logsRename() async throws {
        try await record { recorder, device in
            for _ in 0..<3 { device.deliver(Array(repeating: [0, 0, 0, 0], count: 2)) }
            recorder.offerSources([Source(name: "Snare", color: .off), Self.real[1]])
        }

        let renames = try #require(try metadata().renames)
        #expect(renames.map(\.usbChannel) == [1])
        #expect(renames.map(\.from) == ["Kick"])
        #expect(renames.map(\.to) == ["Snare"])
        #expect(renames[0].position > 0)
        #expect(FileManager.default.fileExists(atPath: take.appending(path: "01 Kick.wav").path))
        #expect(try metadata().usbChannels.map(\.name) == ["Kick", "Lead Vocal"])
    }

    @Test("Offering the same names again logs nothing, and a Take with no renames carries no log")
    func repeatsAreNotRenames() async throws {
        try await record { recorder, _ in
            recorder.offerSources(Self.real)
            recorder.offerSources(Self.real)
        }
        let json = try String(contentsOf: take.appending(path: "Take.json"), encoding: .utf8)
        #expect(!json.contains("renames"))
        #expect(try metadata().renames == nil)
    }

    @Test("Each of several renames is logged in order, the same channel twice from its previous name")
    func severalRenames() async throws {
        try await record { recorder, _ in
            recorder.offerSources([Source(name: "Snare", color: .off), Self.real[1]])
            recorder.offerSources([Source(name: "Snare Top", color: .off), Source(name: "Vox", color: .off)])
        }
        let renames = try #require(try metadata().renames)
        #expect(renames.map(\.usbChannel) == [1, 1, 2])
        #expect(renames.map(\.from) == ["Kick", "Snare", "Lead Vocal"])
        #expect(renames.map(\.to) == ["Snare", "Snare Top", "Vox"])
    }

    @Test("A Take started without a Mixer Link logs the names that arrive; they are also put on its Stems")
    func lateNamesAreLogged() async throws {
        try await record(startSources: []) { recorder, _ in recorder.offerSources(Self.real) }
        let renames = try #require(try metadata().renames)
        #expect(renames.map(\.from) == ["USB 01", "USB 02"])
        #expect(renames.map(\.to) == ["Kick", "Lead Vocal"])
        #expect(FileManager.default.fileExists(atPath: take.appending(path: "01 Kick.wav").path))
    }
}
