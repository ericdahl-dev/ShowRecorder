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
}

/// What happened to the recorder, for whoever follows Takes.
public enum TakeEvent: Equatable, Sendable {
    case armed(InputDeviceInfo)
    case takeStarted(take: Int)
    case takeEnded(TakeEnd)
    case disarmed(reason: DisarmReason)

    public enum DisarmReason: Equatable, Sendable {
        /// The screen showing the recorder went away with no Take running.
        case screenGone
        /// The app sat in the background for 30 minutes with no Take (`IdleDisarm`).
        case idle
    }
}

/// Takes, start to end, on the recorder: which Audio interface is Armed, record and stop.
@MainActor
@Observable
public final class TakeSequencer {
    public let recorder: Recorder
    @ObservationIgnored private let capsAt48k: () -> Bool
    @ObservationIgnored private let now: () -> Date
    /// Whether the running Take has been told to the events stream, and its end not yet.
    @ObservationIgnored private var toldTakeStarted = false
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

    /// Called after each attempt to Arm an interface: with the device when it worked, nil when it failed. The App
    /// resets its meters and reads what the system offered here.
    @ObservationIgnored public var didArm: (_ device: (any AudioIODevice)?) -> Void = { _ in }
    /// Everything that happens, in order. One listener. With no one listening only the newest
    /// `eventBufferSize` are kept, so a stream nobody reads never grows. It ends when the sequencer goes away.
    /// Every Take start and end is told. Arm and disarm are told for the sequencer's own Arming; a device-list,
    /// route or media-reset change still re-Arms from the App and isn't told yet (#301 slices 5-7).
    public let events: AsyncStream<TakeEvent>
    public static let eventBufferSize = 32
    @ObservationIgnored private let emit: AsyncStream<TakeEvent>.Continuation

    public init(recorder: Recorder, devices: any InputDeviceSource, capsAt48k: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.recorder = recorder
        self.now = now
        self.capsAt48k = capsAt48k
        (events, emit) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(Self.eventBufferSize))
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
        recorder.isRecording ? .askToStop : .close
    }

    /// What to do when the operator quits the app (the Mac).
    public enum QuitAction: Equatable, Sendable {
        case quit
        /// A Take is running: ask whether to stop it, and quit only if the answer is stop.
        case askToStop
    }

    /// The operator asked to quit (Command-Q or the Dock menu).
    public func quitRequested() -> QuitAction {
        recorder.isRecording ? .askToStop : .quit
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
        do {
            armedDevice = nil
            let device = try choice.make(sampleRateChoice, capsAt48k())
            try recorder.arm(device)
            armedDevice = choice.info
            armError = nil
            emit.yield(.armed(choice.info))
            didArm(device)
        } catch {
            armError = "Couldn't start \(choice.name): \(error)"
            didArm(nil)
        }
    }

    /// Starts a Take with what the Mixer Link and the tier say right now (the Show-Safe Promise: judged only here).
    /// Returns whether it started.
    @discardableResult
    public func record(sources: [Source], allowance: TakeAllowance?) -> Bool {
        do {
            try recorder.startTake(sources: sources, allowance: allowance)
            takeStartedAt = now()
            recordError = nil
            tellTakeStart()
            return true
        } catch {
            recordError = "Couldn't start recording: \(error.localizedDescription)"
            return false
        }
    }

    /// Ends the running Take.
    public func stop() {
        takeStartedAt = nil
        do {
            try recorder.stopTake()
        } catch {
            recordError = "The Take didn't finish cleanly: \(error.localizedDescription)"
        }
    }

    /// About once a second: tells a Take started elsewhere (the Soundcheck).
    public func tick() {
        if recorder.isRecording { tellTakeStart() }
        if !recorder.isRecording { takeStartedAt = nil }
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

    /// Disarms an unused recorder that has been idle for 30 minutes. Never during a Take.
    private func disarmIfIdle() {
        guard recorder.isArmed, idle.shouldDisarm(at: now(), isRecording: recorder.isRecording) else { return }
        recorder.disarm()
        armedDevice = nil
        disarmedForIdle = true
        emit.yield(.disarmed(reason: .idle))
    }

    private func tellTakeStart() {
        guard !toldTakeStarted else { return }
        toldTakeStarted = true
        emit.yield(.takeStarted(take: recorder.currentShow?.takeCount ?? 0))
    }

    /// The recorder ended a Take, whoever ended it: told at once, not on the next tick. A Take started elsewhere that
    /// ended before a tick saw it is told as started first.
    private func takeEnded(_ end: TakeEnd) {
        takeStartedAt = nil
        if !toldTakeStarted { emit.yield(.takeStarted(take: end.take)) }
        toldTakeStarted = false
        emit.yield(.takeEnded(end))
    }
}
