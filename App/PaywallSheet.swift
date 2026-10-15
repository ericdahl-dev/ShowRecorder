import Recording
import SwiftUI

/// One paywall (#62): why it's here, what Pro adds, the price, the Show-Safe Promise, Buy and Restore. Never shown
/// during a Take; "Not now" closes it with nothing changed.
struct PaywallSheet: View {
    let store: ProStore
    let moment: ProOfferMoment?
    @Environment(\.dismiss) private var dismiss

    private var paywall: Paywall { Paywall(moment: moment, proPrice: store.proProduct?.displayPrice) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(paywall.features, id: \.self) { Label($0, systemImage: "checkmark") }
                } header: {
                    Text(paywall.headline).font(.title3.weight(.semibold)).textCase(nil)
                }
                Section {
                    Text(paywall.promise)
                }
                Section {
                    Button(paywall.buyTitle) {
                        Task {
                            await store.buyPro()
                            if store.license().tier == .pro { dismiss() }
                        }
                    }
                    .disabled(store.proProduct == nil || store.busy)
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
