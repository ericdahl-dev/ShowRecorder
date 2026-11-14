import Testing

@testable import Recording

/// Whether the delete sheet may delete a Show now, must end the open Show first, or is blocked.
@Suite("Delete gate")
struct DeleteGateTests {
    @Test("A Show that isn't open deletes right away")
    func notOpen() {
        #expect(DeleteGate.decide(isRecording: false, isFinishing: false, isOpenShow: false, wholeShow: true) == .ready)
    }

    @Test("The open Show, with no Take running, is ended and then deleted in one step")
    func openShow() {
        #expect(DeleteGate.decide(isRecording: false, isFinishing: false, isOpenShow: true, wholeShow: true) == .endShowFirst)
    }

    @Test("One Take or file of the open Show stays blocked: only deleting the whole Show ends it")
    func partOfOpenShow() {
        #expect(DeleteGate.decide(isRecording: false, isFinishing: false, isOpenShow: true, wholeShow: false)
            == .blocked("This Show is open. End it first (tap the Show name on the record screen)."))
        #expect(DeleteGate.decide(isRecording: false, isFinishing: false, isOpenShow: false, wholeShow: false) == .ready)
    }

    @Test("Nothing deletes during a Take or while one finishes, open Show or not")
    func blocked() {
        for open in [false, true] {
            #expect(DeleteGate.decide(isRecording: true, isFinishing: false, isOpenShow: open, wholeShow: true) == .blocked("A Take is running. Stop it first."))
            #expect(DeleteGate.decide(isRecording: false, isFinishing: true, isOpenShow: open, wholeShow: true) == .blocked(RecorderError.finishing.errorDescription ?? ""))
        }
    }
}
