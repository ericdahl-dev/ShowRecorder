import Foundation
import MixerLink

/// Where mixer packs (#705) are offered: Debug builds only, never TestFlight or the App Store until Eric tries packs
/// on a device. Moving it up is a one-line PR, like `DriveOnlyAvailability`.
public enum PackAvailability {
    public static func isAvailable(isDebugBuild: Bool) -> Bool {
        isDebugBuild
    }

    /// The answer for the running app.
    public static var isAvailableInThisBuild: Bool {
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return isAvailable(isDebugBuild: isDebugBuild)
    }
}

/// What the paywall offers with mixer packs (#705): the Armed family's pack first with Pro beside it, Pro alone for
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
        ownsPro: Bool, armedFamily: MixerFamily?, ownedPacks: Set<MixerFamily>, boughtPacks: Set<MixerFamily>, packsOffered: Bool
    ) -> [Item] {
        if ownsPro { return [] }
        if !packsOffered { return [.pro] }
        if !boughtPacks.isEmpty { return [.upgrade] }
        // A second pack is hidden (Eric): with only a shared pack, the offer is full Pro.
        if !ownedPacks.isEmpty { return [.pro] }
        if let armedFamily, ProPurchases.packProductIDs[armedFamily] != nil { return [.pack(armedFamily), .pro] }
        return [.pro]
    }

    /// How Settings names the plan (#705): a pack owner's plan is their pack ("X Air pack"), unless Pro is owned or a
    /// Trial is running, which say more. Pass the tier without the Armed family (`license(proOffered:now:)`), so the
    /// line doesn't change with the input and a running Trial isn't hidden by a pack on the Armed family.
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
/// ($9.99, $4.99, $4.99), then Full ($19.99, $7.99, $11.99). StoreKit gives only today's price, so the stage is set here
/// and moved by a one-line PR when App Store Connect's prices move.
public enum PriceStage: Equatable, Sendable {
    case launch, step2, full

    /// The stage the App Store prices are at now.
    public static let current = PriceStage.launch

    /// What the paywall says beside the price: "Launch price" at the Launch stage only, never a countdown.
    public var label: String? { self == .launch ? "Launch price" : nil }
}
