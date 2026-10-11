import Foundation

/// One in-app purchase the App Store says this person has, their own or Family Shared. A plain copy of the
/// StoreKit transaction, so what it means can be decided and tested without StoreKit.
public struct OwnedPurchase: Equatable, Sendable {
    public var productID: String
    public var purchaseDate: Date
    /// Set when the purchase was refunded or revoked (such as leaving the family that shared it).
    public var revocationDate: Date?

    public init(productID: String, purchaseDate: Date, revocationDate: Date? = nil) {
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.revocationDate = revocationDate
    }
}

/// What the owned purchases mean for Pro and the Trial (ADR 0004).
public struct ProPurchases: Equatable, Sendable {
    /// The one-time Pro unlock: a non-consumable, Family Sharing on.
    public static let proProductID = "dev.ericdahl.ShowRecorder.pro"
    /// The 14-day Trial: a $0 non-consumable (App Review Guideline 3.1.1). Its purchase date starts the Trial.
    public static let trialProductID = "dev.ericdahl.ShowRecorder.trial"

    public private(set) var ownsPro = false
    public private(set) var trialStartedAt: Date?

    public init(owned: [OwnedPurchase]) {
        let owned = owned.filter { $0.revocationDate == nil }
        ownsPro = owned.contains { $0.productID == Self.proProductID }
        trialStartedAt = owned.first { $0.productID == Self.trialProductID }?.purchaseDate
    }

    private static let lastKnownProKey = "proPurchases.ownsPro"
    private static let lastKnownTrialKey = "proPurchases.trialStartedAt"

    private init(ownsPro: Bool, trialStartedAt: Date?) {
        self.ownsPro = ownsPro
        self.trialStartedAt = trialStartedAt
    }

    /// What was owned the last time the App Store was asked, kept on the device so a launch knows the tier at once
    /// (#316). Nil before the first answer (a fresh install or a new device).
    public static func lastKnown(from defaults: UserDefaults = .standard) -> ProPurchases? {
        guard defaults.object(forKey: lastKnownProKey) != nil else { return nil }
        return ProPurchases(ownsPro: defaults.bool(forKey: lastKnownProKey), trialStartedAt: defaults.object(forKey: lastKnownTrialKey) as? Date)
    }

    public func saveAsLastKnown(to defaults: UserDefaults = .standard) {
        defaults.set(ownsPro, forKey: Self.lastKnownProKey)
        defaults.set(trialStartedAt, forKey: Self.lastKnownTrialKey)
    }

    /// Free, Trial or Pro at `now`. Read when record is pressed, never awaited.
    public func tier(now: Date) -> Tier {
        Entitlement.tier(ownsPro: ownsPro, trialStartedAt: trialStartedAt, now: now)
    }
}
