import Destinations
import Foundation
@testable import Recording
import TakeFile
import Testing

/// Audio one Copy dropped but another has is a Gap that Repair fills; only audio lost from every Copy is a
/// Dropout (#318).
@Suite("Dropout or Gap")
struct DropoutSplitTests {
    @Test("With one Copy, everything it dropped is a Dropout")
    func oneCopy() {
        let split = DropoutSplit(dropped: [.device: [100..<200]], notRecording: [:])
        #expect(split.dropouts == [TakeMetadata.Dropout(copy: .device, start: 100, end: 200)])
        #expect(split.gaps.isEmpty)
    }

    @Test("A stretch only the Drive dropped is a Gap in the Drive, not a Dropout")
    func onlyDrive() {
        let split = DropoutSplit(dropped: [.device: [], .drive: [100..<200]], notRecording: [:])
        #expect(split.dropouts.isEmpty)
        #expect(split.gaps == [TakeMetadata.Gap(copy: .drive, start: 100, end: 200)])
    }

    @Test("Where both Copies dropped it's a Dropout in each; where only one did, a Gap in that one")
    func overlapping() {
        let split = DropoutSplit(dropped: [.device: [150..<250], .drive: [100..<200]], notRecording: [:])
        #expect(split.dropouts == [
            TakeMetadata.Dropout(copy: .device, start: 150, end: 200),
            TakeMetadata.Dropout(copy: .drive, start: 150, end: 200),
        ])
        #expect(split.gaps == [
            TakeMetadata.Gap(copy: .drive, start: 100, end: 150),
            TakeMetadata.Gap(copy: .device, start: 200, end: 250),
        ])
    }

    @Test("A Copy that wasn't recording yet (a Drive that joined late) doesn't have that audio: a drop there is a Dropout")
    func otherNotRecording() {
        let split = DropoutSplit(dropped: [.device: [100..<200], .drive: []], notRecording: [.drive: [0..<150]])
        #expect(split.dropouts == [TakeMetadata.Dropout(copy: .device, start: 100, end: 150)])
        #expect(split.gaps == [TakeMetadata.Gap(copy: .device, start: 150, end: 200)])
    }
}
