import Foundation
@testable import Recording
import Testing

/// The 2 USB Channels the operator chose to record on Free, kept between launches.
@Suite("Free channel choice")
struct FreeChannelChoiceTests {
    func freshDefaults() -> UserDefaults {
        let name = "FreeChannelChoiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Nothing chosen yet: USB Channels 1 and 2")
    func defaultChoice() {
        #expect(FreeChannelChoice.load(from: freshDefaults()) == [1, 2])
    }

    @Test("A saved choice comes back on the next launch")
    func roundTrip() {
        let defaults = freshDefaults()
        FreeChannelChoice.save([5, 9], to: defaults)
        #expect(FreeChannelChoice.load(from: defaults) == [5, 9])
    }

    @Test("Something unreadable stored is ignored: the default, or the valid channels in it")
    func junk() {
        let defaults = freshDefaults()
        defaults.set("1,2", forKey: FreeChannelChoice.key)
        #expect(FreeChannelChoice.load(from: defaults) == [1, 2])
        defaults.set([0, -3, 7], forKey: FreeChannelChoice.key)
        #expect(FreeChannelChoice.load(from: defaults) == [7])
    }

    @Test("Picking a channel for one of the 2 slots replaces it; picking the other slot's channel swaps them, so the 2 stay different")
    func picking() {
        #expect(FreeChannelChoice.picking(9, slot: 0, in: [1, 2]) == [9, 2])
        #expect(FreeChannelChoice.picking(9, slot: 1, in: [1, 2]) == [1, 9])
        #expect(FreeChannelChoice.picking(2, slot: 0, in: [1, 2]) == [2, 1])
        #expect(FreeChannelChoice.picking(1, slot: 0, in: [1, 2]) == [1, 2])
    }
}
