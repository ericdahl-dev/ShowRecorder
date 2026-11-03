import Foundation
@testable import Recording
import Telemetry
import Testing

/// Usage events from Takes (ADR 0007, #1026): `TakeTelemetry` turns the sequencer's `TakeEvent`s into telemetry
/// events, so the sequencer and the audio path don't change.
@MainActor
@Suite("Take telemetry")
struct TakeTelemetryTests {
    @Test("A Take starting sends take_started with its channel count, Destinations and Mixer family")
    func takeStarted() {
        var sent: [TelemetryEvent] = []
        let telemetry = TakeTelemetry(send: { sent.append($0) })
        telemetry.handle(.takeStarted(take: 1), context: TakeContext(channelCount: 18, destinations: .both, mixerFamily: "xair"))
        #expect(sent == [.takeStarted(channelCount: 18, destinations: .both, mixerFamily: "xair")])
    }
}
