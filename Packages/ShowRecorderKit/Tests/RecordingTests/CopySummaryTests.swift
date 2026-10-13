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

    @Test("No summary while a Take runs, or when no Copy of the last Take ended (there was no Take)")
    func noSummaryWithoutEndedCopies() {
        #expect(CopySummary.ofLastTake(takeCopies(running: true, device: .recording, drive: .recording), dropoutCount: 0) == nil)
        #expect(CopySummary.ofLastTake(takeCopies(running: false, device: .missing, drive: .missing), dropoutCount: 0) == nil)
        #expect(CopySummary.ofLastTake(takeCopies(running: false, device: .complete, drive: .missing), dropoutCount: 0)?.text
                == "Device copy: complete (no Drive)")
    }

    @Test("Drive only: the Drive Copy ended reads as the Drive's word alone, with no device-copy note (#550)")
    func driveOnlyDriveCopy() {
        let summary = CopySummary(copies: takeCopies(running: false, driveOnly: true, device: .complete, drive: .complete), dropoutCount: 0)
        #expect(summary.text == "Drive copy: complete")
        #expect(!summary.isProblem)
        #expect(CopySummary(copies: takeCopies(running: false, driveOnly: true, device: .missing, drive: .hasGaps), dropoutCount: 1).text
                == "Drive copy: has Gaps · 1 Dropout")
    }

    @Test("Drive only: a Take the Drive never got is on this iPhone until the Drive is back (#550)")
    func driveOnlyOnDevice() {
        let copies = takeCopies(running: false, driveOnly: true, device: .complete, drive: .missing)
        #expect(CopySummary.ofLastTake(copies, dropoutCount: 0)?.text == "On this iPhone until the Drive is back")
        #expect(CopySummary(copies: copies, dropoutCount: 2).text == "On this iPhone until the Drive is back · 2 Dropouts")
    }

    @Test("Drive only: a stand-in Repair moved to the Drive says it moved from this iPhone (#550)")
    func driveOnlyMoved() {
        let copies = takeCopies(running: false, driveOnly: true, device: .moved, drive: .repaired)
        #expect(CopySummary.ofLastTake(copies, dropoutCount: 0)?.text == "Drive copy: Repaired · moved from this iPhone")
        #expect(CopySummary(copies: copies, dropoutCount: 1).text == "Drive copy: Repaired · moved from this iPhone · 1 Dropout")
    }

    @Test("Drive only: the lines name the device the app runs on (#550)")
    func driveOnlyDeviceWord() {
        #expect(CopySummary.ofLastTake(takeCopies(running: false, driveOnly: true, device: .complete, drive: .missing), dropoutCount: 0, deviceWord: "Mac")?.text
                == "On this Mac until the Drive is back")
        #expect(CopySummary(copies: takeCopies(running: false, driveOnly: true, device: .moved, drive: .repaired), dropoutCount: 0, deviceWord: "Mac").text
                == "Drive copy: Repaired · moved from this Mac")
    }
}
