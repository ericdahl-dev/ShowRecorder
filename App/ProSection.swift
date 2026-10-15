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
        let license = store.license()
        let tier = license.tier
        Section {
            LabeledContent("Plan", value: license.planTitle)
            if let tier, tier != .pro {
                Button("See what Pro adds") { showingPaywall = true }
            }
            if tier == .free, !license.trialStarted {
                Button("Start 14-day Trial…") { showingTrial = true }
            }
            if let tier, tier != .pro {
                Button {
                    Task { await store.buyPro() }
                } label: {
                    LabeledContent("Buy Pro", value: priceText)
                }
                .disabled(store.proProduct == nil || store.busy)
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

    private var priceText: String {
        if let product = store.proProduct { return product.displayPrice }
        return store.loadingProducts ? "Loading…" : "Price unavailable"
    }

    private var footer: String {
        switch store.license().tier {
        case .pro: return "Thank you. Everything in Pro is yours."
        case nil: return "Your plan shows here once the App Store answers. Until then, nothing is limited."
        default: break
        }
        return "Free records every USB Channel on the Device. Pro is a one-time purchase, shared with your family. It adds names and colors from the Mixer, channel names you type, a second Copy on the Drive, unlimited Markers, the Show report, Reaper export, 96 kHz recording and Templates for each venue."
    }
}
