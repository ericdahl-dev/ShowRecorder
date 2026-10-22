import AudioIO
import Foundation
import MixerLink
import Observation

/// One choosable audio device.
public struct DeviceChoice: Identifiable {
    /// What the hot-plug decision sees. `info.id` is stable across unplug and replug.
    public let info: InputDeviceInfo
    /// The label shown in the picker.
    public let name: String
    /// The sample rates the input offers, for the picker (#195); empty when it can't say.
    public var availableSampleRates: [Int] = []
    /// Opens the input at `chosen` (nil: as it is), at most 48 kHz when `capAt48k`. A mixer's input keeps its rate.
    public let make: (_ chosen: Int?, _ capAt48k: Bool) throws -> any AudioIODevice

    public var id: String { info.id }

    public init(info: InputDeviceInfo, name: String, availableSampleRates: [Int] = [], make: @escaping (_ chosen: Int?, _ capAt48k: Bool) throws -> any AudioIODevice) {
        self.info = info
        self.name = name
        self.availableSampleRates = availableSampleRates
        self.make = make
    }
}

/// Where the Audio interfaces on offer come from: Core Audio on the Mac, the audio session on iOS, fakes in tests.
@MainActor
public protocol InputDeviceSource {
    func devices() -> [DeviceChoice]
    /// iOS: the input the current route provides, opened at `sampleRate` (nil: the route's own).
    func currentRouteDevice(sampleRate: Int?) throws -> any AudioIODevice
}

extension InputDeviceSource {
    public func currentRouteDevice(sampleRate: Int?) throws -> any AudioIODevice {
        throw CocoaError(.featureUnsupported)
    }
}

/// What happened to the recorder, for whoever follows Takes.
public enum TakeEvent: Equatable, Sendable {
    case armed(InputDeviceInfo)
    case takeStarted(take: Int)
    case takeEnded(TakeEnd)
    case disarmed(reason: DisarmReason)
    /// The system stopped input (an interruption, a failed restart); the Take, if any, is still running.
    case inputStopped
    /// Input is back after being stopped.
    case inputRestarted
    /// A Marker was placed in the running Take: how many it has now (#551).
    case markerPlaced(count: Int)
    /// The open Show was ended: its name and how many Takes it has (#551).
    case showEnded(name: String, takeCount: Int)

    public enum DisarmReason: Equatable, Sendable {
        /// The screen showing the recorder went away with no Take running.
        case screenGone
        /// The app sat in the background for 30 minutes with no Take (`IdleDisarm`).
        case idle
        /// The Armed Audio interface was disconnected.
        case deviceLost
    }
}

/// Takes, start to end, on the recorder: which Audio interface is Armed, record and stop.
@MainActor
@Observable
public final class TakeSequencer {
    public let recorder: Recorder
    @ObservationIgnored private let capsAt48k: () -> Bool
    @ObservationIgnored private let now: () -> Date
    /// Set once the first Arm has been tried, so a screen appearing before that doesn't Arm early.
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var idle = IdleDisarm()

    public var devices: [DeviceChoice]
    public var selectedDeviceID: String?
    /// The device as it was when last Armed, to tell a format change from a new device.
    public var armedDevice: InputDeviceInfo?
    /// The sample rate choice (#195): nil is the interface's own rate.
    public var sampleRateChoice: Int?
    /// Why the last Arm failed; nil once one works.
    public var armError: String?
    /// Why the last record or stop went wrong, or why a Take ended on its own; nil after a Take starts.
    public var recordError: String?
    /// When the running Take started, for the elapsed time.
    public private(set) var takeStartedAt: Date?
    /// Whether the recorder was disarmed for sitting idle, so coming back should Arm it again.
    public private(set) var disarmedForIdle = false
    /// What to do about audio interruptions, and the banner they leave.
    public private(set) var interruptions = InterruptionPolicy()
    @ObservationIgnored private var toldInputStopped = false
    /// Whether the running Take is the Soundcheck's, so its end says so (#551).
    @ObservationIgnored private var soundcheckTake = false

    /// Called after each attempt to Arm an interface, or to move input to a new one: with the device when it worked,
    /// nil when it failed. The App resets its meters and reads what the system offered here.
    @ObservationIgnored public var didArm: (_ device: (any AudioIODevice)?) -> Void = { _ in }
    /// A line worth logging about input (an interruption, a restart, a route change).
    @ObservationIgnored public var log: (String) -> Void = { _ in }
    /// Everything that happens, in order. One listener. With no one listening only the newest
    /// `eventBufferSize` are kept, so a stream nobody reads never grows. It ends when the sequencer goes away.
    /// Every Take start and end is told, every Arm, each input stop and restart, and a disarm when the screen goes,
    /// the app sits idle or the Armed interface is lost. Arming with no interface selected disarms without telling.
    public let events: AsyncStream<TakeEvent>
    @ObservationIgnored private let source: any InputDeviceSource
    public static let eventBufferSize = 32
    @ObservationIgnored private let emit: AsyncStream<TakeEvent>.Continuation

    public init(recorder: Recorder, devices: any InputDeviceSource, capsAt48k: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.recorder = recorder
        self.now = now
        self.capsAt48k = capsAt48k
        (events, emit) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(Self.eventBufferSize))
        source = devices
        self.devices = devices.devices()
        selectedDeviceID = self.devices.first?.id
        recorder.onTakeEnded = { [weak self] end in self?.takeEnded(end) }
    }

    deinit {
        emit.finish()
    }

    /// What to do when the operator closes the window the recorder is shown in (the Mac).
    public enum WindowCloseAction: Equatable, Sendable {
        case close
        /// A Take is running: ask whether to stop it, and close only if the answer is stop.
        case askToStop
    }

    /// The operator asked to close the window (the close button or Command-W).
    public func windowCloseRequested() -> WindowCloseAction {
        recorder.isRecording || recorder.isFinishing ? .askToStop : .close
    }

    /// What to do when the operator quits the app (the Mac).
    public enum QuitAction: Equatable, Sendable {
        case quit
        /// A Take is running: ask whether to stop it, and quit only if the answer is stop.
        case askToStop
    }

    /// The operator asked to quit (Command-Q or the Dock menu).
    public func quitRequested() -> QuitAction {
        recorder.isRecording || recorder.isFinishing ? .askToStop : .quit
    }

    /// The first Arm, once the App may use the input. Never Arms over an Armed recorder, because Arming again stops
    /// the Take.
    public func start() {
        if !recorder.isArmed { arm() }
        didStart = true
    }

    /// The screen appeared, or came back: Arm if nothing is, never over a running Take. A screen being torn down
    /// and built again (iOS discarding a scene, a window closing) never ends a Take.
    public func screenAppeared() {
        guard didStart, !recorder.isArmed else { return }
        arm()
    }

    /// The screen went away: disarm an unused recorder, never a running Take.
    public func screenDisappeared() {
        guard !recorder.isRecording else { return }
        let wasArmed = recorder.isArmed
        recorder.disarm()
        if wasArmed { emit.yield(.disarmed(reason: .screenGone)) }
    }

    /// The operator chose an interface. Skips the one already Armed (as after a device change the sequencer Armed itself).
    public func select(_ id: String?) {
        selectedDeviceID = id
        if recorder.isArmed, armedDevice?.id == id { return }
        arm()
    }

    /// Arms the selected Audio interface.
    public func arm() {
        guard let choice = devices.first(where: { $0.id == selectedDeviceID }) else {
            recorder.disarm()
            armedDevice = nil
            return
        }
        let previous = armedDevice
        do {
            armedDevice = nil
            let device = try choice.make(sampleRateChoice, capsAt48k())
            try recorder.arm(device)
            armedDevice = choice.info
            armError = nil
            emit.yield(.armed(choice.info))
            didArm(device)
        } catch RecorderError.finishing {
            // The recorder kept the device it had, so the sequencer does too.
            armedDevice = previous
            armError = "Couldn't start \(choice.name): \(RecorderError.finishing.localizedDescription)"
        } catch {
            armError = "Couldn't start \(choice.name): \(error)"
            didArm(nil)
        }
    }

    /// Starts a Take with what the Mixer Link and the tier say right now (the Show-Safe Promise: judged only here).
    /// Returns whether it started.
    @discardableResult
    public func record(sources: [Source], allowance: TakeAllowance?, soundcheck: Bool = false) -> Bool {
        // `Recorder.startTake` ignores a start in the middle of a Take, so this must too: no new start time,
        // Soundcheck flag, event or cleared error (#695).
        guard !recorder.isRecording, !recorder.isStarting else { return false }
        do {
            try recorder.startTake(sources: sources, allowance: allowance)
            return takeStarted(soundcheck: soundcheck)
        } catch {
            recordError = "Couldn't start recording: \(error.localizedDescription)"
            return false
        }
    }

    /// `record` without the main actor waiting on the Drive (#914): the Drive's folders and Stems are made on a thread of
    /// its own, and the Take starts once they are, or on the Device alone when the Drive is slower than
    /// `Recorder.defaultDriveStartDeadline`. `Recorder.isStarting` is true meanwhile; a `stop()` that comes then cancels the
    /// start. Returns whether a Take started.
    @discardableResult
    public func recordOffMain(sources: [Source], allowance: TakeAllowance?, soundcheck: Bool = false) async -> Bool {
        guard !recorder.isRecording, !recorder.isStarting else { return false }
        do {
            try await recorder.startTakeOffMain(sources: sources, allowance: allowance)
            return takeStarted(soundcheck: soundcheck)
        } catch RecorderError.startCanceled {
            return false
        } catch {
            recordError = "Couldn't start recording: \(error.localizedDescription)"
            return false
        }
    }

    /// What a started Take sets and tells.
    private func takeStarted(soundcheck: Bool) -> Bool {
        soundcheckTake = soundcheck
        takeStartedAt = now()
        recordError = nil
        emit.yield(.takeStarted(take: recorder.currentShow?.takeCount ?? 0))
        // Told at once, so the notice clears with the press; a restart (input still stopped, #877) runs after.
        let response = interruptions.handle(.takeStarted, isRecording: recorder.isRecording)
        if response.action != .none { Task { [weak self] in await self?.perform(response) } }
        tellInputState()
        return true
    }

    /// Ends the running Take.
    public func stop() async {
        // A Take that is still starting (#914) has nothing to save: Stop ends the start.
        if recorder.isStarting {
            recorder.cancelStart()
            return
        }
        // The start time stays while the Take is being saved (the screen freezes its timer on it); the end clears it.
        // Not if a later Take has started meanwhile (a second Stop that waited for the save returns after it).
        defer { if !recorder.isRecording, !recorder.isFinishing { takeStartedAt = nil } }
        do {
            try await recorder.stopTake()
        } catch {
            recordError = "The Take didn't finish cleanly: \(error.localizedDescription)"
        }
    }

    /// Places a Marker in the running Take and tells it. Does nothing with no Take running, or past the Take's
    /// Marker limit (Free, #705).
    /// - Returns: whether a Marker was placed: none without a Take, or past the Take's Marker limit (#882).
    @discardableResult
    public func addMarker(named name: String? = nil) -> Bool {
        guard recorder.isRecording, recorder.addMarker(named: name) else { return false }
        emit.yield(.markerPlaced(count: recorder.takeMarkers.count))
        return true
    }

    /// Starts a Show on purpose, ending the open one (see `Recorder.startNewShow`). Never during a Take.
    public func startNewShow(name: String, venue: String) throws {
        try endingShow { try recorder.startNewShow(name: name, venue: venue) }
    }

    /// Starts a Show from a Template, ending the open one (see `Recorder.startNewShow(from:)`). Never during a Take.
    public func startNewShow(from template: Template) throws {
        try endingShow { try recorder.startNewShow(from: template) }
    }

    /// Readies the next Show from the default Template (see `Recorder.prepareNextShow`); returns whether it did.
    @discardableResult
    public func prepareNextShow(from template: Template) -> Bool {
        // It ends a Show idle for 6 hours first; that end is told like any other.
        var ready = false
        try? endingShow { ready = recorder.prepareNextShow(from: template) }
        return ready
    }

    /// Ends the open Show, so the next record starts a new one. Never during a Take.
    public func endShow() throws {
        try endingShow { try recorder.endShow() }
    }

    /// Does `change`, then tells the Show that was open if it ended.
    private func endingShow(_ change: () throws -> Void) throws {
        let open = recorder.currentShow
        try change()
        if let open, recorder.currentShow?.folder != open.folder {
            emit.yield(.showEnded(name: open.name, takeCount: open.takeCount))
        }
    }

    /// About once a second: clears the start time once no Take runs, and disarms an idle recorder. Every Take starts
    /// through `record`, which tells its start (#551).
    public func tick() {
        if !recorder.isRecording, !recorder.isFinishing { takeStartedAt = nil }
        disarmIfIdle()
    }

    /// The screen locked or the app left the front: start counting idle time.
    public func appMovedToBackground() {
        idle.becameIdle(at: now())
    }

    /// The operator asked to Arm again (the alert's button). Arms only: never starts a Take.
    public func armAgain() {
        disarmedForIdle = false
        arm()
    }

    /// The app is in front again: stop counting, and Arm again if it was disarmed for being idle.
    public func appBecameActive() {
        idle.becameActive()
        if disarmedForIdle {
            disarmedForIdle = false
            arm()
        }
    }

    /// The Pre-roll length or the sample rate choice changed: re-Arm so the input uses it. Only between Takes; a
    /// running Take keeps what it started with (Show-Safe Promise).
    public func settingsChanged() {
        if recorder.isArmed, !recorder.isRecording { arm() }
    }

    /// The tier changed (the App Store answered, a purchase, a refund): re-Arm between Takes when the 48 kHz cap now
    /// differs from the rate the input runs at (#316). A running Take keeps its rate; the change applies at the next Arm.
    public func tierChanged() {
        // A Take being saved is still the Take: decide once it is on disk, as `deviceListChanged` does, or the Arm would fail
        // with a false "Couldn't start" after a clean Take and the new rate would wait for the next Arm (#884).
        if recorder.isFinishing {
            Task { [self] in
                await recorder.waitWhileFinishing()
                tierChanged()
            }
            return
        }
        guard recorder.isArmed, !recorder.isRecording, let rate = recorder.sampleRate else { return }
        let capped = capsAt48k()
        if (capped && rate > 48_000) || (!capped && (sampleRateChoice ?? rate) > rate) { arm() }
    }

    /// The list of Audio interfaces changed (the Mac): keeps, switches, re-Arms or disarms as `InputDeviceChange`
    /// decides. A Take on an interface that went away or changed format ends as an input change, with its message.
    public func deviceListChanged() async {
        // A Take being saved is still the Take: decide once it is on disk, so the Arm below can succeed.
        await recorder.waitWhileFinishing()
        let fresh = source.devices()
        let change = InputDeviceChange.decide(
            old: devices.map(\.info), new: fresh.map(\.info),
            selectedID: selectedDeviceID,
            armed: recorder.isArmed ? armedDevice : nil,
            isRecording: recorder.isRecording)
        devices = fresh
        if change.stopsTake {
            do {
                try await recorder.stopTake(because: .inputChanged)
                recordError = change.message
            } catch {
                recordError = "\(change.message ?? "The input device changed during the Take.") But the Take didn't finish cleanly: \(error.localizedDescription)"
            }
        }
        selectedDeviceID = change.selectedID
        switch change.action {
        case .none:
            break
        case .arm:
            arm()
        case .disarm:
            recorder.disarm()
            armedDevice = nil
            didArm(nil)
            emit.yield(.disarmed(reason: .deviceLost))
            if !change.stopsTake { armError = change.message }
        }
    }

    /// The iOS input route really changed (the App filters out its own changes and selects the route's input first):
    /// re-Arm between Takes, move a running Take onto the new route, as `InterruptionPolicy.routeChanged` decides.
    public func routeChanged() async {
        await recorder.waitWhileFinishing()
        switch interruptions.routeChanged(isRecording: recorder.isRecording) {
        case .none: break
        case .rearm: arm()
        case .moveInput: await moveTakeToCurrentRoute()
        }
    }

    /// Moves a running Take onto the current route, keeping it if the format still matches (#10). It asks for the
    /// Take's rate (#195): the default 48 kHz would end a 96 or 44.1 kHz Take.
    private func moveTakeToCurrentRoute() async {
        let wasStopped = interruptions.isInputStopped
        do {
            let device = try source.currentRouteDevice(sampleRate: recorder.sampleRate)
            let continued = try await recorder.restartInput(on: device)
            armedDevice = devices.first { $0.id == selectedDeviceID }?.info
            if !continued, let armedDevice { emit.yield(.armed(armedDevice)) }
            didArm(device)
            log("Input route changed during a Take; \(continued ? "the Take continues" : "the format changed, so the Take was stopped and saved")")
            if !continued { recordError = TakeEnd.Reason.inputChanged.message }
            // A retry that works ends the "input is stopped" state the failed move left behind.
            if wasStopped { await handle(.restarted) }
        } catch {
            // The policy says what's missing and tries again on the next route change or foreground.
            await handle(.moveFailed(String(describing: error)))
        }
    }

    /// An audio session interruption, a media services reset or a change of app state: `InterruptionPolicy` decides,
    /// and this carries it out on the recorder. Nothing here ends a Take, except a reset whose new input can't take it.
    public func handle(_ event: InterruptionPolicy.Event) async {
        await carryOut(event)
        tellInputState()
    }

    /// Told against what was last told, not the state on entry: `handle` calls itself for a restart.
    private func tellInputState() {
        if interruptions.isInputStopped != toldInputStopped {
            toldInputStopped = interruptions.isInputStopped
            emit.yield(toldInputStopped ? .inputStopped : .inputRestarted)
        }
    }

    private func carryOut(_ event: InterruptionPolicy.Event) async {
        await perform(interruptions.handle(event, isRecording: recorder.isRecording))
    }

    private func perform(_ response: InterruptionPolicy.Response) async {
        if let line = response.log { log(line) }
        switch response.action {
        case .none:
            break
        case .restartInput:
            do {
                try recorder.restartInput()
                await handle(.restarted)
            } catch {
                await handle(.restartFailed(String(describing: error)))
            }
        case .replaceDevice:
            guard let choice = devices.first(where: { $0.id == selectedDeviceID }) else {
                await handle(.restartFailed("no audio interface is selected"))
                return
            }
            do {
                let wasRecording = recorder.isRecording
                // The replacement keeps the rate the recorder runs at, uncapped, so a running Take can continue.
                let device = try choice.make(recorder.sampleRate ?? sampleRateChoice, false)
                let continued = try await recorder.restartInput(on: device)
                if !continued {
                    // A new format re-Armed the recorder on the new device.
                    armedDevice = choice.info
                    emit.yield(.armed(choice.info))
                }
                didArm(device)
                await handle(wasRecording && !continued ? .takeEndedByReset : .restarted)
            } catch {
                await handle(.restartFailed(String(describing: error)))
            }
        }
    }

    /// Disarms an unused recorder that has been idle for 30 minutes. Never during a Take.
    private func disarmIfIdle() {
        guard recorder.isArmed, idle.shouldDisarm(at: now(), isRecording: recorder.isRecording) else { return }
        recorder.disarm()
        armedDevice = nil
        disarmedForIdle = true
        emit.yield(.disarmed(reason: .idle))
    }

    /// The recorder ended a Take, whoever ended it: told at once, not on the next tick.
    private func takeEnded(_ end: TakeEnd) {
        takeStartedAt = nil
        // A Take the recorder ended (out of space, no Destination) says why (#551). An input change is told by whoever
        // noticed it (a device-list or route change sets its own message, a media reset its notice), never twice.
        if end.reason != .inputChanged, let message = end.reason.message { recordError = message }
        var end = end
        end.isSoundcheck = soundcheckTake
        soundcheckTake = false
        emit.yield(.takeEnded(end))
    }
}
