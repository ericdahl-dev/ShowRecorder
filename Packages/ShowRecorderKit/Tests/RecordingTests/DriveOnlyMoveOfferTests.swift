@testable import Recording
import Testing

/// When a Drive connects with Drive only Takes waiting on the Device (#805): move them, ask first, or do nothing.
@Suite("Drive only move offer")
struct DriveOnlyMoveOfferTests {
    @Test("During a Take nothing is moved or asked, whatever the choice (#805)")
    func duringATake() {
        for choice in RecordTo.allCases {
            for isOffered in [false, true] {
                #expect(DriveOnlyMoveOffer.decide(storedChoice: choice, isOffered: isOffered, isRecording: true,
                                                  waitingTakes: 2, askedThisConnection: false) == .leave)
            }
        }
    }

    @Test("Where Record to isn't offered, waiting Takes move as today, whatever the choice (#805)")
    func notOffered() {
        for choice in RecordTo.allCases {
            #expect(DriveOnlyMoveOffer.decide(storedChoice: choice, isOffered: false, isRecording: false,
                                              waitingTakes: 2, askedThisConnection: false) == .move)
        }
    }

    @Test("With no Drive only Take waiting on the Device there is nothing to move or ask (#805)")
    func nothingWaiting() {
        for choice in RecordTo.allCases {
            for isOffered in [false, true] {
                #expect(DriveOnlyMoveOffer.decide(storedChoice: choice, isOffered: isOffered, isRecording: false,
                                                  waitingTakes: 0, askedThisConnection: false) == .leave)
            }
        }
    }

    @Test("With Drive or Both chosen, waiting Takes move without asking, every connection (#805)")
    func driveOrBoth() {
        for choice in [RecordTo.drive, .both] {
            for asked in [false, true] {
                #expect(DriveOnlyMoveOffer.decide(storedChoice: choice, isOffered: true, isRecording: false,
                                                  waitingTakes: 2, askedThisConnection: asked) == .move)
            }
        }
    }

    @Test("With the Device chosen, the operator is asked first, with how many Takes wait (#805)")
    func deviceAsks() {
        #expect(DriveOnlyMoveOffer.decide(storedChoice: .device, isOffered: true, isRecording: false,
                                          waitingTakes: 3, askedThisConnection: false) == .ask(takeCount: 3))
    }

    @Test("With the Device chosen, the operator is asked only once per Drive connection (#805)")
    func deviceAsksOnce() {
        #expect(DriveOnlyMoveOffer.decide(storedChoice: .device, isOffered: true, isRecording: false,
                                          waitingTakes: 3, askedThisConnection: true) == .leave)
    }

    @Test("A Drive that connects during a Take, with the Device chosen, is asked about once the Take stops (#805)")
    func askedAfterStop() {
        var asked = false
        func check(isRecording: Bool) -> DriveOnlyMoveOffer {
            let offer = DriveOnlyMoveOffer.decide(storedChoice: .device, isOffered: true, isRecording: isRecording,
                                                  waitingTakes: 2, askedThisConnection: asked)
            if case .ask = offer { asked = true }
            return offer
        }
        #expect(check(isRecording: true) == .leave)
        #expect(check(isRecording: false) == .ask(takeCount: 2))
        #expect(check(isRecording: false) == .leave, "once per connection")
    }

    @Test("The question names how many Takes wait and on which device (#805)")
    func questionPlural() {
        #expect(DriveOnlyMoveOffer.question(takeCount: 3, deviceWord: "iPhone")
            == "3 Takes recorded for the Drive are on this iPhone. Move them to the Drive now?")
        #expect(DriveOnlyMoveOffer.question(takeCount: 2, deviceWord: "Mac")
            == "2 Takes recorded for the Drive are on this Mac. Move them to the Drive now?")
    }

    @Test("One waiting Take reads in the singular (#805)")
    func questionSingular() {
        #expect(DriveOnlyMoveOffer.question(takeCount: 1, deviceWord: "iPad")
            == "1 Take recorded for the Drive is on this iPad. Move it to the Drive now?")
    }

}
