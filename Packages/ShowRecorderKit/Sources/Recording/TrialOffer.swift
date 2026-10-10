import Foundation

/// When the app offers the 14-day Trial on its own: once, at launch, before any Trial or Pro, and never during a Take.
/// After that it is only in Settings.
public enum TrialOffer {
    /// The key that remembers the offer was made.
    public static let offeredKey = "trialOffered"

    /// - Parameter proPrice: Pro's display price, nil until the App Store has it; the offer must name it (Guideline 3.1.1).
    public static func shouldOffer(purchases: ProPurchases, alreadyOffered: Bool, recording: Bool, proPrice: String?) -> Bool {
        !alreadyOffered && !recording && proPrice != nil && !purchases.ownsPro && purchases.trialStartedAt == nil
    }
}
