import Foundation

/// When the app offers the 14-day Trial on its own: once, at launch, before any Trial or Pro, and never during a Take.
/// After that it is only in Settings.
public enum TrialOffer {
    /// The key that remembers the offer was made.
    public static let offeredKey = "trialOffered"

    /// - Parameters:
    ///   - proPrice: Pro's display price, nil until the App Store has it; the offer must name it (Guideline 3.1.1).
    ///   - anotherSheetOpen: Settings, the paywall or another sheet is up. The offer waits: presenting over them closed both (#357).
    public static func shouldOffer(purchases: ProPurchases, alreadyOffered: Bool, recording: Bool, proPrice: String?, anotherSheetOpen: Bool = false) -> Bool {
        !alreadyOffered && !recording && !anotherSheetOpen && proPrice != nil && !purchases.ownsPro && purchases.trialStartedAt == nil
    }
}
