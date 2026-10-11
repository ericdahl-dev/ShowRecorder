import Foundation
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
}
