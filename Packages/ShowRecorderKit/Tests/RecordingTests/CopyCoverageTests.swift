import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// What each Copy of a Take holds (#441). Audio one Copy lacks but another has is a Gap that Repair fills; only audio
/// lost from every Copy is a Dropout (#318).
@Suite("Copy coverage")
struct CopyCoverageTests {
    typealias Copy = CopyCoverage.Copy

    @Test("With one Copy, everything it dropped is a Dropout")
    func oneCopy() {
        let coverage = CopyCoverage([Copy(kind: .device, written: 1_000, dropped: [100..<200])])
        #expect(coverage.dropouts == [TakeMetadata.Dropout(copy: .device, start: 100, end: 200)])
        #expect(coverage.gaps(takeEnd: 1_000).isEmpty)
    }

    @Test("A stretch only the Drive dropped is a Gap in the Drive, not a Dropout")
    func onlyDrive() {
        let coverage = CopyCoverage([Copy(kind: .device, written: 1_000), Copy(kind: .drive, written: 1_000, dropped: [100..<200])])
        #expect(coverage.dropouts.isEmpty)
        #expect(coverage.gaps(takeEnd: nil) == [TakeMetadata.Gap(copy: .drive, start: 100, end: 200)])
    }

    @Test("Where both Copies dropped it's a Dropout in each; where only one did, a Gap in that one")
    func overlapping() {
        let coverage = CopyCoverage([
            Copy(kind: .device, written: 1_000, dropped: [150..<250]),
            Copy(kind: .drive, written: 1_000, dropped: [100..<200]),
        ])
        #expect(coverage.dropouts == [
            TakeMetadata.Dropout(copy: .device, start: 150, end: 200),
            TakeMetadata.Dropout(copy: .drive, start: 150, end: 200),
        ])
        #expect(coverage.gaps(takeEnd: nil) == [
            TakeMetadata.Gap(copy: .drive, start: 100, end: 150),
            TakeMetadata.Gap(copy: .device, start: 200, end: 250),
        ])
    }

    @Test("A Copy that wasn't recording yet (a Drive that joined late) doesn't have that audio: a drop there is a Dropout, and its silence is a Gap")
    func lateJoin() {
        let coverage = CopyCoverage([
            Copy(kind: .device, written: 1_000, dropped: [100..<200]),
            Copy(kind: .drive, written: 1_000, silence: [0..<150]),
        ])
        #expect(coverage.dropouts == [TakeMetadata.Dropout(copy: .device, start: 100, end: 150)])
        #expect(coverage.gaps(takeEnd: nil) == [
            TakeMetadata.Gap(copy: .drive, start: 0, end: 150),
            TakeMetadata.Gap(copy: .device, start: 150, end: 200),
        ])
    }

    @Test("A Copy that stopped early lacks everything after it: a Gap to the Take's end, once the end is known")
    func stoppedEarly() {
        let coverage = CopyCoverage([
            Copy(kind: .device, written: 1_000),
            Copy(kind: .drive, written: 400, stoppedEarly: true),
        ])
        #expect(coverage.gaps(takeEnd: nil).isEmpty, "while the Take runs its end isn't known")
        #expect(coverage.gaps(takeEnd: 1_000) == [TakeMetadata.Gap(copy: .drive, start: 400, end: 1_000)])
        #expect(coverage.gaps(takeEnd: 400).isEmpty)
    }

    @Test("A drop in the other Copy after a Copy stopped early is a Dropout: nothing has that audio")
    func dropAfterOtherStopped() {
        let coverage = CopyCoverage([
            Copy(kind: .device, written: 1_000, dropped: [300..<600]),
            Copy(kind: .drive, written: 400, stoppedEarly: true),
        ])
        #expect(coverage.dropouts == [TakeMetadata.Dropout(copy: .device, start: 400, end: 600)])
        #expect(coverage.gaps(takeEnd: 1_000) == [
            TakeMetadata.Gap(copy: .device, start: 300, end: 400),
            TakeMetadata.Gap(copy: .drive, start: 400, end: 1_000),
        ])
    }

    @Test("A cut-off Take: each Copy holds what is on disk, and the shorter one has a Gap up to the longer")
    func cutOff() {
        let coverage = CopyCoverage(stemLengths: [.device: 580, .drive: 300])
        #expect(coverage.end == 580)
        #expect(coverage.gaps(takeEnd: coverage.end) == [TakeMetadata.Gap(copy: .drive, start: 300, end: 580)])
        #expect(CopyCoverage(stemLengths: [.device: 580, .drive: 580]).gaps(takeEnd: 580).isEmpty)
    }
}
