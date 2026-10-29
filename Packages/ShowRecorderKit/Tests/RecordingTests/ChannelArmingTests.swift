import AudioIO
import Destinations
import Foundation
@testable import Recording
@testable import ShowReport
import Testing

/// A USB Channel that is not armed gets no Stem (#991). The choice is Pro, and judged when record is pressed (ADR 0004).
@Suite("Channel arming")
struct ChannelArmingTests {
    @Test("Pro and the Trial record only the armed channels; their numbers stay")
    func proRecordsOnlyArmed() {
        for tier in [Tier.pro, .trial(daysLeft: 3)] {
            let allowance = Entitlement.allowance(for: tier, channelCount: 6, notArmed: [3, 5])
            #expect(allowance.recordedChannels == [1, 2, 4, 6])
        }
    }

    @Test("Free, and a Trial that has ended, record every channel: the choice is kept but not applied")
    func freeRecordsAll() {
        let ended = Entitlement.tier(ownsPro: false, trialStartedAt: Date(timeIntervalSince1970: 0), now: Date(timeIntervalSince1970: 15 * 86_400))
        #expect(ended == .free)
        for tier in [Tier.free, ended] {
            #expect(Entitlement.allowance(for: tier, channelCount: 6, notArmed: [3, 5]).recordedChannels == Set(1...6))
        }
    }

    @Test("How many channels a Take records: the armed ones on Pro and the Trial, every one on Free, so the screen never counts a choice Free ignores")
    func recordedCount() {
        func count(_ license: License) -> Int { license.recordedChannelCount(channelCount: 6, notArmed: [3, 5]) }
        #expect(count(License(proOffered: true, tier: .pro, trialStarted: false)) == 4)
        #expect(count(License(proOffered: true, tier: .free, trialStarted: false)) == 6)
        #expect(count(License(proOffered: true, tier: nil, trialStarted: false)) == 6)
        #expect(License(proOffered: true, tier: .free, trialStarted: false).recordedChannelCount(channelCount: 3, notArmed: [1, 2, 3]) == 3)
    }

    @Test("The license reads the tier at press: Pro applies it, Free doesn't, an unknown tier leaves everything on, and no Pro offered means it is unlocked")
    func licenseGate() {
        func recorded(_ license: License) -> Set<Int>? { license.allowance(channelCount: 6, notArmed: [3, 5])?.recordedChannels }
        #expect(recorded(License(proOffered: true, tier: .pro, trialStarted: false)) == [1, 2, 4, 6])
        #expect(recorded(License(proOffered: true, tier: .trial(daysLeft: 2), trialStarted: true)) == [1, 2, 4, 6])
        #expect(recorded(License(proOffered: true, tier: .free, trialStarted: false)) == Set(1...6))
        #expect(recorded(License(proOffered: true, tier: nil, trialStarted: false)) == nil)
        #expect(recorded(License(proOffered: false, tier: nil, trialStarted: false)) == [1, 2, 4, 6])
        // Nothing to leave out and no Pro offered: still nothing limited.
        #expect(License(proOffered: false, tier: nil, trialStarted: false).allowance(channelCount: 6) == nil)
    }
}

@Suite("Channel arming, remembered")
struct ChannelArmingStoreTests {
    func defaults() -> UserDefaults {
        let suite = "ChannelArmingStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("It is offered in Debug builds only, until moved up")
    func debugOnly() {
        #expect(ChannelArmingAvailability.level == .debugOnly)
        #expect(ChannelArmingAvailability.isAvailable(isDebugBuild: true, environment: nil))
        #expect(!ChannelArmingAvailability.isAvailable(isDebugBuild: false, environment: .sandbox))
        #expect(!ChannelArmingAvailability.isAvailable(isDebugBuild: false, environment: nil))
    }

    @Test("Every channel is armed until chosen, and the choice is kept per Audio interface")
    func perInterface() {
        let store = defaults()
        #expect(ChannelArming.notArmed(on: "X18/XR18", from: store).isEmpty)
        ChannelArming.save([3, 5], on: "X18/XR18", to: store)
        ChannelArming.save([1], on: "DJM-V10", to: store)
        #expect(ChannelArming.notArmed(on: "X18/XR18", from: store) == [3, 5])
        #expect(ChannelArming.notArmed(on: "DJM-V10", from: store) == [1])
        #expect(ChannelArming.notArmed(on: "Another", from: store).isEmpty)
        ChannelArming.save([], on: "X18/XR18", to: store)
        #expect(ChannelArming.notArmed(on: "X18/XR18", from: store).isEmpty)
    }
}

/// The Recorder keeps the choice for the Armed Audio interface and locks it during a Take (#991).
@MainActor
@Suite("Channel arming, on the Recorder")
struct RecorderChannelArmingTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "RecorderChannelArmingTests-\(UUID().uuidString)")

    func defaults() -> UserDefaults {
        let suite = "RecorderChannelArmingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func recorder(_ store: UserDefaults, available: Bool = true) -> Recorder {
        Recorder(
            deviceFolder: root, now: { RecordingTakeTests.showDay }, savedNames: store, destinationCheckInterval: nil,
            channelArmingAvailable: { available })
    }

    @Test("Every channel is armed until chosen; the choice counts only the channels it names and comes back for the same interface")
    func chosenAndRemembered() throws {
        let store = defaults()
        let first = recorder(store)
        try first.arm(FakeAudioDevice(name: "X18/XR18", inputChannelCount: 18))
        #expect(first.notArmedChannels.isEmpty)
        #expect(first.setNotArmedChannels([3, 5, 99]))
        #expect(first.notArmedChannels == [3, 5])

        let relaunched = recorder(store)
        try relaunched.arm(FakeAudioDevice(name: "DJM-V10", inputChannelCount: 8))
        #expect(relaunched.notArmedChannels.isEmpty)
        try relaunched.arm(FakeAudioDevice(name: "X18/XR18", inputChannelCount: 18))
        #expect(relaunched.notArmedChannels == [3, 5])
        relaunched.disarm()
        #expect(relaunched.notArmedChannels.isEmpty)
    }

    @Test("It can't be changed during a Take, or with nothing Armed")
    func lockedDuringATake() async throws {
        let recorder = recorder(defaults())
        #expect(!recorder.setNotArmedChannels([2]))
        let audio = FakeAudioDevice(inputChannelCount: 4)
        try recorder.arm(audio)
        try recorder.startTake()
        #expect(!recorder.setNotArmedChannels([2]) && recorder.notArmedChannels.isEmpty)
        audio.deliver((0..<4).map { _ in Array(repeating: 0.2, count: 480) })
        try await recorder.stopTake()
        #expect(recorder.setNotArmedChannels([2]))
    }

    @Test("Where it isn't offered, nothing is saved and every channel stays armed")
    func hidden() throws {
        let store = defaults()
        let hidden = recorder(store, available: false)
        try hidden.arm(FakeAudioDevice(inputChannelCount: 4))
        #expect(!hidden.setNotArmedChannels([2]) && hidden.notArmedChannels.isEmpty)
        // A choice saved where it was offered is kept but not applied.
        ChannelArming.save([2], on: "Fake Device", to: store)
        try hidden.arm(FakeAudioDevice(inputChannelCount: 4))
        #expect(hidden.notArmedChannels.isEmpty)
        let offered = recorder(store)
        try offered.arm(FakeAudioDevice(inputChannelCount: 4))
        #expect(offered.notArmedChannels == [2])
    }

    @Test("A Take records only the armed channels, with their numbers and names, in both Copies, in Repair, the report and the Reaper project")
    func takeWritesOnlyArmed() async throws {
        let drive = root.appending(path: "Drive")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let device = root.appending(path: "Device")
        let available = DriveSwitch()
        let recorder = Recorder(
            deviceFolder: device, driveFolder: { available.folder.map { DriveAccess(folder: $0) } }, now: { RecordingTakeTests.showDay },
            savedNames: defaults(), destinationCheckInterval: nil, channelArmingAvailable: { true })
        let audio = FakeAudioDevice(inputChannelCount: 8)
        try recorder.arm(audio)
        recorder.setChannelName("Keys", forChannel: 7)
        #expect(recorder.setNotArmedChannels([3, 5]))
        let pro = License(proOffered: true, tier: .pro, trialStarted: false)
        let allowance = pro.allowance(channelCount: recorder.usbChannelCount, notArmed: recorder.notArmedChannels)

        try recorder.startTake(allowance: allowance)
        audio.deliver((0..<8).map { _ in Array(repeating: 0.2, count: 480) })
        // The Drive joins late, so Repair has to fill it from the Device.
        available.folder = drive
        await recorder.checkDestinations()
        audio.deliver((0..<8).map { _ in Array(repeating: 0.2, count: 480) })
        try await recorder.stopTake()
        await recorder.waitForRepair()

        let expected = ["01 USB 01.wav", "02 USB 02.wav", "04 USB 04.wav", "06 USB 06.wav", "07 Keys.wav", "08 USB 08.wav"]
        var contents: [[String: Data]] = []
        for parent in [device, drive] {
            let take = parent.appending(path: "2026-10-06 Show/Take 01")
            let files = try FileManager.default.contentsOfDirectory(atPath: take.path).filter { $0.hasSuffix(".wav") }.sorted()
            #expect(files == expected, "\(parent.lastPathComponent)")
            contents.append(Dictionary(uniqueKeysWithValues: try files.map { ($0, try Data(contentsOf: take.appending(path: $0))) }))
        }
        #expect(contents[0] == contents[1], "Repair leaves the Drive's Stems the same as the Device's")
        #expect(recorder.copies[.drive] == .repaired)
        #expect(recorder.lastTakeSignal?.recorded == 6)

        for parent in [device, drive] {
            let report = try ShowReport(showFolder: parent.appending(path: "2026-10-06 Show"))
            #expect(report.takes.first?.usbChannels.map(\.usbChannel) == [1, 2, 4, 6, 7, 8], "\(parent.lastPathComponent)")
            // The Reaper project has a track per recorded channel, in USB Channel order: the gaps are skipped.
            let project = try String(contentsOf: parent.appending(path: "2026-10-06 Show/2026-10-06 Show.RPP"), encoding: .utf8)
            #expect(project.components(separatedBy: "<TRACK").count - 1 == 6, "\(parent.lastPathComponent)")
            #expect(project.contains("07 Keys.wav") && !project.contains("03 USB 03.wav") && !project.contains("05 USB 05.wav"))
        }
    }

    @Test("With no channel armed, a press records nothing and starts nothing")
    func noneArmed() async throws {
        let recorder = recorder(defaults())
        let audio = FakeAudioDevice(inputChannelCount: 3)
        try recorder.arm(audio)
        #expect(recorder.setNotArmedChannels([1, 2, 3]))
        let allowance = License(proOffered: true, tier: .pro, trialStarted: false).allowance(channelCount: 3, notArmed: recorder.notArmedChannels)
        #expect(throws: RecorderError.noChannelsArmed) { try recorder.startTake(allowance: allowance) }
        await #expect(throws: RecorderError.noChannelsArmed) { try await recorder.startTakeOffMain(allowance: allowance) }
        #expect(!recorder.isRecording && recorder.currentShow == nil)
    }

    @Test("A replacement for the same interface keeps the choice; another interface's own choice comes with it")
    func restartInputReloads() async throws {
        let store = defaults()
        ChannelArming.save([2], on: "Backup", to: store)
        let recorder = recorder(store)
        try recorder.arm(FakeAudioDevice(name: "Main", inputChannelCount: 4))
        #expect(recorder.setNotArmedChannels([1, 3]))
        #expect(try await recorder.restartInput(on: FakeAudioDevice(name: "Main", inputChannelCount: 4)))
        #expect(recorder.notArmedChannels == [1, 3])
        #expect(try await recorder.restartInput(on: FakeAudioDevice(name: "Backup", inputChannelCount: 4)))
        #expect(recorder.notArmedChannels == [2])
    }
}
