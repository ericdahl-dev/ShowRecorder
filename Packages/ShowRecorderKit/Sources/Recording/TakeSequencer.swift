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
}

/// Takes, start to end, on the recorder: which Audio interface is Armed, record and stop.
@MainActor
@Observable
public final class TakeSequencer {
    public let recorder: Recorder
    @ObservationIgnored private let capsAt48k: () -> Bool
    @ObservationIgnored private let now: () -> Date
    /// The last Take end told to the events stream, so each is told once.
    @ObservationIgnored private var toldTakeEnd: TakeEnd?
    /// Whether the running Take has been told to the events stream.
    @ObservationIgnored private var toldTakeStarted = false

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

    /// Called after each attempt to Arm an interface: with the device when it worked, nil when it failed. The App
    /// resets its meters and reads what the system offered here.
    @ObservationIgnored public var didArm: (_ device: (any AudioIODevice)?) -> Void = { _ in }
    /// Everything that happens, in order. One listener.
    public let events: AsyncStream<TakeEvent>
    @ObservationIgnored private let emit: AsyncStream<TakeEvent>.Continuation

    public init(recorder: Recorder, devices: any InputDeviceSource, capsAt48k: @escaping () -> Bool, now: @escaping () -> Date = Date.init) {
        self.recorder = recorder
        self.now = now
        toldTakeEnd = recorder.lastTakeEnd
        self.capsAt48k = capsAt48k
        (events, emit) = AsyncStream.makeStream()
        self.devices = devices.devices()
        selectedDeviceID = self.devices.first?.id
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
        tellTakeEnd()
    }

    /// About once a second: tells a Take started elsewhere (the Soundcheck) or ended by the recorder on its own.
    public func tick() {
        tellTakeEnd()
        if recorder.isRecording { tellTakeStart() }
        if !recorder.isRecording { takeStartedAt = nil }
    }

    private func tellTakeStart() {
        guard !toldTakeStarted else { return }
        toldTakeStarted = true
        emit.yield(.takeStarted(take: recorder.currentShow?.takeCount ?? 0))
    }

    private func tellTakeEnd() {
        guard let end = recorder.lastTakeEnd, end != toldTakeEnd else { return }
        toldTakeEnd = end
        toldTakeStarted = false
        emit.yield(.takeEnded(end))
    }
}
