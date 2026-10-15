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
                                if case .trial = store.license().tier { dismiss() }
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
}

/// What the days chip opens during a Trial (#743): what it includes, when it ends, what Free keeps after, and Buy Pro.
struct TrialStatusSheet: View {
    let store: ProStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if case .trial(let daysLeft) = store.license().tier, let started = store.purchases.trialStartedAt {
                    let proPrice = store.proProduct?.displayPrice
                    let ends = Entitlement.trialEnd(startedAt: started).formatted(.dateTime.month(.wide).day())
                    Section {
                        ForEach(TrialStatusNotice(daysLeft: daysLeft, endsOn: ends, proPrice: proPrice).lines, id: \.self) { Text($0) }
                    }
                    Section {
                        Button(Paywall(moment: nil, proPrice: proPrice).buyTitle) {
                            Task {
                                await store.buyPro()
                                if store.license().tier == .pro { dismiss() }
                            }
                        }
                        .disabled(store.proProduct == nil || store.busy)
                        if let note = store.note {
                            Text(note).font(.footnote).secondaryText()
                        } else if store.proProduct == nil {
                            Text(store.loadingProducts ? "Loading the price…" : "Pro isn't available right now.")
                                .font(.footnote).secondaryText()
                        }
                    }
                } else if store.license().tier == .pro {
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
}
