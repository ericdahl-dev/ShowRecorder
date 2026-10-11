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
    func startShow() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "TemplateTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay }, savedNames: defaults)
        let audio = FakeAudioDevice(inputChannelCount: 4)
        try recorder.arm(audio)
        try recorder.startNewShow(name: "Rehearsal", venue: "")
        recorder.setChannelName("Old", forChannel: 2)

        try recorder.startNewShow(from: sunday())
        #expect(recorder.currentShow?.name.hasSuffix(" Sunday Service") == true)
        #expect(recorder.currentShow?.venue == "Main hall")
        #expect(recorder.channelNames == [1: "Pastor", 3: "Keys"])
        #expect(recorder.savedChannelNames.contains("Pastor"), "the names come back as chips, like typed ones")

        try recorder.startTake()
        #expect(throws: RecorderError.takeRunning) { try recorder.startNewShow(from: sunday()) }
        try recorder.stopTake()
    }

    @Test("Templates can be used between Takes; on Free (once Pro is offered) they are listed as Pro, and nothing saved is lost")
    func access() {
        #expect(TemplateAccess(proOffered: false, tier: .free, isRecording: false) == .usable)
        #expect(TemplateAccess(proOffered: true, tier: .trial(daysLeft: 5), isRecording: false) == .usable)
        #expect(TemplateAccess(proOffered: true, tier: .pro, isRecording: false) == .usable)
        #expect(TemplateAccess(proOffered: true, tier: .free, isRecording: false) == .proOnly)
        #expect(TemplateAccess(proOffered: true, tier: .pro, isRecording: true) == .takeRunning)
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
}
