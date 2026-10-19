import Recording
import SwiftUI

/// One paywall (#62): why it's here, what Pro adds, the price, the Show-Safe Promise, Buy and Restore. Never shown
/// during a Take; "Not now" closes it with nothing changed.
struct PaywallSheet: View {
    let store: ProStore
    let moment: ProOfferMoment?
    /// The linked Mixer's model while Mixer Link is up, for the pack headline (#705).
    let mixerModel: String?
    @Environment(\.dismiss) private var dismiss

    private var paywall: Paywall { Paywall(moment: moment, proPrice: store.proProduct?.displayPrice) }
    /// The pack first with Pro beside it, Pro alone, or only the upgrade (#705).
    private var items: [PackOffer.Item] {
        let purchases = store.purchases
        return PackOffer.items(
            ownsPro: purchases.ownsPro, armedFamily: store.armedFamily(), ownedPacks: purchases.ownedPacks,
            boughtPacks: purchases.boughtPacks, packsOffered: PackAvailability.isAvailableInThisBuild)
    }
    private var headline: String {
        PackOffer.paywallHeadline(items: items, mixerModel: mixerModel, moment: moment, paywall: paywall)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(paywall.features, id: \.self) { Label($0, systemImage: "checkmark") }
                } header: {
                    Text(headline).font(.title3.weight(.semibold)).textCase(nil)
                }
                Section {
                    Text(paywall.promise)
                }
                Section {
                    if case .pack(let family)? = items.first {
                        let product = store.packProducts[family]
                        Button(product.map { "Buy \(family.name) pack, \($0.displayPrice)" } ?? "Buy \(family.name) pack") {
                            guard let product else { return }
                            Task {
                                await store.buy(product)
                                // Closes only when the pack came through, not on a cancel (#705).
                                if store.purchases.ownedPacks.contains(family) { dismiss() }
                            }
                        }
                        .disabled(product == nil || store.busy)
                        Text(PackOffer.packFootnote(family: family)).font(.footnote).secondaryText()
                    }
                    if items.contains(.pro) {
                        Button(paywall.buyTitle) {
                            Task {
                                await store.buyPro()
                                // On Pro owned, not the tier: with a pack on the Armed family the tier is already Pro, and a
                                // cancel mustn't close the sheet (#705).
                                if store.purchases.ownsPro { dismiss() }
                            }
                        }
                        .disabled(store.proProduct == nil || store.busy)
                    }
                    if items.contains(.upgrade) {
                        let product = store.upgradeProduct
                        Button(product.map { "Upgrade to Pro, \($0.displayPrice)" } ?? "Upgrade to Pro") {
                            guard let product else { return }
                            Task {
                                await store.buy(product)
                                if store.purchases.ownsPro { dismiss() }
                            }
                        }
                        .disabled(product == nil || store.busy)
                    }
                    // The price stage under the offers, in every build (Eric, #705).
                    if !items.isEmpty, let label = PriceStage.current.label {
                        Text(label).font(.footnote).secondaryText()
                    }
                    Button("Restore Purchases") { Task { await store.restore() } }
                        .disabled(store.busy)
                    if let note = store.note {
                        Text(note).font(.footnote).secondaryText()
                    }
                } footer: {
                    Text(paywall.footnote)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Pro")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }
}

/// A paywall due to be shown: `moment` is why, nil when opened from Settings.
struct PaywallRequest: Identifiable, Equatable {
    let id = UUID()
    let moment: ProOfferMoment?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}
