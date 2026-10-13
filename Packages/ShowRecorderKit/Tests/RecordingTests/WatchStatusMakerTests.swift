import Destinations
import Foundation
import MixerLink
@testable import Recording
import Testing
import WatchRemote

/// What the iPhone tells the watch (#100), from what the record screen already knows: no new signals of its own.
@Suite("Watch status maker")
struct WatchStatusMakerTests {
    static let started = Date(timeIntervalSince1970: 1_000)
    static func chip(_ kind: StatusChip.Kind, _ state: StatusChip.State) -> StatusChip {
        StatusChip(kind: kind, text: "", state: state)
    }

    @Test("Not Armed, Armed, and Recording with when it started, its title and its Marker count")
    func state() {
        #expect(WatchStatusMaker.make(isArmed: false, take: nil).state == .notArmed)
        #expect(WatchStatusMaker.make(isArmed: true, take: nil).state == .armed)
        let take = WatchStatusMaker.Take(startedAt: Self.started, title: "Take 02", markerCount: 3)
        #expect(WatchStatusMaker.make(isArmed: true, take: take).state
                == .recording(startedAt: Self.started, takeTitle: "Take 02", markerCount: 3))
    }

    @Test("Problems come from the status chips, the Copies, Dropouts and the Mixer Link")
    func problems() {
        let take = WatchStatusMaker.Take(startedAt: Self.started, title: "Take 02", markerCount: 0)
        let status = WatchStatusMaker.make(
            isArmed: true, take: take,
            chips: [Self.chip(.device, .attention), Self.chip(.drive, .attention), Self.chip(.mixer, .attention)],
            driveAvailable: true, copies: [.device: .recording, .drive: .interrupted], dropoutCount: 2, mixerDown: true)
        #expect(status.problems == [.deviceLowSpace, .driveLowSpace, .copyStopped, .gapOrDropout, .mixerLinkLost])
    }

    @Test("All quiet says nothing; a missing Drive isn't 'low on space'; a Copy that never started isn't 'stopped'")
    func quiet() {
        let status = WatchStatusMaker.make(
            isArmed: true, take: nil, chips: [Self.chip(.device, .ok), Self.chip(.drive, .attention)],
            driveAvailable: false, copies: [.drive: .missing], dropoutCount: 0, mixerDown: false)
        #expect(status.problems.isEmpty)
    }
}
