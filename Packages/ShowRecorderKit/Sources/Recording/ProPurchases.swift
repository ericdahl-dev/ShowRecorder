import Foundation
import MixerLink

/// One in-app purchase the App Store says this person has, their own or Family Shared. A plain copy of the
/// StoreKit transaction, so what it means can be decided and tested without StoreKit.
public struct OwnedPurchase: Equatable, Sendable {
    public var productID: String
    public var purchaseDate: Date
    /// Set when the purchase was refunded or revoked (such as leaving the family that shared it).
    public var revocationDate: Date?
    /// Shared by a family member through Family Sharing, not bought by this person (#705).
    public var isFamilyShared: Bool

    public init(productID: String, purchaseDate: Date, revocationDate: Date? = nil, isFamilyShared: Bool = false) {
        self.productID = productID
        self.purchaseDate = purchaseDate
        self.revocationDate = revocationDate
        self.isFamilyShared = isFamilyShared
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
    /// The upgrade to Pro for a pack owner (#705): offered only to them, repriced at each price stage like Pro. Counts
    /// as Pro only while a pack is still owned, so refunding the pack takes it back (ADR 0004). Proposed ID, not yet in
    /// App Store Connect.
    public static let upgradeProductID = "dev.ericdahl.ShowRecorder.upgrade.pro"

    public private(set) var ownsPro = false
    public private(set) var trialStartedAt: Date?
    public private(set) var ownedPacks: Set<MixerFamily> = []
    /// The owned packs this person bought themselves, not shared through Family Sharing: only these earn the offer of
    /// the upgrade to Pro (Eric, #705), so nobody is sold an upgrade resting on a pack someone else can stop sharing.
    public private(set) var boughtPacks: Set<MixerFamily> = []

    public init(owned: [OwnedPurchase]) {
        let owned = owned.filter { $0.revocationDate == nil }
        ownsPro = owned.contains { $0.productID == Self.proProductID }
        trialStartedAt = owned.first { $0.productID == Self.trialProductID }?.purchaseDate
        ownedPacks = Set(Self.packProductIDs.filter { pack in owned.contains { $0.productID == pack.value } }.keys)
        boughtPacks = Set(Self.packProductIDs.filter { pack in owned.contains { $0.productID == pack.value && !$0.isFamilyShared } }.keys)
        // The upgrade is Pro only alongside a pack still owned (#705). One this person bought needs a pack they bought,
        // so refunding it can't lean on a family member's; one shared with them rests on any pack shared with them too.
        let ownsBought = !boughtPacks.isEmpty, ownsAny = !ownedPacks.isEmpty
        if owned.contains(where: { $0.productID == Self.upgradeProductID && ($0.isFamilyShared ? ownsAny : ownsBought) }) { ownsPro = true }
    }

    private static let lastKnownProKey = "proPurchases.ownsPro"
    private static let lastKnownTrialKey = "proPurchases.trialStartedAt"
    /// The owned packs as their product IDs, which stay the same when the code changes (#705). A device that saved
    /// before this key existed restores no packs.
    private static let lastKnownPacksKey = "proPurchases.ownedPacks"
    /// The packs among them bought by this person, not shared (#705), as product IDs too.
    private static let lastKnownBoughtPacksKey = "proPurchases.boughtPacks"

    private init(ownsPro: Bool, trialStartedAt: Date?, ownedPacks: Set<MixerFamily>, boughtPacks: Set<MixerFamily>) {
        self.ownsPro = ownsPro
        self.trialStartedAt = trialStartedAt
        self.ownedPacks = ownedPacks
        self.boughtPacks = boughtPacks
    }

    /// What was owned the last time the App Store was asked, kept on the device so a launch knows the tier at once
    /// (#316). Nil before the first answer (a fresh install or a new device).
    public static func lastKnown(from defaults: UserDefaults = .standard) -> ProPurchases? {
        guard defaults.object(forKey: lastKnownProKey) != nil else { return nil }
        func packs(_ key: String) -> Set<MixerFamily> {
            let ids = defaults.stringArray(forKey: key) ?? []
            return Set(packProductIDs.filter { ids.contains($0.value) }.keys)
        }
        return ProPurchases(
            ownsPro: defaults.bool(forKey: lastKnownProKey), trialStartedAt: defaults.object(forKey: lastKnownTrialKey) as? Date,
            ownedPacks: packs(lastKnownPacksKey), boughtPacks: packs(lastKnownBoughtPacksKey))
    }

    public func saveAsLastKnown(to defaults: UserDefaults = .standard) {
        defaults.set(ownsPro, forKey: Self.lastKnownProKey)
        defaults.set(trialStartedAt, forKey: Self.lastKnownTrialKey)
        defaults.set(ownedPacks.compactMap { Self.packProductIDs[$0] }.sorted(), forKey: Self.lastKnownPacksKey)
        defaults.set(boughtPacks.compactMap { Self.packProductIDs[$0] }.sorted(), forKey: Self.lastKnownBoughtPacksKey)
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
