@testable import Recording
import Testing

/// What the App does when the Take sequencer tells it something (#551 PR 5): one place, from the one event stream,
/// whoever started or ended the Take. Eric (2026-10-13): a Take the recorder ends itself gets the same Pro offer as
/// Stop; the Soundcheck Take shows on the Live Activity and the watch, with no Pro offer.
@Suite("Take follow-up")
struct TakeFollowUpTests {
    let end = TakeEvent.takeEnded(TakeEnd(take: 1, reason: .stopped))

    @Test("A Take's start, each Marker and its end update the Live Activity")
    func liveActivity() {
        for event in [TakeEvent.takeStarted(take: 1), .markerPlaced(count: 2), end] {
            #expect(TakeFollowUp(event).contains(.liveActivity), "\(event)")
        }
        #expect(TakeFollowUp(.inputStopped).isEmpty)
    }

    @Test("Every Take end offers Pro where it's due, whoever ended it, Stop or out of space")
    func proOfferAfterAnyEnd() {
        for reason in [TakeEnd.Reason.stopped, .outOfSpace, .noDestination, .inputChanged] {
            #expect(TakeFollowUp(.takeEnded(TakeEnd(take: 1, reason: reason))).contains(.proOffer), "\(reason)")
        }
    }

    @Test("The Soundcheck Take shows on the Live Activity but never offers Pro")
    func soundcheck() {
        let followUp = TakeFollowUp(.takeEnded(TakeEnd(take: 1, reason: .stopped, isSoundcheck: true)))
        #expect(followUp.contains(.liveActivity))
        #expect(!followUp.contains(.proOffer))
    }
}
