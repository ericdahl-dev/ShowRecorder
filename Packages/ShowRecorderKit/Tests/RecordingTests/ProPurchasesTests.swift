import Foundation
import MixerLink
@testable import Recording
import Testing

/// What the App Store's current entitlements (own or Family Shared) mean for Pro and the Trial.
@Suite("Pro purchases")
struct ProPurchasesTests {
    let bought = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Nothing owned: no Pro and no Trial")
    func nothingOwned() {
        let owned = ProPurchases(owned: [])
        #expect(!owned.ownsPro)
        #expect(owned.trialStartedAt == nil)
    }

    @Test("Owning the Pro product is Pro, and no Trial")
    func pro() {
        let owned = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.proProductID, purchaseDate: bought)])
        #expect(owned.ownsPro)
        #expect(owned.trialStartedAt == nil)
    }

    @Test("Owning the Trial starts the Trial on its purchase date")
    func trial() {
        let owned = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: bought)])
        #expect(!owned.ownsPro)
        #expect(owned.trialStartedAt == bought)
    }

    @Test("A refunded or revoked purchase counts for nothing")
    func revoked() {
        let later = bought.addingTimeInterval(86_400)
        let owned = ProPurchases(owned: [
            OwnedPurchase(productID: ProPurchases.proProductID, purchaseDate: bought, revocationDate: later),
            OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: bought, revocationDate: later),
        ])
        #expect(!owned.ownsPro)
        #expect(owned.trialStartedAt == nil)
    }

    @Test("The tier follows from what is owned: a Trial bought 3 days ago has 11 days left; Pro beats the Trial")
    func tier() {
        let threeDaysOn = bought.addingTimeInterval(3 * 86_400)
        let trial = OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: bought)
        let pro = OwnedPurchase(productID: ProPurchases.proProductID, purchaseDate: bought)
        #expect(ProPurchases(owned: [trial]).tier(now: threeDaysOn) == .trial(daysLeft: 11))
        #expect(ProPurchases(owned: [trial, pro]).tier(now: threeDaysOn) == .pro)
        #expect(ProPurchases(owned: []).tier(now: threeDaysOn) == .free)
    }

    // MARK: - Mixer packs (#412, #705)

    func pack(_ family: MixerFamily, revoked: Bool = false) -> OwnedPurchase {
        OwnedPurchase(productID: ProPurchases.packProductIDs[family]!, purchaseDate: bought, revocationDate: revoked ? bought : nil)
    }

    @Test("A mixer pack is Pro while its family's interface is the Ready input; any other input, or none, stays Free (#412)")
    func packIsProForItsFamily() {
        let owned = ProPurchases(owned: [pack(.xAir)])
        #expect(owned.ownedPacks == [.xAir])
        #expect(!owned.ownsPro)
        #expect(owned.tier(now: bought, readyFamily: .xAir) == .pro)
        #expect(owned.tier(now: bought, readyFamily: .x32) == .free)
        #expect(owned.tier(now: bought, readyFamily: nil) == .free, "a generic interface needs full Pro")
        #expect(owned.tier(now: bought) == .free)
    }

    @Test("A refunded or revoked pack isn't owned (#412)")
    func revokedPack() {
        #expect(ProPurchases(owned: [pack(.x32, revoked: true)]).ownedPacks.isEmpty)
    }

    @Test("With a Trial running, a pack is Pro on its family and the Trial covers the rest; Pro covers every input (#412)")
    func packWithTrialAndPro() {
        let trial = OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: bought)
        let both = ProPurchases(owned: [pack(.xAir), trial])
        #expect(both.tier(now: bought, readyFamily: .xAir) == .pro)
        #expect(both.tier(now: bought, readyFamily: .x32) == .trial(daysLeft: 14))
        #expect(both.tier(now: bought.addingTimeInterval(30 * 86_400), readyFamily: .xAir) == .pro, "a pack doesn't depend on the Trial")
        let pro = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.proProductID, purchaseDate: bought)])
        #expect(pro.tier(now: bought, readyFamily: nil) == .pro)
    }

    // MARK: - The upgrade to Pro for a pack owner (#705)

    func upgrade() -> OwnedPurchase { OwnedPurchase(productID: ProPurchases.upgradeProductID, purchaseDate: bought) }

    @Test("A pack owner's upgrade is Pro on every input, while the pack is still owned (#705)")
    func upgradeIsPro() {
        let owned = ProPurchases(owned: [pack(.xAir), upgrade()])
        #expect(owned.ownsPro)
        #expect(owned.tier(now: bought, readyFamily: .x32) == .pro)
        #expect(owned.tier(now: bought, readyFamily: nil) == .pro)
    }

    @Test("The upgrade alone, or with its pack refunded, isn't Pro: refunding the pack takes the upgrade back (#705, ADR 0004)")
    func upgradeNeedsAPack() {
        #expect(!ProPurchases(owned: [upgrade()]).ownsPro)
        let refunded = ProPurchases(owned: [pack(.x32, revoked: true), upgrade()])
        #expect(!refunded.ownsPro)
        #expect(refunded.tier(now: bought, readyFamily: .x32) == .free)
    }

    @Test("A pack bought by this person is in boughtPacks; one shared through Family Sharing is owned but not bought (#705)")
    func boughtVersusShared() {
        let shared = OwnedPurchase(productID: ProPurchases.packProductIDs[.x32]!, purchaseDate: bought, isFamilyShared: true)
        let owned = ProPurchases(owned: [pack(.xAir), shared])
        #expect(owned.ownedPacks == [.xAir, .x32])
        #expect(owned.boughtPacks == [.xAir])
    }

    @Test("An upgrade bought by this person needs a pack they bought: refunding it can't lean on a family member's pack (#705)")
    func boughtUpgradeNeedsBoughtPack() {
        let sharedPack = OwnedPurchase(productID: ProPurchases.packProductIDs[.x32]!, purchaseDate: bought, isFamilyShared: true)
        #expect(!ProPurchases(owned: [pack(.xAir, revoked: true), sharedPack, upgrade()]).ownsPro)
    }

    @Test("An upgrade shared through Family Sharing rests on the shared pack: the family keeps Pro (#705)")
    func sharedUpgradeWithSharedPack() {
        let sharedPack = OwnedPurchase(productID: ProPurchases.packProductIDs[.xAir]!, purchaseDate: bought, isFamilyShared: true)
        let sharedUpgrade = OwnedPurchase(productID: ProPurchases.upgradeProductID, purchaseDate: bought, isFamilyShared: true)
        #expect(ProPurchases(owned: [sharedPack, sharedUpgrade]).ownsPro)
    }
}
