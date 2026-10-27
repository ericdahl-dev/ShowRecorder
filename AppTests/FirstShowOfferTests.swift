import Foundation
import Recording
import Testing
@testable import ShowRecorder

/// The offer when the first Show ends (#969): it reads the plan as owned, so a pack owner whose pack's mixer was
/// Armed still gets it, with the upgrade.
@MainActor
struct FirstShowOfferTests {
    func store(owning ids: [String]) -> ProStore {
        let owned = ids.map { OwnedPurchase(productID: $0, purchaseDate: Date().addingTimeInterval(-86_400)) }
        let store = ProStore(status: ProStatus(lastKnown: ProPurchases(owned: owned)))
        store.armedFamily = { .xAir }
        return store
    }

    func offer(_ pro: ProStore) -> ProOfferMoment? {
        var offers = ProOffers(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return RecordScreenModel.firstShowOffer(&offers, show: "Friday", takeCount: 3, pro: pro)
    }

    @Test func packOwnerGetsTheFirstShowOfferWithTheUpgrade() {
        let pro = store(owning: [ProPurchases.packProductIDs[.xAir]!])
        #expect(offer(pro) == .firstShowEnded)
        let purchases = pro.purchases
        #expect(PackOffer.items(
            ownsPro: purchases.ownsPro, armedFamily: .xAir, ownedPacks: purchases.ownedPacks,
            boughtPacks: purchases.boughtPacks, packsOffered: PackAvailability.isAvailableInThisBuild) == [.upgrade],
            "the paywall it opens offers the upgrade")
    }

    @Test func proOwnerNeverGetsIt() {
        #expect(offer(store(owning: [ProPurchases.proProductID])) == nil)
    }

    @Test func freeUserStillGetsIt() {
        #expect(offer(store(owning: [])) == .firstShowEnded)
    }
}
