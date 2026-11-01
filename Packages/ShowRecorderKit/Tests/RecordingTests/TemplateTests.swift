import AudioIO
import Foundation
import MixerLink
@testable import Recording
import Testing

/// Templates: a venue's whole setup, saved on this device, to start a Show from in one tap (#33, ADR 0004).
@MainActor
@Suite("Templates")
struct TemplateTests {
    let defaults = UserDefaults(suiteName: "TemplateTests-\(UUID().uuidString)")!

    func sunday() -> Template {
        Template(
            name: "Sunday Service", venue: "Main hall", channelNames: [1: "Pastor", 3: "Keys"],
            mixerNetworkName: "Skeyelab XR18", mixerAddress: "192.168.1.146", preRollSeconds: 10)
    }

    @Test("Templates are kept on the device, listed by name, and can be renamed and deleted")
    func store() throws {
        var store = TemplateStore(defaults: defaults)
        store.save(sunday())
        store.save(Template(name: "Friday gig", venue: nil, channelNames: [:], mixerNetworkName: nil, mixerAddress: "", preRollSeconds: 0))
        #expect(TemplateStore(defaults: defaults).templates.map(\.name) == ["Friday gig", "Sunday Service"])
        #expect(TemplateStore(defaults: defaults).templates.last == sunday().withID(store.templates.last!.id))

        let friday = try #require(store.templates.first)
        store.rename(friday.id, to: "Bar gig")
        store.delete(store.templates.first { $0.name == "Sunday Service" }!.id)
        #expect(TemplateStore(defaults: defaults).templates.map(\.name) == ["Bar gig"])
    }

    @Test("Starting a Show from a Template names it after the Template and brings its venue and channel names, even replacing an open Show; never during a Take")
    func startShow() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TemplateTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, savedNames: defaults)
        let audio = FakeAudioDevice(inputChannelCount: 4)
        try recorder.getReady(audio)
        try recorder.startNewShow(name: "Rehearsal", venue: "")
        recorder.setChannelName("Old", forChannel: 2)

        try recorder.startNewShow(from: sunday())
        #expect(recorder.currentShow?.name.hasSuffix(" Sunday Service") == true)
        #expect(recorder.currentShow?.venue == "Main hall")
        #expect(recorder.channelNames == [1: "Pastor", 3: "Keys"])
        #expect(recorder.savedChannelNames.contains("Pastor"), "the names come back as chips, like typed ones")

        try recorder.startTake()
        #expect(throws: RecorderError.takeRunning) { try recorder.startNewShow(from: sunday()) }
        try await recorder.stopTake()
    }

    @Test("Templates can be used between Takes; on Free (once Pro is offered) they are listed as Pro, and nothing saved is lost")
    func access() {
        #expect(License(proOffered: false, tier: .free, trialStarted: false).templateAccess(isRecording: false) == .usable)
        #expect(License(proOffered: true, tier: .trial(daysLeft: 5), trialStarted: false).templateAccess(isRecording: false) == .usable)
        #expect(License(proOffered: true, tier: .pro, trialStarted: false).templateAccess(isRecording: false) == .usable)
        #expect(License(proOffered: true, tier: .free, trialStarted: false).templateAccess(isRecording: false) == .proOnly)
        #expect(License(proOffered: true, tier: .pro, trialStarted: false).templateAccess(isRecording: true) == .takeRunning)
        #expect(TemplateAccess.proOnly.note == "Templates are part of Pro. Your saved Templates are kept.")
    }

    @Test("The Template's Mixer is found by its network name when its address changed; otherwise the saved address")
    func mixerAddress() {
        let moved = FoundMixer(host: "192.168.1.77", identity: MixerIdentity(networkName: "Skeyelab XR18", model: "XR18", firmware: "1.20"))
        let other = FoundMixer(host: "192.168.1.20", identity: MixerIdentity(networkName: "Stage XR18", model: "XR18", firmware: "1.20"))
        #expect(sunday().connectAddress(found: [other, moved]) == "192.168.1.77")
        #expect(sunday().connectAddress(found: [other]) == "192.168.1.146")
        #expect(sunday().connectAddress(found: []) == "192.168.1.146")
    }

    @Test("The default Template readies the next Show without creating one: the next record starts it, named after the Template, with its names (#34)")
    func prepareNextShow() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TemplateTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, savedNames: defaults)
        let audio = FakeAudioDevice(inputChannelCount: 4)
        try recorder.getReady(audio)

        #expect(recorder.prepareNextShow(from: sunday()))
        #expect(recorder.currentShow == nil, "no empty Show folder at launch")
        #expect(recorder.channelNames == [1: "Pastor", 3: "Keys"])

        try recorder.startTake()
        try await recorder.stopTake()
        #expect(recorder.currentShow?.name.hasSuffix(" Sunday Service") == true)
        #expect(recorder.currentShow?.venue == "Main hall")
        #expect(recorder.currentShow?.channelNames == [1: "Pastor", 3: "Keys"])

        // With a Show open, nothing changes.
        #expect(!recorder.prepareNextShow(from: Template(name: "Other", venue: nil, channelNames: [2: "X"], mixerNetworkName: nil, mixerAddress: "", preRollSeconds: 0)))
        #expect(recorder.channelNames == [1: "Pastor", 3: "Keys"])
    }

    @Test("One Template can be the default; it is kept across launches, can be cleared, and deleting it clears it (#34)")
    func defaultTemplate() throws {
        var store = TemplateStore(defaults: defaults)
        store.save(sunday())
        let id = try #require(store.templates.first?.id)
        #expect(store.defaultTemplate == nil)
        store.setDefault(id)
        #expect(TemplateStore(defaults: defaults).defaultTemplate?.name == "Sunday Service")
        store.setDefault(nil)
        #expect(TemplateStore(defaults: defaults).defaultTemplate == nil)
        store.setDefault(id)
        store.delete(id)
        #expect(TemplateStore(defaults: defaults).defaultTemplate == nil)
    }

    @Test("A past Show's setup can be saved as a Template: its channel names and venue, named like the Show without the date (#34)")
    func fromPastShow() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TemplateTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, savedNames: defaults)
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 2))
        try recorder.startNewShow(name: "Youth Night", venue: "Gym")
        recorder.setChannelName("Leader", forChannel: 2)
        let folder = try #require(recorder.currentShow?.folder)
        try recorder.endShow()

        let template = try #require(Template.fromShow(folder: folder, mixerNetworkName: "Skeyelab XR18", mixerAddress: "192.168.1.146", preRollSeconds: 5))
        #expect(template.name == "Youth Night")
        #expect(template.venue == "Gym")
        #expect(template.channelNames == [2: "Leader"])
        #expect(template.mixerNetworkName == "Skeyelab XR18" && template.preRollSeconds == 5)
        #expect(Template.fromShow(folder: root.appending(path: "nope"), mixerNetworkName: nil, mixerAddress: "", preRollSeconds: 0) == nil)
    }

    @Test("A Template keeps its Record to choice on the device (#840)")
    func recordToKept() {
        var store = TemplateStore(defaults: defaults)
        var template = sunday()
        template.recordTo = .drive
        store.save(template)
        #expect(TemplateStore(defaults: defaults).templates.first?.recordTo == .drive)
    }

    @Test("A Template saved before Record to loads with no Record to choice (#840)")
    func oldTemplateHasNoRecordTo() throws {
        let old = #"[{"id":"\#(UUID().uuidString)","name":"Old","channelNames":{"1":"Pastor"},"mixerAddress":"192.168.1.146","preRollSeconds":10}]"#
        defaults.set(Data(old.utf8), forKey: TemplateStore.key)
        let store = TemplateStore(defaults: defaults)
        #expect(!store.couldNotRead)
        let template = try #require(store.templates.first)
        #expect(template.name == "Old" && template.recordTo == nil)
    }

    @Test("A Template keeps which USB Channels are not armed, and one saved before that leaves the current choice (#991)")
    func notArmedKept() throws {
        var store = TemplateStore(defaults: defaults)
        var template = sunday()
        template.notArmedChannels = [3, 5]
        store.save(template)
        #expect(TemplateStore(defaults: defaults).templates.first?.notArmedChannels == [3, 5])

        let old = #"[{"id":"\#(UUID().uuidString)","name":"Old","channelNames":{},"mixerAddress":"","preRollSeconds":0}]"#
        defaults.set(Data(old.utf8), forKey: TemplateStore.key)
        #expect(try #require(TemplateStore(defaults: defaults).templates.first).notArmedChannels == nil)
    }

    @Test("A Template from a past Show takes today's Record to choice (#840)")
    func fromPastShowRecordTo() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TemplateTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, savedNames: defaults)
        try recorder.getReady(FakeAudioDevice(inputChannelCount: 2))
        try recorder.startNewShow(name: "Youth Night", venue: "Gym")
        let folder = try #require(recorder.currentShow?.folder)
        try recorder.endShow()

        let template = try #require(Template.fromShow(
            folder: folder, mixerNetworkName: nil, mixerAddress: "", preRollSeconds: 0, recordTo: .device))
        #expect(template.recordTo == .device)
    }

    @Test("A Template store that can't be read is kept aside, not erased by the next save, and says it couldn't be read (#325)")
    func unreadableStoreKept() throws {
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: TemplateStore.key)
        var store = TemplateStore(defaults: defaults)
        #expect(store.templates.isEmpty)
        #expect(store.couldNotRead)
        store.save(sunday())
        #expect(defaults.data(forKey: TemplateStore.unreadableKey) == garbage, "the old store is kept aside")
        #expect(TemplateStore(defaults: defaults).templates.map(\.name) == ["Sunday Service"])
        #expect(!TemplateStore(defaults: defaults).couldNotRead)
    }
}
