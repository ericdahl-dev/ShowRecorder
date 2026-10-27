import Recording
import SwiftUI

/// The 14-day Trial offer: what it is, what Free keeps afterward and what Pro costs, before anything starts
/// (Guideline 3.1.1). Offered once at first launch and from Settings; "Not now" closes it with nothing changed.
struct TrialSheet: View {
    let store: ProStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let disclosure = store.trialDisclosure {
                    Section {
                        ForEach(disclosure.lines, id: \.self) { Text($0) }
                    }
                    Section {
                        Button("Start 14-day Trial") {
                            Task {
                                await store.startTrial()
                                if Self.trialStarted(store) { dismiss() }
                            }
                        }
                        .disabled(store.trialProduct == nil || store.busy)
                        if let note = store.note {
                            Text(note).font(.footnote).secondaryText()
                        }
                    }
                } else {
                    Text(store.loadingProducts ? "Loading…" : "The Trial isn't available right now.")
                        .secondaryText()
                }
            }
            .formStyle(.grouped)
            .navigationTitle("14-day Trial")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }

    /// Whether the Trial has started, so the sheet can close: the plan as owned, so a pack on the Armed family doesn't hide the Trial (#889).
    static func trialStarted(_ store: ProStore) -> Bool {
        if case .trial = store.planLicense().tier { true } else { false }
    }
}

/// What the days chip opens during a Trial (#743): what it includes, when it ends, what Free keeps after, and Buy Pro.
struct TrialStatusSheet: View {
    let store: ProStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if case .trial(let daysLeft) = Self.tier(store), let started = store.purchases.trialStartedAt {
                    let proPrice = store.proProduct?.displayPrice
                    let ends = Entitlement.trialEnd(startedAt: started).formatted(.dateTime.month(.wide).day())
                    // The upgrade or Pro (#962); either way the sheet closes once Pro is owned.
                    let upgrade = Self.offer(store) == .upgrade
                    let product = upgrade ? store.upgradeProduct : store.proProduct
                    Section {
                        ForEach(TrialStatusNotice(daysLeft: daysLeft, endsOn: ends, proPrice: product?.displayPrice, upgrade: upgrade).lines, id: \.self) { Text($0) }
                    }
                    let title = upgrade
                        ? product.map { "Upgrade to Pro, \($0.displayPrice)" } ?? "Upgrade to Pro"
                        : Paywall(moment: nil, proPrice: proPrice).buyTitle
                    Section {
                        Button(title) {
                            Task {
                                if !upgrade { await store.buyPro() } else if let product { await store.buy(product) }
                                if Self.tier(store) == .pro { dismiss() }
                            }
                        }
                        .disabled(product == nil || store.busy)
                        if let note = store.note {
                            Text(note).font(.footnote).secondaryText()
                        } else if product == nil {
                            Text(store.loadingProducts ? "Loading the price…" : "\(upgrade ? "The upgrade" : "Pro") isn't available right now.")
                                .font(.footnote).secondaryText()
                        }
                    }
                } else if Self.tier(store) == .pro {
                    Text("You have Pro.").secondaryText()
                } else {
                    Text("The Trial has ended. Free keeps recording every USB Channel.").secondaryText()
                }
            }
            .formStyle(.grouped)
            .navigationTitle("14-day Trial")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 360)
        #endif
    }

    /// The plan the sheet describes: the plan as owned, so a pack on the Armed family doesn't hide the Trial (#889).
    static func tier(_ store: ProStore) -> Tier? {
        store.planLicense().tier
    }

    /// What the sheet offers: the upgrade to someone who bought a pack, as the paywall and Settings do (#962); else Pro.
    static func offer(_ store: ProStore) -> PackOffer.Item { store.trialOffer }
}
