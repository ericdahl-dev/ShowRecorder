import Foundation
import Recording
import Testing
@testable import ShowRecorder

/// The Trial sheets for someone who owns a mixer pack (#889): with that family's Mixer Armed the pack counts as Pro at
/// record, but the sheets describe the plan as owned.
@MainActor
struct TrialSheetTests {
    /// Owns the X Air pack and has just started the Trial, with an XR18 Armed.
    func packOwnerInTrial() -> ProStore {
        let now = Date()
        let store = ProStore(status: ProStatus(lastKnown: ProPurchases(owned: [
            OwnedPurchase(productID: ProPurchases.packProductIDs[.xAir]!, purchaseDate: now.addingTimeInterval(-86_400)),
            OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: now),
        ])))
        store.armedFamily = { .xAir }
        return store
    }

    @Test func packOwnerStartingTheTrialSeesTheSheetClose() {
        #expect(TrialSheet.trialStarted(packOwnerInTrial()))
    }

    @Test func packOwnerInTheTrialSeesATrialNotPro() {
        let tier = TrialStatusSheet.tier(packOwnerInTrial())
        guard case .trial = tier else {
            Issue.record("the status sheet reads \(String(describing: tier)), not a Trial")
            return
        }
    }

    @Test func packOwnerInTheTrialSeesTheDaysChip() {
        #expect(packOwnerInTrial().trialChip != nil, "the chip opens the Trial status sheet")
    }

    @Test func packOwnerWithoutATrialIsNotToldTheyHavePro() {
        let store = ProStore(status: ProStatus(lastKnown: ProPurchases(owned: [
            OwnedPurchase(productID: ProPurchases.packProductIDs[.xAir]!, purchaseDate: Date()),
        ])))
        store.armedFamily = { .xAir }
        #expect(TrialStatusSheet.tier(store) == .free)
    }
}
