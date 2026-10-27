import Foundation
@testable import Recording
import TakeFile
import Testing

/// What the record screen says and remembers, second by second (#552). The alert order is the App's old `raisedAlerts`.
@Suite("Record screen state")
struct RecordScreenStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func ids(_ state: RecordScreenState, _ snapshot: RecordScreenSnapshot) -> [String] {
        state.alerts(snapshot).ordered.map(\.id)
    }

    private func repatch(_ channel: Int = 3) -> TakeMetadata.RoutingChange {
        TakeMetadata.RoutingChange(position: 12, usbChannel: channel, from: "Kick", to: "Snare")
    }

    private var recording: RecordScreenSnapshot {
        var s = RecordScreenSnapshot()
        s.isArmed = true
        s.isRecording = true
        s.takeBusy = true
        s.hasInputs = true
        s.copies = takeCopies(device: .recording, drive: .recording)
        return s
    }

    private var idle: RecordScreenSnapshot {
        var s = RecordScreenSnapshot()
        s.isArmed = true
        s.hasInputs = true
        s.driveChosen = true
        s.soundcheckOffered = true
        return s
    }

    @Test("A quiet screen says nothing")
    func quiet() {
        #expect(ids(RecordScreenState(), idle).isEmpty)
        #expect(ids(RecordScreenState(), recording).isEmpty)
    }

    @Test("During a Take every alert comes in its priority, and within one priority in the order the App raised them")
    func orderDuringATake() {
        var s = recording
        s.armError = "The input stopped."
        s.recordError = "The Take stopped."
        s.copies = takeCopies(device: .recording, drive: .interrupted)
        s.usbChannelShortfall = "Only 8 of 18 channels."
        s.interruptionNotice = "A call interrupted the input."
        s.noSignalSilent = true
        s.takeNumber = 2
        s.routingChanges = [repatch()]
        s.routingNotice = "Kick is now Snare."
        s.power = PowerStatus(batteryLevel: 0.05, charging: .unplugged, thermal: .nominal)
        let power = s.power.alerts.map(\.id)

        #expect(ids(RecordScreenState(), s) ==
            ["arm", "record", "drive-stopped"] + power + ["shortfall", "interruption", "noSignal", "routing"])
    }

    @Test("Between Takes the Copy summary and the move report follow the input alerts, then the hints")
    func orderBetweenTakes() {
        var s = idle
        s.armError = "The input didn't start."
        s.usbChannelShortfall = "Only 8 of 18 channels."
        s.interruptionNotice = "A call interrupted the input."
        s.recorderCopies = takeCopies(running: false, device: .complete, drive: .complete)
        s.movesDriveOnlyTakes = true
        s.moveReport = MoveReport(isMoving: true, moves: [], skips: [])
        s.power = PowerStatus(batteryLevel: 0.05, charging: .unplugged, thermal: .nominal)
        let power = s.power.alerts.map(\.id)

        #expect(ids(RecordScreenState(), s) == ["arm"] + power + ["shortfall", "interruption", "copies", "moves"])
    }

    @Test("The setup hint comes before the Soundcheck offer, and the offer waits while the hint shows")
    func hints() {
        var s = idle
        s.driveChosen = false
        s.soundcheckOffered = false
        #expect(ids(RecordScreenState(), s) == ["hint"])
        s.setupHintDismissed = true
        #expect(ids(RecordScreenState(), s) == ["soundcheck"])
        s.soundcheckOffered = true
        #expect(ids(RecordScreenState(), s).isEmpty)
        s.setupHintDismissed = false
        s.hasMixerAddress = true
        #expect(ids(RecordScreenState(), s).isEmpty)
    }

    @Test("The hint names the Mixer only where Mixer Link is offered")
    func hintWording() throws {
        var s = idle
        s.driveChosen = false
        s.soundcheckOffered = true
        let plain = try #require(RecordScreenState().alerts(s).top)
        #expect(plain.text == "Choose the audio interface and Drive in Settings (the gear).")
        #expect(plain.action == .dismissHint)
        s.offersMixerLink = true
        let withMixer = try #require(RecordScreenState().alerts(s).top)
        #expect(withMixer.text == "Choose the audio interface, Drive and Mixer in Settings (the gear).")
    }

    @Test("An arm failure with the microphone denied is critical and opens the system settings")
    func micDenied() throws {
        var s = idle
        s.isArmed = false
        s.micDenied = true
        s.armError = "Microphone access is off."
        let alert = try #require(RecordScreenState().alerts(s).top)
        #expect(alert.id == "arm")
        #expect(alert.priority == .cannotRecord)
        #expect(alert.tone == .critical)
        #expect(alert.text == "Microphone access is off.")
        #expect(alert.action == .openSystemSettings)

        s.micDenied = false
        #expect(try #require(RecordScreenState().alerts(s).top).action == .arm)
    }

    @Test("Disarmed for being idle is a warning with the block's text and its Arm button, unless an arm error speaks")
    func disarmedForIdle() throws {
        var s = idle
        s.isArmed = false
        s.disarmedForIdle = true
        let alert = try #require(RecordScreenState().alerts(s).top)
        #expect(alert.id == "idle")
        #expect(alert.tone == .warning)
        #expect(alert.text == "Disarmed after 30 minutes idle.")
        #expect(alert.action == .arm)

        s.armError = "The input didn't start."
        #expect(ids(RecordScreenState(), s) == ["arm"])
    }

    @Test("No signal is not raised while an interruption has stopped the input, whose notice says why")
    func noSignalWaitsForInterruption() {
        var s = recording
        s.noSignalSilent = true
        s.interruptionNotice = "A call interrupted the input."
        s.isInputStopped = true
        #expect(ids(RecordScreenState(), s) == ["interruption"])
        s.isInputStopped = false
        #expect(ids(RecordScreenState(), s) == ["interruption", "noSignal"])
    }

    @Test("A swiped warning stays away until its problem clears, then shows again when it comes back")
    func raisedSwipedClearedRaised() throws {
        var state = RecordScreenState()
        var s = idle
        s.interruptionNotice = "A call interrupted the input."
        state.update(s, at: t0)
        let alert = try #require(state.alerts(s).top)

        state.swipe(alert)
        #expect(ids(state, s).isEmpty)
        state.update(s, at: t0 + 1)
        #expect(ids(state, s).isEmpty)

        s.interruptionNotice = nil
        state.update(s, at: t0 + 2)
        s.interruptionNotice = "A call interrupted the input."
        #expect(ids(state, s) == ["interruption"])
    }

    @Test("A critical alert cannot be swiped away")
    func criticalStays() throws {
        var state = RecordScreenState()
        var s = recording
        s.copies = takeCopies(device: .recording, drive: .interrupted)
        let alert = try #require(state.alerts(s).top)
        state.swipe(alert)
        #expect(ids(state, s) == ["drive-stopped"])
    }

    @Test("A swiped warning shows again when its message changes")
    func swipedMessageChanges() throws {
        var state = RecordScreenState()
        var s = idle
        s.interruptionNotice = "A call interrupted the input."
        state.swipe(try #require(state.alerts(s).top))
        s.interruptionNotice = "Another app took the input."
        #expect(ids(state, s) == ["interruption"])
    }

    @Test("The Drive dropping and rejoining during a Take: critical, then a green banner that fades after 10 s on screen")
    func driveDropsAndRejoins() throws {
        var state = RecordScreenState()
        var s = recording
        state.update(s, at: t0)
        #expect(ids(state, s).isEmpty)

        s.copies = takeCopies(device: .recording, drive: .interrupted)
        state.update(s, at: t0 + 1)
        #expect(ids(state, s) == ["drive-stopped"])

        s.copies = takeCopies(device: .recording, drive: .recording)
        state.update(s, at: t0 + 2)
        let back = try #require(state.alerts(s).top)
        #expect(back.id == "drive-back")
        #expect(back.tone == .ok)

        state.update(s, at: t0 + 11)
        #expect(ids(state, s) == ["drive-back"])
        state.update(s, at: t0 + 12.5)
        #expect(ids(state, s).isEmpty)
    }

    @Test("A green banner does not fade while the app is off screen, and gets its 10 s once back")
    func fadeWaitsForScreen() {
        var state = RecordScreenState()
        var s = recording
        s.copies = takeCopies(device: .recording, drive: .interrupted)
        state.update(s, at: t0)
        s.copies = takeCopies(device: .recording, drive: .recording)
        state.update(s, at: t0 + 1)
        #expect(ids(state, s) == ["drive-back"])

        state.setOnScreen(false)
        state.update(s, at: t0 + 60)
        #expect(ids(state, s) == ["drive-back"])

        state.setOnScreen(true)
        state.update(s, at: t0 + 61)
        state.update(s, at: t0 + 70)
        #expect(ids(state, s) == ["drive-back"])
        state.update(s, at: t0 + 72)
        #expect(ids(state, s).isEmpty)
    }

    @Test("The rejoin banner goes when the Take ends")
    func rejoinEndsWithTake() {
        var state = RecordScreenState()
        var s = recording
        s.copies = takeCopies(device: .recording, drive: .interrupted)
        state.update(s, at: t0)
        s.copies = takeCopies(device: .recording, drive: .recording)
        state.update(s, at: t0 + 1)
        s.copies = takeCopies(running: false, device: .complete, drive: .complete)
        state.update(s, at: t0 + 2)
        #expect(!ids(state, s).contains("drive-back"))
    }

    @Test("A re-patch warns until the operator has seen it; a second re-patch, or the next Take's, warns again")
    func rePatchSeen() {
        var state = RecordScreenState()
        var s = recording
        s.takeNumber = 4
        s.routingChanges = [repatch()]
        s.routingNotice = "Kick is now Snare."
        #expect(ids(state, s) == ["routing"])
        #expect(state.alerts(s).top?.action == .dismissRoutingChange)

        state.dismissRoutingChange(s)
        #expect(ids(state, s).isEmpty)

        s.routingChanges = [repatch(), repatch(5)]
        s.routingNotice = "Kick is now Snare. Tom is now Snare."
        #expect(ids(state, s) == ["routing"])

        state.dismissRoutingChange(s)
        #expect(ids(state, s).isEmpty)

        s.takeNumber = 5
        s.routingChanges = [repatch(5), repatch(6)]
        #expect(ids(state, s) == ["routing"])
    }

    @Test("A re-patch is only a warning during a Take")
    func rePatchOnlyWhileRecording() {
        var s = idle
        s.routingChanges = [repatch()]
        s.routingNotice = "Kick is now Snare."
        #expect(ids(RecordScreenState(), s).isEmpty)
    }

    @Test("Check Drive finding nothing is told until the Drive comes back")
    func checkDriveFoundNothing() throws {
        var state = RecordScreenState()
        var s = recording
        s.copies = takeCopies(device: .recording, drive: .interrupted)
        let before = try #require(state.alerts(s).top)
        #expect(before.action == .checkDrive)

        state.checkedDrive(copies: s.copies)
        let after = try #require(state.alerts(s).top)
        #expect(after.text != before.text)
        #expect(after.id == before.id)

        s.copies = takeCopies(device: .recording, drive: .recording)
        state.update(s, at: t0)
        s.copies = takeCopies(device: .recording, drive: .interrupted)
        #expect(state.alerts(s).top?.text == before.text)
    }

    @Test("A Drive Check that finds the Drive says nothing more than the plain alert")
    func checkDriveFound() throws {
        var state = RecordScreenState()
        var s = recording
        s.copies = takeCopies(device: .recording, drive: .recording)
        state.checkedDrive(copies: s.copies)
        s.copies = takeCopies(device: .recording, drive: .interrupted)
        let plain = try #require(RecordScreenState().alerts(s).top)
        #expect(state.alerts(s).top == plain)
    }

    @Test("The last Take's Copy summary shows between Takes, and a Repair in progress shows instead while one runs")
    func copySummary() throws {
        var s = idle
        s.recorderCopies = takeCopies(running: false, device: .complete, drive: .complete)
        let done = try #require(RecordScreenState().alerts(s).top)
        #expect(done.id == "copies")
        #expect(done.priority == .copyResult)

        s.isRepairing = true
        let repairing = try #require(RecordScreenState().alerts(s).top)
        #expect(repairing.text == "Repairing Gaps from the other Copy…")
        #expect(repairing.tone == .ok)

        s.takeBusy = true
        #expect(ids(RecordScreenState(), s).isEmpty)
    }
}
