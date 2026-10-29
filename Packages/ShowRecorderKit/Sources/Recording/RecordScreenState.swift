import Destinations
import Foundation
import MixerLink
import TakeFile
import WatchRemote

/// The plain facts the record screen decides from (#552): the App reads the Recorder, the sequencer, the Drive, the
/// Mixer Link, power and the License, and fills this in. No object from any of them goes in, so a test can build any
/// second of a show.
public struct RecordScreenSnapshot: Equatable, Sendable {
    // The input
    public var isReady = false
    public var isRecording = false
    /// A Take is running or starting, or its Stems are still being written.
    public var takeBusy = false
    public var isRepairing = false
    public var micDenied = false
    public var getReadyError: String?
    public var stoodDownForIdle = false
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

    // The status strip, the header and the watch
    public var usbChannelCount = 0
    /// Free space on the Device (the part the Take writes to).
    public var deviceAvailableBytes: Int64 = 1 << 40
    public var driveStatus = DriveStatus.notChosen
    public var mixerState: MixerLinkState?
    /// The Mixer Link was up and has gone down (the watch's "Mixer Link lost").
    public var mixerDown = false
    public var sampleRate = 48_000
    public var recordTo = RecordTo.both
    /// Whether a Take pressed now would also go to the Drive (the License, #705).
    public var driveAllowed = true
    public var readyDeviceName: String?
    public var showName: String?
    public var takeStartedAt: Date?
    public var markerCount = 0
    /// Clipped meters, by index from 0.
    public var clippedChannels: Set<Int> = []

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
    /// What the screen showed at the last announcement check, for VoiceOver.
    private var announced: ScreenAnnouncements.State?

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

    /// Tells VoiceOver about a new alert, clip or Dropout, once, when it happens (#249). Checked about once a second.
    public mutating func announcements(_ s: RecordScreenSnapshot) -> [String] {
        let now = ScreenAnnouncements.State(clipped: s.clippedChannels, alerts: alerts(s).ordered, dropoutCount: s.dropoutCount)
        defer { announced = now }
        return ScreenAnnouncements.changes(from: announced, to: now)
    }

    /// The status strip: Device and Drive time left, and the Mixer Link.
    public func chips(_ s: RecordScreenSnapshot) -> [StatusChip] {
        StatusChip.make(
            usbChannelCount: s.usbChannelCount, deviceAvailableBytes: s.deviceAvailableBytes, drive: s.driveStatus,
            mixer: s.mixerState, copies: s.copies, sampleRate: s.sampleRate, recordTo: s.recordTo, driveAllowed: s.driveAllowed)
    }

    /// What the Apple Watch shows (#100): its state and the problems that need attention. The Live Activity shows the same problems.
    public func watchStatus(_ s: RecordScreenSnapshot, now: Date = .now) -> WatchStatus {
        let take = s.isRecording ? s.takeStartedAt.map {
            WatchStatusMaker.Take(startedAt: $0, title: takeTitle(s), markerCount: s.markerCount)
        } : nil
        let driveAvailable = if case .available = s.driveStatus { true } else { false }
        return WatchStatusMaker.make(
            isReady: s.isReady, take: take, chips: chips(s), driveAvailable: driveAvailable, copies: s.copies,
            dropoutCount: s.isRecording ? s.dropoutCount : 0, mixerDown: s.mixerDown, now: now)
    }

    /// Just the Ready device's name, for the one-line landscape header.
    public func compactInputSummary(_ s: RecordScreenSnapshot) -> String {
        s.isReady ? (s.readyDeviceName ?? "Audio interface") : "No audio interface"
    }

    /// The Ready device's name and channel count, for the header.
    public func inputSummary(_ s: RecordScreenSnapshot) -> String {
        guard s.isReady else { return recordBlock(s)?.text ?? "Choose the Mixer's audio interface in Settings" }
        let name = s.readyDeviceName ?? "Audio interface"
        return "\(name) · \(Self.usbChannelSummary(s.usbChannelCount))"
    }

    /// "1 USB Channel" or "18 USB Channels".
    public static func usbChannelSummary(_ count: Int) -> String {
        count == 1 ? "1 USB Channel" : "\(count) USB Channels"
    }

    /// The running (or last) Take's number in the Show.
    public func takeTitle(_ s: RecordScreenSnapshot) -> String {
        TakeMetadata.name(take: s.takeNumber)
    }

    /// "2026-10-06 Show · Take 02", or a hint before the first Take.
    public func showSummary(_ s: RecordScreenSnapshot) -> String {
        guard let show = s.showName else { return "Press record to start a Show" }
        return "\(show) · \(takeTitle(s))"
    }

    /// Why Record is dimmed, when it is, and what to offer.
    public func recordBlock(_ s: RecordScreenSnapshot) -> RecordAvailability.Block? {
        RecordAvailability.block(
            isReady: s.isReady, isRecording: s.isRecording, micDenied: s.micDenied,
            getReadyFailed: s.getReadyError != nil && !s.micDenied, stoodDownForIdle: s.stoodDownForIdle, hasInputs: s.hasInputs)
    }

    /// How each Copy of the last Take stands, shown once recording has stopped.
    public func copySummary(_ s: RecordScreenSnapshot) -> (text: String, isProblem: Bool)? {
        if s.takeBusy { return nil }
        if s.isRepairing { return ("Repairing Gaps from the other Copy…", false) }
        guard let summary = CopySummary.ofLastTake(s.recorderCopies, dropoutCount: s.dropoutCount) else { return nil }
        return (summary.text, summary.isProblem)
    }

    /// Every alert the screen could show, in the order the App raised them: the queue sorts by priority and keeps this order within one.
    private func raised(_ s: RecordScreenSnapshot) -> [ScreenAlert] {
        var list: [ScreenAlert] = []
        if let error = s.getReadyError {
            list.append(ScreenAlert(id: "getReady", priority: .cannotRecord, tone: .critical, text: error, action: s.micDenied ? .openSystemSettings : .getReady))
        } else if s.stoodDownForIdle, let block = recordBlock(s) {
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
