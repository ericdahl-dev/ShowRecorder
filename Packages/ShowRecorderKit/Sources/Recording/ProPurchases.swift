import Foundation
import MixerLink

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
    /// Mixer packs (#412): each unlocks Pro while its family's interface is the Armed input. Proposed IDs, not yet
    /// created in App Store Connect (#705); the DJM pack waits for DJM support (#364).
    public static let packProductIDs: [MixerFamily: String] = [.xAir: "dev.ericdahl.ShowRecorder.pack.xair", .x32: "dev.ericdahl.ShowRecorder.pack.x32"]

    public private(set) var ownsPro = false
    public private(set) var trialStartedAt: Date?
    public private(set) var ownedPacks: Set<MixerFamily> = []

    public init(owned: [OwnedPurchase]) {
        let owned = owned.filter { $0.revocationDate == nil }
        ownsPro = owned.contains { $0.productID == Self.proProductID }
        trialStartedAt = owned.first { $0.productID == Self.trialProductID }?.purchaseDate
        ownedPacks = Set(Self.packProductIDs.filter { pack in owned.contains { $0.productID == pack.value } }.keys)
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
        tier(now: now, armedFamily: nil)
    }

    /// Free, Trial or Pro at `now` with `armedFamily`'s interface as the Armed input (nil for any other input): a
    /// mixer pack is Pro only on its own family (ADR 0004, #412).
    public func tier(now: Date, armedFamily: MixerFamily?) -> Tier {
        if ownsPro || armedFamily.map(ownedPacks.contains) == true { return .pro }
        return Entitlement.tier(ownsPro: false, trialStartedAt: trialStartedAt, now: now)
    }
}
