@testable import Recording
import Testing

/// The record screen's line about how the last Take's Copies ended up.
@Suite("Copy summary")
struct CopySummaryTests {
    @Test("Each outcome has its word: complete, has Gaps, Repaired, Repair failed")
    func everyOutcomeWord() {
        #expect(CopySummary(copies: takeCopies(running: false, device: .hasGaps, drive: .repaired), dropoutCount: 0).text == "Device copy: has Gaps · Drive copy: Repaired")
        #expect(CopySummary(copies: takeCopies(running: false, device: .complete, drive: .repairFailed), dropoutCount: 0).text == "Device copy: complete · Drive copy: Repair failed")
    }

    @Test("Two complete Copies and no Dropouts read as before")
    func twoCopies() {
        let summary = CopySummary(copies: takeCopies(running: false, device: .complete, drive: .complete), dropoutCount: 0)
        #expect(summary.text == "Device copy: complete · Drive copy: complete")
        #expect(!summary.isProblem)
    }

    @Test("A lone Copy says there was no Drive")
    func oneCopy() {
        let summary = CopySummary(copies: takeCopies(running: false, device: .complete, drive: .missing), dropoutCount: 0)
        #expect(summary.text == "Device copy: complete (no Drive)")
        #expect(!summary.isProblem)
    }

    @Test("A lone Drive Copy says there was no device copy")
    func oneDriveCopy() {
        let summary = CopySummary(copies: takeCopies(running: false, device: .missing, drive: .complete), dropoutCount: 0)
        #expect(summary.text == "Drive copy: complete (no device copy)")
    }

    @Test("A Take with Dropouts says how many and is a problem")
    func dropouts() {
        let summary = CopySummary(copies: takeCopies(running: false, device: .complete, drive: .complete), dropoutCount: 2)
        #expect(summary.text == "Device copy: complete · Drive copy: complete · 2 Dropouts")
        #expect(summary.isProblem)
    }

    @Test("One Dropout is singular, and goes with a lone Copy's note")
    func oneDropout() {
        let summary = CopySummary(copies: takeCopies(running: false, device: .complete, drive: .missing), dropoutCount: 1)
        #expect(summary.text == "Device copy: complete (no Drive) · 1 Dropout")
        #expect(summary.isProblem)
    }

    @Test("Gaps are still a problem")
    func gaps() {
        let summary = CopySummary(copies: takeCopies(running: false, device: .hasGaps, drive: .repaired), dropoutCount: 0)
        #expect(summary.text == "Device copy: has Gaps · Drive copy: Repaired")
        #expect(summary.isProblem)
    }

    @Test("Today's call with the last Take's outcomes, as the record screen passes them, reads the same")
    func outcomesCall() {
        #expect(CopySummary(outcomes: [.device: .complete], dropoutCount: 0).text == "Device copy: complete (no Drive)")
        #expect(CopySummary(outcomes: [.device: .hasGaps, .drive: .repaired], dropoutCount: 1).text
                == "Device copy: has Gaps · Drive copy: Repaired · 1 Dropout")
    }

    @Test("A Copy that never ended (interrupted with no outcome) isn't counted, as a missing one isn't")
    func copyWithoutOutcome() {
        let summary = CopySummary(copies: takeCopies(running: false, device: .complete, drive: .interrupted), dropoutCount: 0)
        #expect(summary.text == "Device copy: complete (no Drive)")
    }

    @Test("A Repair that failed is a problem")
    func repairFailedIsAProblem() {
        #expect(CopySummary(copies: takeCopies(running: false, device: .complete, drive: .repairFailed), dropoutCount: 0).isProblem)
    }
}
