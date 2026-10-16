import Foundation
import MixerLink
@testable import Recording
import Testing

/// Before the App Store has said what's owned, nothing is limited, and the last known tier is kept on the device so
/// later launches know it at once (#316, Show-Safe Promise).
@Suite("Unknown tier")
struct UnknownTierTests {
    @Test("What was owned is kept on the device: nothing before the first look, then the last one seen")
    func lastKnown() {
        let defaults = UserDefaults(suiteName: "UnknownTierTests-\(UUID().uuidString)")!
        #expect(ProPurchases.lastKnown(from: defaults) == nil)
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let trial = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: started)])
        trial.saveAsLastKnown(to: defaults)
        #expect(ProPurchases.lastKnown(from: defaults) == trial)
        let pro = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.proProductID, purchaseDate: started)])
        pro.saveAsLastKnown(to: defaults)
        #expect(ProPurchases.lastKnown(from: defaults)?.ownsPro == true)
    }

    @Test("Owned mixer packs are kept on the device too, so a pack owner's first record press after launch isn't Free (#705)")
    func lastKnownPacks() {
        let defaults = UserDefaults(suiteName: "UnknownTierTests-\(UUID().uuidString)")!
        let bought = Date(timeIntervalSince1970: 1_800_000_000)
        let packs = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.packProductIDs[.xAir]!, purchaseDate: bought)])
        packs.saveAsLastKnown(to: defaults)
        #expect(ProPurchases.lastKnown(from: defaults) == packs)
        #expect(ProPurchases.lastKnown(from: defaults)?.tier(now: bought, armedFamily: .xAir) == .pro)
    }

    @Test("The App Store's answer counts as a change when a pack is bought or refunded, though Pro and the Trial didn't move (#705)")
    func packChangeIsAChange() {
        let bought = Date(timeIntervalSince1970: 1_800_000_000)
        let pack = OwnedPurchase(productID: ProPurchases.packProductIDs[.x32]!, purchaseDate: bought)
        var status = ProStatus(lastKnown: ProPurchases(owned: []))
        let bought1 = status.appStoreAnswered([pack], now: bought)
        let again = status.appStoreAnswered([pack], now: bought)
        let refunded = status.appStoreAnswered([], now: bought)
        #expect(bought1)
        #expect(!again, "the same answer again is no change")
        #expect(refunded)
    }
}
