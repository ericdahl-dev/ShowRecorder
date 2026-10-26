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

    @Test("At record press typed names name the Stems only when the Take may use them; Free gets generic names and no colors, not the Mixer's (#705)")
    func takeSources() {
        let red = MixerColor(hue: .red, inverted: false)
        let mixer = [Source(name: "Kick", color: red), Source.fallback(usbChannel: 2), Source(name: "Bass", color: red)]
        let naming = ChannelNaming(typed: [1: "Kick In"])
        let pro = naming.sources(for: mixer, channelCount: 4, allowance: nil)
        #expect(pro.map(\.name) == ["Kick In", "USB 02", "Bass", "USB 04"])
        #expect(!pro[0].hasMixerName)
        #expect(pro[2].color == red && pro[2].hasMixerName)
        let free = naming.sources(for: mixer, channelCount: 4, allowance: Entitlement.allowance(for: .free, channelCount: 4))
        #expect(free.map(\.name) == ["USB 01", "USB 02", "USB 03", "USB 04"])
        #expect(free.allSatisfy { $0.color == .off && !$0.hasMixerName })
    }

    @Test("A Free Take that started without Mixer names takes none offered later either (#705)")
    func noLateNamesOnFree() {
        var naming = ChannelNaming()
        naming.takeStarted(with: [Source.fallback(usbChannel: 1)])
        naming.mixerOffered([Source(name: "Kick", color: .off)])
        let free = Entitlement.allowance(for: .free, channelCount: 1)
        let end = naming.takeEnded(allowance: free, onFiles: [1: "USB 01"])
        #expect(end.names.isEmpty && end.late.isEmpty)
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

    static func routed(_ name: String, from route: String?) -> Source {
        var source = Source(name: name, color: .off)
        source.routedFrom = route
        return source
    }

    @Test("A name the Mixer changes during a Take on the same routing is a rename, once (#557)")
    func renamedDuringATake() {
        var naming = ChannelNaming()
        naming.takeStarted(with: [Self.routed("Kick", from: "In 1"), Self.routed("Snare", from: "In 2")])

        let events = naming.mixerOffered([Self.routed("Kick In", from: "In 1"), Self.routed("Snare", from: "In 2")])

        #expect(events == [.renamed(channel: 1, from: "Kick", to: "Kick In")])
        #expect(naming.mixerOffered([Self.routed("Kick In", from: "In 1"), Self.routed("Snare", from: "In 2")]).isEmpty, "a repeat is nothing")
    }

    @Test("A channel the Mixer re-patches is a re-patch, not a rename; a sweep of the source selector is a re-patch each time (#557)")
    func repatchedDuringATake() {
        var naming = ChannelNaming()
        naming.takeStarted(with: [Self.routed("Kick", from: "In 1")])

        let first = naming.mixerOffered([Self.routed("Vox", from: "In 5")])
        let second = naming.mixerOffered([Self.routed("Bass", from: "In 6")])

        #expect(first == [.repatched(channel: 1, from: "Kick", to: "Vox")])
        #expect(second == [.repatched(channel: 1, from: "Vox", to: "Bass")])
    }

    @Test("A re-patch and a rename in one offer come back re-patch first, even when the re-patched channel is the higher one (#557)")
    func repatchBeforeRename() {
        var naming = ChannelNaming()
        naming.takeStarted(with: [Self.routed("Kick", from: "In 1"), Self.routed("Snare", from: "In 2")])

        let events = naming.mixerOffered([Self.routed("Kick In", from: "In 1"), Self.routed("Vox", from: "In 9")])

        #expect(events == [.repatched(channel: 2, from: "Snare", to: "Vox"), .renamed(channel: 1, from: "Kick", to: "Kick In")])
        #expect(naming.mixerOffered([Self.routed("Kick In", from: "In 1"), Self.routed("Vox", from: "In 9")]).isEmpty, "a repeat is nothing")
    }

    @Test("Names offered late are kept for the Take's end, and their first offer is not a rename of the USB names (#557)")
    func lateNamesAndChanges() {
        var naming = ChannelNaming()
        naming.takeStarted(with: [.fallback(usbChannel: 1)])

        let events = naming.mixerOffered([Source(name: "Kick", color: .off)])
        let ended = naming.takeEnded(allowance: nil, onFiles: [1: "USB 01"])

        #expect(events == [.renamed(channel: 1, from: "USB 01", to: "Kick")], "logged on the Take, as before")
        #expect(ended.names == [1: "Kick"], "and put on the files at its end")
    }

    @Test("The first routing known for a channel is only noted; a re-patch to a Source with no routing stays a rename (#557)")
    func routingFirstKnownAndUnknown() {
        var naming = ChannelNaming()
        naming.takeStarted(with: [Self.routed("Kick", from: nil)])

        #expect(naming.mixerOffered([Self.routed("Kick", from: "In 1")]).isEmpty, "routing arrives late: noted, no event")
        #expect(naming.mixerOffered([Self.routed("Vox", from: nil)]) == [.renamed(channel: 1, from: "Kick", to: "Vox")])
    }

    @Test("A channel past the Take's start Sources compares with its USB name (#557)")
    func renamedFromTheUSBName() {
        var naming = ChannelNaming()
        naming.takeStarted(with: [])

        #expect(naming.mixerOffered([Self.routed("Kick", from: nil)]) == [.renamed(channel: 1, from: "USB 01", to: "Kick")])
    }

    @Test("Typed names are remembered as chips, newest first, one per name whatever the case; the built-in shortcut names are not (#557)")
    func typedNamesBecomeChips() {
        var naming = ChannelNaming()
        for (channel, name) in [(1, "Pastor Mike"), (2, "Choir mic"), (3, "Kick"), (4, "Vox 2"), (5, "pastor mike")] { naming.type(name, for: channel) }

        #expect(naming.saved == ["pastor mike", "Choir mic"])
        naming.type("   ", for: 6)
        #expect(naming.saved == ["pastor mike", "Choir mic"], "a refused name is not remembered")
    }

    @Test("Copying a Show's names replaces the typed ones and remembers them, the lowest channel's name newest; it says how many (#557)")
    func copyingNames() {
        var naming = ChannelNaming(typed: [9: "Old"], saved: ["Old"])

        let count = naming.copy([1: "Pastor", 2: "Choir"])

        #expect(count == 2)
        #expect(naming.typed == [1: "Pastor", 2: "Choir"])
        #expect(naming.saved == ["Pastor", "Choir", "Old"])
    }

    @Test("The chips are kept on the device and come back (#557)")
    func chipsPersist() throws {
        let suite = "ChannelNamingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var naming = ChannelNaming()
        naming.type("Choir mic", for: 1)
        naming.persist(to: defaults)

        #expect(ChannelNaming(typed: [:], saved: SavedChannelNames.load(from: defaults)).saved == ["Choir mic"])
    }

    @Test("A Take that started with Mixer names takes no late ones, and Free puts no typed names on files")
    func noLateNamesAndFree() {
        var naming = ChannelNaming(typed: [1: "Kick In"])
        naming.takeStarted(with: [Source(name: "Kick", color: .off)])
        naming.mixerOffered([Source(name: "Other", color: .off)])
        let free = Entitlement.allowance(for: .free, channelCount: 1)
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
        try await recorder.stopTake()
        recorder.setChannelName("Bass", forChannel: 1)
        recorder.setChannelName("Keys", forChannel: 2)

        recorder.clearChannelName(forChannel: 1)

        #expect(recorder.channelNames == [2: "Keys"])
        #expect(ShowFile.read(from: root.appending(path: "2026-10-06 Show"))?.channelNames == ["2": "Keys"])
        try recorder.startTake()
        audio.deliver([[0.1], [0.1]])
        try await recorder.stopTake()
        await recorder.waitForRepair()
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "2026-10-06 Show/Take 02/01 USB 01.wav").path))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "2026-10-06 Show/Take 02/02 Keys.wav").path))
    }
}
