import Recording
import SwiftUI

/// The Pro section of Settings: the tier, Buy Pro and Restore Purchases. Calm and out of the way: no prompts, and hidden
/// during a Take (`SettingsLock`).
struct ProSection: View {
    /// On in every build since the Pro and Trial products exist in App Store Connect (#371, 2026-10-11): the section,
    /// the first-launch Trial offer, the paywall, the days-left chip and the Free limit at record. Turning it off makes
    /// `record()` pass no allowance, so every USB Channel is recorded with every extra (#60), and hides all of those.
    static let isOffered = true

    @Bindable var model: RecordScreenModel

    private var store: ProStore { model.pro }
    /// Presented by the Settings Form, not this Section: a sheet on a lazily built Form row is torn down when the row
    /// is rebuilt, and took Settings with it (#357).
    @Binding var showingTrial: Bool
    @Binding var showingPaywall: Bool

    var body: some View {
        let tier = store.tier()
        Section {
            LabeledContent("Plan", value: tier.title)
            if tier != .pro {
                Button("See what Pro adds") { showingPaywall = true }
            }
            if tier == .free, store.purchases.trialStartedAt == nil {
                Button("Start 14-day Trial…") { showingTrial = true }
            }
            if tier != .pro {
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
        if store.tier() == .pro { return "Thank you. Every USB Channel is recorded." }
        return "Pro is a one-time purchase, shared with your family. It adds channel names you type, the Show report, Reaper export, 96 kHz recording and Templates for each venue."
    }
}
