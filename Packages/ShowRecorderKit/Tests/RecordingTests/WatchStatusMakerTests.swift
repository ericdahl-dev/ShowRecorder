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

    @Test("Not Ready, Ready, and Recording with when it started, its title and its Marker count")
    func state() {
        #expect(WatchStatusMaker.make(isReady: false, take: nil).state == .notReady)
        #expect(WatchStatusMaker.make(isReady: true, take: nil).state == .ready)
        let take = WatchStatusMaker.Take(startedAt: Self.started, title: "Take 02", markerCount: 3)
        #expect(WatchStatusMaker.make(isReady: true, take: take).state
                == .recording(startedAt: Self.started, takeTitle: "Take 02", markerCount: 3))
    }

    @Test("Problems come from the status chips, the Copies, Dropouts and the Mixer Link")
    func problems() {
        let take = WatchStatusMaker.Take(startedAt: Self.started, title: "Take 02", markerCount: 0)
        let status = WatchStatusMaker.make(
            isReady: true, take: take,
            chips: [Self.chip(.device, .attention), Self.chip(.drive, .attention), Self.chip(.mixer, .attention)],
            driveAvailable: true, copies: takeCopies(device: .recording, drive: .interrupted), dropoutCount: 2, mixerDown: true)
        #expect(status.problems == [.deviceLowSpace, .driveLowSpace, .copyStopped, .gapOrDropout, .mixerLinkLost])
    }

    @Test("All quiet says nothing; a missing Drive isn't 'low on space'; a Copy that never started isn't 'stopped'")
    func quiet() {
        let status = WatchStatusMaker.make(
            isReady: true, take: nil, chips: [Self.chip(.device, .ok), Self.chip(.drive, .attention)],
            driveAvailable: false, copies: takeCopies(device: .recording, drive: .missing), dropoutCount: 0, mixerDown: false)
        #expect(status.problems.isEmpty)
    }
    @Test("A chip for a Copy that stopped (failed) isn't low space: it's a Copy stopped")
    func stoppedIsNotLowSpace() {
        let take = WatchStatusMaker.Take(startedAt: Self.started, title: "Take 02", markerCount: 0)
        let status = WatchStatusMaker.make(
            isReady: true, take: take, chips: [Self.chip(.device, .failed), Self.chip(.drive, .failed)],
            driveAvailable: true, copies: takeCopies(device: .interrupted, drive: .interrupted))
        #expect(status.problems == [.copyStopped])
    }

    @Test("A Copy stopped for low space is its own problem on the wrist, not a Copy stopped (#560)")
    func fullIsItsOwnProblem() {
        let take = WatchStatusMaker.Take(startedAt: Self.started, title: "Take 02", markerCount: 0)
        let full = WatchStatusMaker.make(
            isReady: true, take: take, chips: [Self.chip(.drive, .failed)], driveAvailable: true,
            copies: takeCopies(device: .recording, drive: .full))
        #expect(full.problems == [.copyFull])
        let both = WatchStatusMaker.make(isReady: true, take: take, copies: takeCopies(device: .interrupted, drive: .full))
        #expect(both.problems == [.copyStopped, .copyFull])
        #expect(WatchStatus.Problem.copyFull.text == "A Copy is full")
    }

    @Test("After a Take, a Copy that stopped during it is no longer a problem on the wrist")
    func stoppedOnlyWhileRunning() {
        let status = WatchStatusMaker.make(isReady: true, take: nil, copies: takeCopies(running: false, device: .interrupted, drive: .interrupted))
        #expect(status.problems.isEmpty)
    }
}
