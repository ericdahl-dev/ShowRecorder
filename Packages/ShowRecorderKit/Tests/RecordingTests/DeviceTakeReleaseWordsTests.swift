import Foundation
@testable import Recording
import Testing

/// Drive only (#656): what the confirmation for deleting a kept Take from the Device says. It names exactly what goes and what
/// stays, calmly, and says it can't be undone on this device.
@Suite("Deleting a kept Take: the words")
struct DeviceTakeReleaseWordsTests {
    func summary(stems: Int = 2, standIns: Bool = false, longest: Double = 83, shortest: Double = 45) -> DeviceTakeRelease.Summary {
        .init(take: 3, channels: 2, stems: stems, holdsStandIns: standIns, longestSeconds: longest, shortestSeconds: shortest)
    }

    @Test("The title names the Take and this device")
    func title() {
        #expect(summary().title(deviceWord: "iPhone") == "Delete Take 03 from this iPhone?")
        #expect(summary().title(deviceWord: "Mac") == "Delete Take 03 from this Mac?")
    }

    @Test("The message says what the Drive holds, what goes, that the Drive Copy stays, and that it can't be undone")
    func message() {
        #expect(summary().message(deviceWord: "iPhone") ==
            "The Drive holds everything this iPhone holds of Take 03: 2 Stems, the longest 1:23 and the shortest 0:45. "
            + "Deleting removes those 2 Stems from this iPhone. The Drive copy stays. This can't be undone on this iPhone.")
    }

    @Test("One Stem, equal lengths, and parts held for the Drive")
    func variants() {
        let one = summary(stems: 1, longest: 60, shortest: 60).message(deviceWord: "iPhone")
        #expect(one.contains("1 Stem, 1:00 long."))
        #expect(one.contains("removes that Stem"))
        #expect(summary(stems: 3, longest: 60, shortest: 60).message(deviceWord: "iPhone").contains("3 Stems, each 1:00 long."))
        #expect(summary(standIns: true).message(deviceWord: "iPhone").contains(
            "2 Stems, including what this iPhone recorded while the Drive was away, the longest 1:23 and the shortest 0:45."))
    }

    @Test("Hours roll over; the words use no em dash or exclamation point")
    func formatting() {
        #expect(summary(longest: 3_725, shortest: 3_725).message(deviceWord: "iPad").contains("1:02:05"))
        let all = summary().message(deviceWord: "iPhone") + summary().title(deviceWord: "iPhone")
        #expect(!all.contains("—") && !all.contains("!"))
    }
}
