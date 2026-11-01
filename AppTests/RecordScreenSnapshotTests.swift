import AudioIO
import Foundation
import Recording
import Testing
import WatchRemote
@testable import ShowRecorder

/// The App code that fills `RecordScreenSnapshot` (#552, #679): each field comes from the right Recorder, sequencer, Drive,
/// Mixer, power or License fact. The Kit side is tested in `RecordScreenStateTests`. Only facts a test can set without an
/// audio device or a Drive are driven here; the rest are read back from the object they come from.
@MainActor
@Suite(.serialized)
struct RecordScreenSnapshotTests {
    /// A model reads the device's own saved settings, so a test that changes one puts it back.
    func restoring<T>(_ key: String, _ body: () -> T) -> T {
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        return body()
    }

    @Test func freshModelReadsAsIdle() {
        let s = RecordScreenModel().snapshot
        #expect(!s.isReady && !s.isRecording && !s.takeBusy && !s.isRepairing)
        #expect(s.readyDeviceName == nil)
        #expect(s.getReadyError == nil && s.recordError == nil)
        #expect(s.sampleRate == 48_000)
    }

    @Test func getReadyErrorComesFromTheSequencer() {
        let model = RecordScreenModel()
        model.sequencer.getReadyError = "No input"
        #expect(model.snapshot.getReadyError == "No input")
    }

    @Test func hasInputsFollowsTheDevices() {
        let model = RecordScreenModel()
        model.devices = []
        #expect(!model.snapshot.hasInputs)
        model.devices = [DeviceChoice(info: .init(id: "x", name: "X", inputChannelCount: 2, sampleRate: 48_000), name: "X") { _, _ in throw CancellationError() }]
        #expect(model.snapshot.hasInputs)
    }

    @Test func recordToComesFromTheRecorder() {
        let model = RecordScreenModel()
        model.recorder.recordTo = .device
        #expect(model.snapshot.recordTo == .device)
    }

    @Test func driveFactsComeFromTheDriveModel() {
        let model = RecordScreenModel()
        let s = model.snapshot
        #expect(s.driveStatus == model.drive.status)
        #expect(s.driveChosen == (model.drive.status != .notChosen))
        #expect(s.deviceAvailableBytes == model.drive.deviceAvailableBytes)
        // Not the snapshot's own default, so an unwired field fails.
        #expect(s.deviceAvailableBytes != RecordScreenSnapshot().deviceAvailableBytes)
    }

    @Test func mixerAddressSetsHasMixerAddress() {
        restoring("mixerAddress") {
            let model = RecordScreenModel()
            model.mixerAddress = ""
            #expect(!model.snapshot.hasMixerAddress)
            model.mixerAddress = "192.168.1.146"
            #expect(model.snapshot.hasMixerAddress)
        }
    }

    @Test func soundcheckOfferedComesFromTheModel() {
        restoring("soundcheckOffered") {
            let model = RecordScreenModel()
            model.soundcheckOffered = false
            #expect(!model.snapshot.soundcheckOffered)
            model.soundcheckOffered = true
            #expect(model.snapshot.soundcheckOffered)
        }
    }

    @Test func dismissingTheHintReachesTheSnapshot() {
        restoring("setupHintDismissed") {
            let model = RecordScreenModel()
            model.perform(.dismissHint)
            #expect(model.snapshot.setupHintDismissed)
        }
    }

    // The glue that stays in the App: alert actions that open sheets, and the watch's three commands.

    @Test func alertActionsOpenTheirSheets() {
        let model = RecordScreenModel()
        model.perform(.showMoves)
        #expect(model.showingMoves)
        model.perform(.soundcheck)
        #expect(model.showingSoundcheck)
    }

    @Test func watchStartBeforeGettingReadySaysOpenThePhone() {
        let model = RecordScreenModel()
        #expect(model.watchActions.start() == WatchRemoteModel.openPhoneText)
    }

    @Test func watchStopAndMarkerWhileIdleDoNothing() {
        let model = RecordScreenModel()
        #expect(model.watchActions.stop() == false)
        #expect(model.watchActions.marker() == WatchCommandDesk.notRecording)
    }

    // MARK: - Which USB Channels are armed (#991)

    /// A store that owns Pro, or owns nothing (Free once the App Store has answered), and never asks the App Store.
    func store(owningPro: Bool) -> ProStore {
        ProStore(status: ProStatus(lastKnown: ProPurchases(owned: owningPro ? [OwnedPurchase(productID: ProPurchases.proProductID, purchaseDate: Date())] : [])))
    }

    @Test func notArmedChannelsReachTheLanesCountAndTemplates() {
        restoring("notArmedChannels") { restoring("templates") {
            let model = RecordScreenModel(pro: store(owningPro: true))
            try? model.recorder.getReady(FakeAudioDevice(name: "ChannelArmingTest", inputChannelCount: 18))
            defer { model.recorder.standDown() }
            #expect(model.notArmedLanes.isEmpty && model.recordedChannelCount == 18 && !model.noChannelArmed)
            #expect(model.offersChannelArming)

            model.setChannelArmed(3, false)
            model.setChannelArmed(5, false)
            #expect(model.notArmedLanes == [3, 5] && model.recordedChannelCount == 16)
            #expect(model.currentAllowance()?.recordedChannels == Set(1...18).subtracting([3, 5]))
            model.setChannelArmed(5, true)
            #expect(model.notArmedLanes == [3] && model.recordedChannelCount == 17)

            model.saveTemplate(named: "Armed test")
            #expect(model.templates.templates.first { $0.name == "Armed test" }?.notArmedChannels == [3])
        } }
    }

    @Test func noChannelArmedBlocksRecordAndSaysSo() {
        restoring("notArmedChannels") {
            let model = RecordScreenModel(pro: store(owningPro: true))
            try? model.recorder.getReady(FakeAudioDevice(name: "ChannelArmingTest", inputChannelCount: 2))
            defer { model.recorder.standDown() }
            model.setChannelArmed(1, false)
            #expect(!model.noChannelArmed)
            model.setChannelArmed(2, false)
            #expect(model.noChannelArmed && model.snapshot.recordedChannelCount == 0)
            #expect(model.screen.inputSummary(model.snapshot).hasSuffix("No USB Channel is armed. Arm one to record."))
            model.record()
            #expect(!model.startRequested && !model.recorder.isRecording)
        }
    }

    @Test func freeKeepsTheChoiceButRecordsEveryChannel() {
        restoring("notArmedChannels") {
            let model = RecordScreenModel(pro: store(owningPro: false))
            try? model.recorder.getReady(FakeAudioDevice(name: "ChannelArmingTest", inputChannelCount: 4))
            defer { model.recorder.standDown() }
            // Free is offered no menu; a choice saved before (as Pro, or a Trial) is kept but not applied.
            #expect(!model.offersChannelArming)
            model.recorder.setNotArmedChannels([2])
            #expect(model.recorder.notArmedChannels == [2])
            #expect(model.notArmedLanes.isEmpty && model.recordedChannelCount == 4 && !model.noChannelArmed)
            #expect(model.currentAllowance()?.recordedChannels == Set(1...4))
        }
    }

    @Test func aLaterTemplateWithoutAChoiceDropsTheWaitingOne() {
        restoring("notArmedChannels") {
            let model = RecordScreenModel(pro: store(owningPro: true))
            func template(_ notArmed: Set<Int>?) -> Template {
                Template(name: "T", venue: nil, channelNames: [:], mixerNetworkName: nil, mixerAddress: "", preRollSeconds: 0, notArmedChannels: notArmed)
            }
            // No Audio interface is Ready yet: Template A's choice waits, and Template B (none) takes it back.
            model.applyArming(from: template([2, 3]))
            model.applyArming(from: template(nil))
            try? model.recorder.getReady(FakeAudioDevice(name: "TemplatePendingTest", inputChannelCount: 4))
            defer { model.recorder.standDown() }
            #expect(model.recorder.notArmedChannels.isEmpty && model.recordedChannelCount == 4)
        }
    }
}
