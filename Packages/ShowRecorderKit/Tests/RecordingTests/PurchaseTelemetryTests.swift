import Foundation
import MixerLink
import Telemetry
import Testing

@testable import Recording

/// Usage events from purchases (ADR 0007, #1026): trial_started and pro_bought, decided from what was owned before a
/// purchase and after it, so buying what is already owned sends nothing.
@Suite("Purchase telemetry")
struct PurchaseTelemetryTests {
    let day = Date(timeIntervalSince1970: 1_800_000_000)

    func owning(_ ids: String...) -> ProPurchases {
        ProPurchases(owned: ids.map { OwnedPurchase(productID: $0, purchaseDate: day) })
    }

    @Test("Starting the Trial sends trial_started")
    func trialStarted() {
        #expect(PurchaseTelemetry.events(before: owning(), after: owning(ProPurchases.trialProductID)) == [.trialStarted])
    }

    @Test("Buying Pro sends pro_bought, during a Trial too")
    func proBought() {
        #expect(PurchaseTelemetry.events(before: owning(), after: owning(ProPurchases.proProductID)) == [.proBought])
        #expect(PurchaseTelemetry.events(
            before: owning(ProPurchases.trialProductID),
            after: owning(ProPurchases.trialProductID, ProPurchases.proProductID)) == [.proBought])
    }

    @Test("A pack owner's upgrade to Pro sends pro_bought; a pack alone sends nothing")
    func upgradeAndPacks() throws {
        let pack = try #require(ProPurchases.packProductIDs[.xAir])
        #expect(PurchaseTelemetry.events(before: owning(), after: owning(pack)).isEmpty)
        #expect(PurchaseTelemetry.events(
            before: owning(pack), after: owning(pack, ProPurchases.upgradeProductID)) == [.proBought])
    }

    @Test("Buying what is already owned, or a purchase that changed nothing, sends nothing")
    func nothingNew() {
        let both = owning(ProPurchases.trialProductID, ProPurchases.proProductID)
        #expect(PurchaseTelemetry.events(before: both, after: both).isEmpty)
        #expect(PurchaseTelemetry.events(before: owning(), after: owning()).isEmpty)
    }
}
