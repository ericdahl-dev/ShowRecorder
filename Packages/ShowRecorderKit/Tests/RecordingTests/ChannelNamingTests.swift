import AudioIO
import Foundation
import MixerLink
import Testing

@testable import Recording

/// Who names each USB Channel (#443): a typed name wins over the Mixer's, which wins over "USB 07". Keyed from 1.
@MainActor
@Suite("Channel naming")
struct ChannelNamingTests {
    static let sources = [
        Source(name: "Kick", color: .off),
        Source.fallback(usbChannel: 2),
        Source(name: "Bass", color: .off),
    ]

    @Test("One row per channel, numbered from 1, showing the typed name; the hint is the Mixer's name or the USB default")
    func rows() {
        let naming = ChannelNaming(typed: [2: "Snare Top"])
        let rows = naming.rows(channelCount: 3, sources: Self.sources)
        #expect(rows.map(\.number) == [1, 2, 3])
        #expect(rows.map(\.name) == ["", "Snare Top", ""])
        #expect(rows.map(\.hint) == ["Kick", "USB 02", "Bass"])
    }

    @Test("What a channel is called: typed, else the Mixer's, else USB; the naming box starts from typed, else the Mixer's, else empty")
    func names() {
        let naming = ChannelNaming(typed: [3: "Bass DI"])
        #expect(naming.displayName(1, sources: Self.sources) == "Kick")
        #expect(naming.displayName(2, sources: Self.sources) == "USB 02")
        #expect(naming.displayName(3, sources: Self.sources) == "Bass DI")
        #expect(naming.displayName(4, sources: Self.sources) == "USB 04", "past the Mixer's Sources")
        #expect(naming.editText(1, sources: Self.sources) == "Kick")
        #expect(naming.editText(2, sources: Self.sources) == "")
        #expect(naming.editText(3, sources: Self.sources) == "Bass DI")
    }

    @Test("Typing trims, refuses a blank name, and clearing says whether there was one")
    func typing() {
        var naming = ChannelNaming()
        let typed = naming.type("  Vox  ", for: 1), blank = naming.type("   ", for: 2)
        #expect(typed && !blank)
        #expect(naming.typed == [1: "Vox"])
        let cleared = naming.clear(1), again = naming.clear(1)
        #expect(cleared && !again)
    }

    @Test("At record press typed names name the Stems only when the Take may use them; Free keeps the Mixer's")
    func takeSources() {
        let naming = ChannelNaming(typed: [1: "Kick In"])
        let pro = naming.sources(for: Self.sources, channelCount: 4, allowance: nil)
        #expect(pro.map(\.name) == ["Kick In", "USB 02", "Bass", "USB 04"])
        #expect(!pro[0].hasMixerName)
        let free = Entitlement.allowance(for: .free, channelCount: 4, freeChoice: [1, 2])
        #expect(naming.sources(for: Self.sources, channelCount: 4, allowance: free).map(\.name) == ["Kick", "USB 02", "Bass", "USB 04"])
    }

    @Test("A Take that started without Mixer names takes the first ones offered; at its end typed names win over them")
    func lateNames() {
        var naming = ChannelNaming(typed: [2: "Snare"])
        naming.takeStarted(with: [Source.fallback(usbChannel: 1), Source.fallback(usbChannel: 2)])
        naming.mixerOffered([Source(name: "Kick", color: .off), Source(name: "Snr", color: .off)])
        naming.mixerOffered([Source(name: "Later", color: .off), Source(name: "Later", color: .off)])
        let end = naming.takeEnded(allowance: nil, onFiles: [1: "USB 01", 2: "USB 02"])
        #expect(end.names == [1: "Kick", 2: "Snare"])
        #expect(end.late == [1])
        let next = naming.takeEnded(allowance: nil, onFiles: [1: "USB 01", 2: "USB 02"])
        #expect(next.names == [2: "Snare"], "late names are used once")
    }

    @Test("A Take that started with Mixer names takes no late ones, and Free puts no typed names on files")
    func noLateNamesAndFree() {
        var naming = ChannelNaming(typed: [1: "Kick In"])
        naming.takeStarted(with: [Source(name: "Kick", color: .off)])
        naming.mixerOffered([Source(name: "Other", color: .off)])
        let free = Entitlement.allowance(for: .free, channelCount: 1, freeChoice: [1])
        let onFree = naming.takeEnded(allowance: free, onFiles: [1: "Kick"])
        #expect(onFree.names.isEmpty)
        let onPro = naming.takeEnded(allowance: nil, onFiles: [1: "Kick"])
        #expect(onPro.names == [1: "Kick In"])
        let done = naming.takeEnded(allowance: nil, onFiles: [1: "Kick In"])
        #expect(done.names.isEmpty, "already on the files")
    }

    @Test("A Stem's file name stays under the file systems' 255 bytes, whatever the name's characters")
    func stemFileNameBytes() {
        let name = StemFileName.make(usbChannel: 7, sourceName: String(repeating: "🥁", count: 80))
        #expect(name.utf8.count <= 255)
        #expect(name.hasPrefix("07 🥁") && name.hasSuffix(".wav"))
        #expect(StemFileName.make(usbChannel: 7, sourceName: String(repeating: "a", count: 80)) == "07 \(String(repeating: "a", count: 64)).wav")
    }

    @Test("Clearing a row takes the typed name away for the Show's later Takes, in Show.json too")
    func clearingARow() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ChannelNameListTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 2)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        try recorder.stopTake()
        recorder.setChannelName("Bass", forChannel: 1)
        recorder.setChannelName("Keys", forChannel: 2)

        recorder.clearChannelName(forChannel: 1)

        #expect(recorder.channelNames == [2: "Keys"])
        #expect(ShowFile.read(from: root.appending(path: "2026-10-06 Show"))?.channelNames == ["2": "Keys"])
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "2026-10-06 Show/Take 02/01 USB 01.wav").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "2026-10-06 Show/Take 02/02 Keys.wav").path))
    }
}
