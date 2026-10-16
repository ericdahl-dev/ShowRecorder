import Recording
import SwiftUI

/// The Pro section of Settings: the tier, Buy Pro and Restore Purchases. Calm and out of the way: no prompts, and
/// hidden during a Take (`SettingsLock`).
struct ProSection: View {
    @Bindable var model: RecordScreenModel

    private var store: ProStore { model.pro }
    /// Presented by the Settings Form, not this Section: a sheet on a lazily built Form row is torn down when the row
    /// is rebuilt, and took Settings with it (#357).
    @Binding var showingTrial: Bool
    @Binding var showingPaywall: Bool

    var body: some View {
        let license = store.planLicense()
        let tier = license.tier
        let purchases = store.purchases
        // What to offer (#705): the Armed family's pack and Pro, Pro alone, or only the upgrade for a pack owner.
        let items = tier == nil ? [] : PackOffer.items(
            ownsPro: purchases.ownsPro, armedFamily: model.armedFamily, ownedPacks: purchases.ownedPacks,
            boughtPacks: purchases.boughtPacks, packsOffered: PackAvailability.isAvailableInThisBuild)
        Section {
            LabeledContent("Plan", value: PackOffer.planTitle(tier: tier, ownsPro: purchases.ownsPro, ownedPacks: purchases.ownedPacks))
            if let tier, tier != .pro {
                Button("See what Pro adds") { showingPaywall = true }
            }
            if tier == .free, !license.trialStarted {
                Button("Start 14-day Trial…") { showingTrial = true }
            }
            if case .pack(let family)? = items.first {
                let product = store.packProducts[family]
                Button {
                    if let product { Task { await store.buy(product) } }
                } label: {
                    LabeledContent("Buy \(family.name) pack", value: priceText(product?.displayPrice))
                }
                .disabled(product == nil || store.busy)
            }
            if items.contains(.pro) {
                Button {
                    Task { await store.buyPro() }
                } label: {
                    LabeledContent("Buy Pro", value: priceText(store.proProduct?.displayPrice))
                }
                .disabled(store.proProduct == nil || store.busy)
            }
            if items.contains(.upgrade) {
                Button {
                    if let product = store.upgradeProduct { Task { await store.buy(product) } }
                } label: {
                    LabeledContent("Upgrade to Pro", value: priceText(store.upgradeProduct?.displayPrice))
                }
                .disabled(store.upgradeProduct == nil || store.busy)
            }
            // With the packs, Debug only for now (#705): Release shows no price-stage line until Eric turns it on.
            if PackAvailability.isAvailableInThisBuild, !items.isEmpty, let label = PriceStage.current.label {
                Text(label).font(.footnote).secondaryText()
            }
            Button("Restore Purchases") { Task { await store.restore() } }
                .disabled(store.busy)
            if let note = store.note {
                Text(note).font(.footnote).secondaryText()
            }
        } header: {
            Text("Pro")
        } footer: {
            Text(footer)
        }
    }

    private func priceText(_ price: String?) -> String {
        if let price { return price }
        return store.loadingProducts ? "Loading…" : "Price unavailable"
    }

    private var footer: String {
        switch store.planLicense().tier {
        case .pro: return "Thank you. Everything in Pro is yours."
        case nil: return "Your plan shows here once the App Store answers. Until then, nothing is limited."
        default: break
        }
        return "Free records every USB Channel on the Device. Pro is a one-time purchase, shared with your family. It adds names and colors from the Mixer, channel names you type, a second Copy on the Drive, unlimited Markers, the Show report, Reaper export, 96 kHz recording and Templates for each venue."
    }
}
