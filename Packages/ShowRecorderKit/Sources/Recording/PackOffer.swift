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

    /// The pack headline (#705): the linked Mixer's model, else the family's name.
    public static func headline(family: MixerFamily, mixerModel: String?) -> String {
        let model = mixerModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "Pro for your \(model.isEmpty ? family.name : model)"
    }
}

extension MixerFamily {
    /// The family's name in the paywall (#705).
    var name: String {
        switch self {
        case .xAir: "X Air"
        case .x32: "X32"
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
