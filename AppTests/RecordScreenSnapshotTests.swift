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
        #expect(!s.isArmed && !s.isRecording && !s.takeBusy && !s.isRepairing)
        #expect(s.armedDeviceName == nil)
        #expect(s.armError == nil && s.recordError == nil)
        #expect(s.sampleRate == 48_000)
    }

    @Test func armErrorComesFromTheSequencer() {
        let model = RecordScreenModel()
        model.sequencer.armError = "No input"
        #expect(model.snapshot.armError == "No input")
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

    @Test func watchStartBeforeArmingSaysOpenThePhone() {
        let model = RecordScreenModel()
        #expect(model.watchActions.start() == WatchRemoteModel.openPhoneText)
    }

    @Test func watchStopAndMarkerWhileIdleDoNothing() {
        let model = RecordScreenModel()
        #expect(model.watchActions.stop() == false)
        #expect(model.watchActions.marker() == WatchCommandDesk.notRecording)
    }
}
