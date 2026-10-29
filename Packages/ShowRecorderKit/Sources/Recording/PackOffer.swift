import Foundation
import MixerLink

/// Where mixer packs (#705) are offered: Debug builds only, never TestFlight or the App Store until Eric tries packs
/// on a device. Moving it up is a one-line PR, like `DriveOnlyAvailability`.
public enum PackAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugOnly

    public static func isAvailable(isDebugBuild: Bool) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: nil)
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}

/// What the paywall offers with mixer packs (#705): the Ready family's pack first with Pro beside it, Pro alone for
/// a generic input, and only the upgrade for someone who already has a pack (a second pack is hidden, Eric 2026-10-16).
public enum PackOffer {
    public enum Item: Equatable, Sendable {
        case pack(MixerFamily)
        case pro
        case upgrade
    }

    /// - Parameter boughtPacks: the owned packs this person bought themselves; a pack only shared with them through
    ///   Family Sharing doesn't earn the upgrade, so they're offered full Pro (Eric, #705).
    public static func items(
        ownsPro: Bool, readyFamily: MixerFamily?, ownedPacks: Set<MixerFamily>, boughtPacks: Set<MixerFamily>, packsOffered: Bool
    ) -> [Item] {
        if ownsPro { return [] }
        if !packsOffered { return [.pro] }
        if !boughtPacks.isEmpty { return [.upgrade] }
        // A second pack is hidden (Eric): with only a shared pack, the offer is full Pro.
        if !ownedPacks.isEmpty { return [.pro] }
        if let readyFamily, ProPurchases.packProductIDs[readyFamily] != nil { return [.pack(readyFamily), .pro] }
        return [.pro]
    }

    /// How Settings names the plan (#705): a pack owner's plan is their pack ("X Air pack"), unless Pro is owned or a
    /// Trial is running, which say more. Pass the tier without the Ready family (`license(proOffered:now:)`), so the
    /// line doesn't change with the input and a running Trial isn't hidden by a pack on the Ready family.
    public static func planTitle(tier: Tier?, ownsPro: Bool, ownedPacks: Set<MixerFamily>) -> String {
        guard let tier else { return "Checking with the App Store…" }
        if ownsPro { return Tier.pro.title }
        if case .trial = tier { return tier.title }
        if let pack = ownedPacks.sorted(by: { $0.name < $1.name }).first { return "\(pack.name) pack" }
        return tier.title
    }

    /// What Restore Purchases says once the App Store has synced (#705): nothing when Pro came back, the pack when only
    /// a pack did, else that no purchase was found.
    public static func restoreNote(ownsPro: Bool, ownedPacks: Set<MixerFamily>) -> String? {
        if ownsPro { return nil }
        if let pack = ownedPacks.sorted(by: { $0.name < $1.name }).first { return "Restored: \(pack.name) pack" }
        return "No purchase found for this Apple Account."
    }

    /// The pack headline (#705): the linked Mixer's model, else the family's name.
    public static func headline(family: MixerFamily, mixerModel: String?) -> String {
        let model = mixerModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "Pro for your \(model.isEmpty ? family.name : model)"
    }

    /// Under the pack offer (#705): the pack covers one family, Pro every audio interface.
    public static func packFootnote(family: MixerFamily) -> String {
        "The \(family.name) pack is Pro while an \(family.models.joined(separator: " or ")) is the audio interface. Pro covers every one."
    }

    /// The Settings footer for a pack owner (#705), in place of Free's; nil without a pack. Only a bought pack is offered
    /// the upgrade (`items`); a pack shared through Family Sharing is offered full Pro.
    public static func ownerFooter(ownedPacks: Set<MixerFamily>, boughtPacks: Set<MixerFamily>) -> String? {
        // A bought pack first: it's the one the upgrade rests on.
        let byName: (MixerFamily, MixerFamily) -> Bool = { $0.name < $1.name }
        guard let pack = boughtPacks.intersection(ownedPacks).sorted(by: byName).first ?? ownedPacks.sorted(by: byName).first else { return nil }
        let rest = boughtPacks.isEmpty ? "Pro covers every one." : "Upgrade to Pro for every one."
        return "Your \(pack.name) pack is Pro while an \(pack.models.joined(separator: " or ")) is the audio interface. \(rest)"
    }

    /// The paywall's headline (#705): a running Trial's line first, with the pack or the upgrade offered below it (Eric);
    /// else the pack's, then the upgrade's, then the moment's. The Trial's line is the `.trialEndingSoon` moment's; opened
    /// from Settings (no moment), the offer's headline shows during a Trial too.
    public static func paywallHeadline(items: [Item], mixerModel: String?, moment: ProOfferMoment?, paywall: Paywall) -> String {
        if case .trialEndingSoon = moment { return paywall.headline }
        if case .pack(let family)? = items.first { return headline(family: family, mixerModel: mixerModel) }
        return upgradeHeadline(items: items) ?? paywall.headline
    }

    /// The paywall headline when the only offer is the upgrade (#705); nil otherwise.
    public static func upgradeHeadline(items: [Item]) -> String? {
        items == [.upgrade] ? "Pro on every audio interface" : nil
    }
}

extension MixerFamily {
    /// The family's name in copy: "X Air", "X32" (#705).
    public var name: String {
        switch self {
        case .xAir: "X Air"
        case .x32: "X32"
        }
    }

    /// The models the family's pack covers, in copy: "XR18", "MR18" (#705).
    public var models: [String] {
        switch self {
        case .xAir: ["XR18", "MR18"]
        case .x32: ["X32", "M32"]
        }
    }
}

/// Where the launch price ladder stands (Eric, 2026-10-15, #705): Launch (Pro $4.99, packs $2.99, upgrade $1.99), Step 2
/// ($9.99, $4.99, $4.99), then Full ($19.99, $7.99, $11.99). The stage follows Pro's live StoreKit price (Eric, #908), so
/// a price step in App Store Connect hides "Launch price" in installed copies without an update.
public enum PriceStage {
    /// What the paywall says beside the price: "Launch price" while Pro's live price is its launch price in that
    /// currency, never a countdown. Nil while the price is loading, after a price step, or in a currency not listed.
    public static func label(proPrice: Decimal?, currencyCode: String?) -> String? {
        guard let proPrice, let currencyCode,
              launchProPrices[currencyCode]?.contains(where: { Decimal(string: $0) == cents(proPrice) }) == true else { return nil }
        return "Launch price"
    }

    /// The price to the cent: StoreKit's Decimal can carry float residue (4.9900000000000002). Every listed price is whole cents.
    private static func cents(_ price: Decimal) -> Decimal {
        var price = price, rounded = Decimal()
        NSDecimalRound(&rounded, &price, 2, .plain)
        return rounded
    }

    /// Pro's launch price in each App Store currency, as App Store Connect equalized the $4.99 US price
    /// (read 2026-10-21; some territories in one currency differ, so a currency can list two). StoreKit gives no price
    /// tier, so a price outside this list, from a price step or Apple re-equalizing a territory, hides the label.
    static let launchProPrices: [String: [String]] = [
        "AED": ["19.99"], "AUD": ["7.99"], "BRL": ["29.9"], "CAD": ["6.99"],
        "CHF": ["4"], "CLP": ["5990"], "CNY": ["38"], "COP": ["24900"],
        "CZK": ["129"], "DKK": ["39"], "EGP": ["249.99"], "EUR": ["4.99", "5.99"],
        "GBP": ["4.99"], "HKD": ["38"], "HUF": ["1990"], "IDR": ["99000"],
        "ILS": ["14.9"], "INR": ["499"], "JPY": ["800"], "KRW": ["7700"],
        "KZT": ["2990"], "MXN": ["99"], "MYR": ["22.9"], "NGN": ["7900"],
        "NOK": ["59"], "NZD": ["9.99"], "PEN": ["22.9"], "PHP": ["299"],
        "PKR": ["1300"], "PLN": ["24.99"], "QAR": ["19.99"], "RON": ["29.99"],
        "RUB": ["449"], "SAR": ["19.99"], "SEK": ["69"], "SGD": ["6.98"],
        "THB": ["199"], "TRY": ["249.99"], "TWD": ["150"], "TZS": ["14900"],
        "USD": ["4.99", "5.99"], "VND": ["149000"], "ZAR": ["99.99"],
    ]
}
