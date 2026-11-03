import Foundation
import Telemetry

/// What the app knows about a Take that the sequencer's events don't carry.
public struct TakeContext: Equatable, Sendable {
    public var channelCount: Int
    public var destinations: TelemetryDestinations
    /// The Mixer family's raw value when the Mixer Link is connected, else nil.
    public var mixerFamily: String?

    public init(channelCount: Int, destinations: TelemetryDestinations, mixerFamily: String?) {
        self.channelCount = channelCount
        self.destinations = destinations
        self.mixerFamily = mixerFamily
    }
}

/// Usage events from Takes (ADR 0007, #1026): turns the sequencer's `TakeEvent`s into telemetry events, so the
/// sequencer and the real-time audio path (ADR 0002) don't change. The app feeds it the sequencer's event stream.
@MainActor
public final class TakeTelemetry {
    private let send: (TelemetryEvent) -> Void

    public init(send: @escaping (TelemetryEvent) -> Void) {
        self.send = send
    }

    public func handle(_ event: TakeEvent, context: TakeContext) {
        if case .takeStarted = event {
            send(.takeStarted(
                channelCount: context.channelCount, destinations: context.destinations, mixerFamily: context.mixerFamily
            ))
        }
    }
}
