import Foundation
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
}
