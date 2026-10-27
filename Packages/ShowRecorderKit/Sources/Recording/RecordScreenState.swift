import Foundation
import TakeFile

/// The plain facts the record screen decides from (#552): the App reads the Recorder, the sequencer, the Drive, the
/// Mixer Link, power and the License, and fills this in. No object from any of them goes in, so a test can build any
/// second of a show.
public struct RecordScreenSnapshot: Equatable, Sendable {
    // The input
    public var isArmed = false
    public var isRecording = false
    /// A Take is running or starting, or its Stems are still being written.
    public var takeBusy = false
    public var isRepairing = false
    public var micDenied = false
    public var armError: String?
    public var disarmedForIdle = false
    public var hasInputs = false
    public var recordError: String?
    /// A real reason some USB Channels won't be recorded, as the alert says it.
    public var usbChannelShortfall: String?
    public var interruptionNotice: String?
    public var isInputStopped = false
    public var noSignalSilent = false

    // The Take and its Copies
    /// The Copies as the screen last refreshed them.
    public var copies = TakeCopies.none
    /// The Recorder's own Copies: the last Take's, for the Copy summary.
    public var recorderCopies = TakeCopies.none
    public var dropoutCount = 0
    public var driveNotice: String?
    public var driveCopyAllowed = true
    public var takeNumber = 0
    public var routingChanges: [TakeMetadata.RoutingChange] = []
    public var routingNotice: String?
    public var movesDriveOnlyTakes = false
    public var moveReport = MoveReport(isMoving: false, moves: [], skips: [])

    // The device
    public var power = PowerStatus(batteryLevel: nil, charging: .unknown, thermal: .nominal)

    // First launch
    public var setupHintDismissed = false
    public var driveChosen = false
    public var hasMixerAddress = false
    public var offersMixerLink = false
    public var soundcheckOffered = false

    public init() {}
}

/// What the record screen says, and what it remembers between seconds (#552): the alerts swiped away, a green banner's
/// 10 s fade, the Drive-rejoined notice, "Check Drive found nothing", and the re-patch the operator has already seen.
/// The App holds one, calls `update` about once a second, and reads `alerts` from a snapshot of the moment.
public struct RecordScreenState: Equatable, Sendable {
    private var swiped = SwipedAlerts()
    private var driveRejoin = DriveRejoinNotice()
    /// The Drive stopped and Check Drive found nothing, until it comes back.
    private var driveCheckedAndNotFound = false
    /// The routing changes the operator dismissed the warning at, in which Take: a later re-patch, or the next Take's, warns again.
    private var routingChangeSeen: Seen?
    /// Whether the app is in front; a green banner's 10 s count only then (#758).
    private var isOnScreen = true

    private struct Seen: Equatable, Sendable {
        var take: Int
        var changes: [TakeMetadata.RoutingChange]
    }

    public init() {}

    /// Everything the record screen has to say, most urgent first, but the warnings and green summaries swiped away
    /// (#644, #698); it shows one and counts the rest.
    public func alerts(_ snapshot: RecordScreenSnapshot) -> AlertQueue {
        AlertQueue(swiped.showing(raised(snapshot)))
    }

    /// Checked about once a second, in this order: the Drive's coming and going, a swiped warning whose problem has
    /// cleared (it shows again if it comes back), then the green banner on top fading after 10 s on screen (#758).
    public mutating func update(_ snapshot: RecordScreenSnapshot, at now: Date) {
        driveRejoin.update(copies: snapshot.copies)
        if snapshot.copies[.drive] != .interrupted { driveCheckedAndNotFound = false }
        let list = raised(snapshot)
        var next = swiped
        next.forget(absentFrom: list)
        if isOnScreen { _ = next.fade(list, at: now) }
        if next != swiped { swiped = next }
    }

    public mutating func swipe(_ alert: ScreenAlert) { swiped.swipe(alert) }

    /// The operator looked for the Drive again: it stays "not found" until the Drive comes back.
    public mutating func checkedDrive(copies: TakeCopies) {
        driveCheckedAndNotFound = copies[.drive] == .interrupted
    }

    /// The operator has seen the re-patches so far in this Take.
    public mutating func dismissRoutingChange(_ snapshot: RecordScreenSnapshot) {
        routingChangeSeen = Seen(take: snapshot.takeNumber, changes: snapshot.routingChanges)
    }

    /// Leaving the screen pauses a green banner's fade, so it gets its 10 s once back (#758).
    public mutating func setOnScreen(_ onScreen: Bool) {
        guard onScreen != isOnScreen else { return }
        isOnScreen = onScreen
        if !onScreen { swiped.pauseFade() }
    }

    /// Why Record is dimmed, when it is, and what to offer.
    private func block(_ s: RecordScreenSnapshot) -> RecordAvailability.Block? {
        RecordAvailability.block(
            isArmed: s.isArmed, isRecording: s.isRecording, micDenied: s.micDenied,
            armFailed: s.armError != nil && !s.micDenied, disarmedForIdle: s.disarmedForIdle, hasInputs: s.hasInputs)
    }

    /// How each Copy of the last Take stands, shown once recording has stopped.
    private func copySummary(_ s: RecordScreenSnapshot) -> (text: String, isProblem: Bool)? {
        if s.takeBusy { return nil }
        if s.isRepairing { return ("Repairing Gaps from the other Copy…", false) }
        guard let summary = CopySummary.ofLastTake(s.recorderCopies, dropoutCount: s.dropoutCount) else { return nil }
        return (summary.text, summary.isProblem)
    }

    /// Every alert the screen could show, in the order the App raised them: the queue sorts by priority and keeps this order within one.
    private func raised(_ s: RecordScreenSnapshot) -> [ScreenAlert] {
        var list: [ScreenAlert] = []
        if let error = s.armError {
            list.append(ScreenAlert(id: "arm", priority: .cannotRecord, tone: .critical, text: error, action: s.micDenied ? .openSystemSettings : .arm))
        } else if s.disarmedForIdle, let block = block(s) {
            list.append(ScreenAlert(id: "idle", priority: .cannotRecord, tone: .warning, text: block.text, action: block.action))
        }
        if let error = s.recordError {
            list.append(ScreenAlert(id: "record", priority: .cannotRecord, tone: .critical, text: error))
        }
        if let alert = DestinationAlert.make(copies: s.copies, checkedAndNotFound: driveCheckedAndNotFound,
                                             driveNote: s.driveNotice, driveCopyAllowed: s.driveCopyAllowed) {
            list.append(alert)
        }
        if let rejoined = driveRejoin.alert { list.append(rejoined) }
        if let shortfall = s.usbChannelShortfall {
            list.append(ScreenAlert(id: "shortfall", priority: .input, tone: .warning, text: shortfall))
        }
        if let notice = s.interruptionNotice {
            list.append(ScreenAlert(id: "interruption", priority: .input, tone: .warning, text: notice))
        }
        // Not while input is stopped by an interruption: its own notice says why nothing arrives.
        if let alert = NoSignalAlert.make(isSilent: s.noSignalSilent, isRecording: s.isRecording && !s.isInputStopped) { list.append(alert) }
        // A re-patch on the Mixer during the Take (#21), until the Take ends or the operator has seen it.
        if s.isRecording, routingChangeSeen?.take != s.takeNumber || routingChangeSeen?.changes != s.routingChanges,
           let text = s.routingNotice {
            list.append(ScreenAlert(id: "routing", priority: .input, tone: .warning, text: text, action: .dismissRoutingChange))
        }
        list += s.power.alerts
        if let summary = copySummary(s), !s.isRecording {
            list.append(ScreenAlert(id: "copies", priority: .copyResult, tone: summary.isProblem ? .warning : .ok, text: summary.text))
        }
        // Drive only Takes moving to the Drive (#630), where Drive only is offered; tap for each Take and why one stays.
        if let alert = s.moveReport.alert(isOffered: s.movesDriveOnlyTakes, isRecording: s.isRecording) {
            list.append(alert)
        }
        // A first-run nudge, once: neither a Drive nor a Mixer is set up yet.
        let setupHintShowing = !s.setupHintDismissed && !s.isRecording && !s.driveChosen && !s.hasMixerAddress
        if setupHintShowing {
            list.append(ScreenAlert(id: "hint", priority: .hint, tone: .info, text: s.offersMixerLink ? "Choose the audio interface, Drive and Mixer in Settings (the gear)." : "Choose the audio interface and Drive in Settings (the gear).", action: .dismissHint))
        }
        // Offered once, as a banner rather than a sheet, so it never stacks on another first-launch sheet (#63).
        if Soundcheck.shouldOffer(alreadyOffered: s.soundcheckOffered, isRecording: s.isRecording, setupHintShowing: setupHintShowing) {
            list.append(ScreenAlert(id: "soundcheck", priority: .hint, tone: .info, text: "Check your rig with a 30 s Soundcheck.", action: .soundcheck))
        }
        return list
    }
}
