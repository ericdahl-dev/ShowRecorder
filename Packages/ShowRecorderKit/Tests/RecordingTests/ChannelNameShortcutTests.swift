import Testing

@testable import Recording

/// Shortcut chips on the channel names page.
@Suite("Channel name shortcuts")
struct ChannelNameShortcutTests {
    @Test("A plain shortcut fills its own name")
    func plain() {
        #expect(ChannelNameShortcut.kick.name(taken: []) == "Kick")
        #expect(ChannelNameShortcut.leadVox.name(taken: ["Vox 1"]) == "Lead Vox")
    }

    @Test("A numbered shortcut takes the lowest number no other row has: Vox 1, Vox 2, then a gap is refilled")
    func numbered() {
        #expect(ChannelNameShortcut.vox.name(taken: []) == "Vox 1")
        #expect(ChannelNameShortcut.vox.name(taken: ["Vox 1", "Kick"]) == "Vox 2")
        #expect(ChannelNameShortcut.vox.name(taken: ["Vox 1", "Vox 3"]) == "Vox 2")
        #expect(ChannelNameShortcut.vox.name(taken: ["vox 1"]) == "Vox 2", "names are compared without case")
        #expect(ChannelNameShortcut.tom.name(taken: ["Vox 1"]) == "Tom 1")
    }

    @Test("The list is the common names, plain and numbered")
    func list() {
        let names = ChannelNameShortcut.all.map(\.title)
        #expect(names.contains("Kick") && names.contains("Vox 1…") == false && names.contains("Vox"))
        #expect(ChannelNameShortcut.all.count == Set(names).count)
    }
}
