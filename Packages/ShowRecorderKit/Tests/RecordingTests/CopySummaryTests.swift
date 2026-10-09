@testable import Recording
import Testing

/// The record screen's line about how the last Take's Copies ended up.
@Suite("Copy summary")
struct CopySummaryTests {
    @Test("Two complete Copies and no Dropouts read as before")
    func twoCopies() {
        let summary = CopySummary(outcomes: [.device: .complete, .drive: .complete], dropoutCount: 0)
        #expect(summary.text == "Device copy: complete · Drive copy: complete")
        #expect(!summary.isProblem)
    }

    @Test("A lone Copy says there was no Drive")
    func oneCopy() {
        let summary = CopySummary(outcomes: [.device: .complete], dropoutCount: 0)
        #expect(summary.text == "Device copy: complete (no Drive)")
        #expect(!summary.isProblem)
    }

    @Test("A lone Drive Copy says there was no device copy")
    func oneDriveCopy() {
        let summary = CopySummary(outcomes: [.drive: .complete], dropoutCount: 0)
        #expect(summary.text == "Drive copy: complete (no device copy)")
    }

    @Test("A Take with Dropouts says how many and is a problem")
    func dropouts() {
        let summary = CopySummary(outcomes: [.device: .complete, .drive: .complete], dropoutCount: 2)
        #expect(summary.text == "Device copy: complete · Drive copy: complete · 2 Dropouts")
        #expect(summary.isProblem)
    }

    @Test("One Dropout is singular, and goes with a lone Copy's note")
    func oneDropout() {
        let summary = CopySummary(outcomes: [.device: .complete], dropoutCount: 1)
        #expect(summary.text == "Device copy: complete (no Drive) · 1 Dropout")
        #expect(summary.isProblem)
    }

    @Test("Gaps are still a problem")
    func gaps() {
        let summary = CopySummary(outcomes: [.device: .hasGaps, .drive: .repaired], dropoutCount: 0)
        #expect(summary.text == "Device copy: has Gaps · Drive copy: Repaired")
        #expect(summary.isProblem)
    }
}
