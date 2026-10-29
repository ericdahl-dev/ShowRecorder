import Foundation
import Recording
import Testing
@testable import ShowRecorder

/// The Trial sheets for someone who owns a mixer pack (#889): with that family's Mixer Ready the pack counts as Pro at
/// record, but the sheets describe the plan as owned.
@MainActor
struct TrialSheetTests {
    /// Owns the X Air pack and has just started the Trial, with an XR18 Ready.
    func packOwnerInTrial() -> ProStore {
        let now = Date()
        let store = ProStore(status: ProStatus(lastKnown: ProPurchases(owned: [
            OwnedPurchase(productID: ProPurchases.packProductIDs[.xAir]!, purchaseDate: now.addingTimeInterval(-86_400)),
            OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: now),
        ])))
        store.readyFamily = { .xAir }
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
        store.readyFamily = { .xAir }
        #expect(TrialStatusSheet.tier(store) == .free)
    }

    /// What the status sheet offers (#962): the upgrade to someone who bought a pack, as the paywall and Settings do.
    @Test func packOwnerInTheTrialIsOfferedTheUpgrade() {
        #expect(TrialStatusSheet.offer(packOwnerInTrial()) == .upgrade)
    }

    /// What the Trial sheet's disclosure names before the Trial starts (#972): the same offer as the status sheet.
    @Test func packOwnerBeforeTheTrialIsToldTheUpgrade() {
        let store = ProStore(status: ProStatus(lastKnown: ProPurchases(owned: [
            OwnedPurchase(productID: ProPurchases.packProductIDs[.xAir]!, purchaseDate: Date().addingTimeInterval(-86_400)),
        ])))
        #expect(store.trialOffer == .upgrade)
    }

    @Test func noPackBeforeTheTrialIsToldFullPro() {
        #expect(ProStore(status: ProStatus(lastKnown: ProPurchases(owned: []))).trialOffer == .pro)
    }

    @Test func trialWithoutAPackIsOfferedPro() {
        let store = ProStore(status: ProStatus(lastKnown: ProPurchases(owned: [
            OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: Date()),
        ])))
        #expect(TrialStatusSheet.offer(store) == .pro)
    }

    @Test func trialWithOnlyASharedPackIsOfferedPro() {
        let now = Date()
        let store = ProStore(status: ProStatus(lastKnown: ProPurchases(owned: [
            OwnedPurchase(productID: ProPurchases.packProductIDs[.xAir]!, purchaseDate: now.addingTimeInterval(-86_400), isFamilyShared: true),
            OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: now),
        ])))
        #expect(TrialStatusSheet.offer(store) == .pro)
    }
}
