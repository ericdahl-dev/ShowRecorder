import Foundation
import Recording
import Testing
@testable import ShowRecorder

/// The between-Takes "Trial ending soon" note (#961): it reads the plan as owned, so a pack on the Ready family doesn't
/// hide the Trial's last days.
@MainActor
struct TrialNoteTests {
    /// A store owning `extra` plus a Trial started 13 days ago, with an XR18 Ready.
    func store(owning extra: [String] = [], trial: Bool = true) -> ProStore {
        let now = Date()
        var owned = extra.map { OwnedPurchase(productID: $0, purchaseDate: now.addingTimeInterval(-20 * 86_400)) }
        if trial { owned.append(OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: now.addingTimeInterval(-13 * 86_400))) }
        let store = ProStore(status: ProStatus(lastKnown: ProPurchases(owned: owned)))
        store.readyFamily = { .xAir }
        return store
    }

    func note(_ pro: ProStore) -> ProOfferMoment? {
        var offers = ProOffers(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return RecordScreenModel.trialNote(&offers, show: "Friday", pro: pro, isRecording: false)
    }

    @Test func packOwnerInTheTrialsLastDaysSeesTheNote() {
        let moment = note(store(owning: [ProPurchases.packProductIDs[.xAir]!]))
        guard case .trialEndingSoon = moment else {
            Issue.record("no Trial note: \(String(describing: moment))")
            return
        }
    }

    @Test func trialWithoutAPackStillSeesTheNote() {
        let moment = note(store())
        guard case .trialEndingSoon = moment else {
            Issue.record("no Trial note: \(String(describing: moment))")
            return
        }
    }

    @Test func proOwnerNeverSeesTheNote() {
        #expect(note(store(owning: [ProPurchases.proProductID])) == nil)
    }
}
