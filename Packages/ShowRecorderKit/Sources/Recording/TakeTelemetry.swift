import Foundation
import Telemetry

/// What the app knows about a Take that the sequencer's events don't carry.
public struct TakeContext: Equatable, Sendable {
    public var channelCount: Int
    public var destinations: TelemetryDestinations
    /// The Mixer family's raw value when the Mixer Link is connected, else nil.
    public var mixerFamily: String?
    /// The running Take's Dropouts so far (`RecordScreenState.dropoutCount`).
    public var dropouts: Int

    public init(channelCount: Int, destinations: TelemetryDestinations, mixerFamily: String?, dropouts: Int = 0) {
        self.channelCount = channelCount
        self.destinations = destinations
        self.mixerFamily = mixerFamily
        self.dropouts = dropouts
    }
}

/// Usage events from Takes (ADR 0007, #1026): turns the sequencer's `TakeEvent`s into telemetry events, so the
/// sequencer and the real-time audio path (ADR 0002) don't change. The app feeds it the sequencer's event stream.
@MainActor
public final class TakeTelemetry {
    private let send: (TelemetryEvent) -> Void
    private let now: () -> Date
    private var startedAt: Date?

    public init(send: @escaping (TelemetryEvent) -> Void, now: @escaping () -> Date = Date.init) {
        self.send = send
        self.now = now
    }

    public func handle(_ event: TakeEvent, context: TakeContext) {
        switch event {
        case .takeStarted:
            startedAt = now()
            send(.takeStarted(
                channelCount: context.channelCount, destinations: context.destinations, mixerFamily: context.mixerFamily
            ))
        case let .takeEnded(end):
            let seconds = startedAt.map { Int(now().timeIntervalSince($0)) } ?? 0
            startedAt = nil
            send(.takeStopped(
                seconds: seconds, channelCount: context.channelCount, dropouts: context.dropouts,
                cause: Self.cause(end.reason)
            ))
        default:
            break
        }
    }

    static func cause(_ reason: TakeEnd.Reason) -> TakeStopCause {
        switch reason {
        case .stopped: .stopped
        case .outOfSpace: .outOfSpace
        case .noDestination: .noDestination
        case .inputChanged: .inputChanged
        }
    }
}

extension TakeContext {
    /// The context of the Take on the Ready `recorder`: its USB Channels, its Record to and its Dropouts so far.
    @MainActor
    public init(recorder: Recorder, mixerFamily: String?) {
        let destinations: TelemetryDestinations = switch recorder.recordTo {
        case .device: .device
        case .drive: .driveOnly
        case .both: .both
        }
        self.init(
            channelCount: recorder.usbChannelCount, destinations: destinations, mixerFamily: mixerFamily,
            dropouts: recorder.dropoutCount)
    }
}
