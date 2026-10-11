import Recording
import SwiftUI

/// The Pro section of Settings: the tier, Buy Pro, Restore Purchases and, on Free, which 2 USB Channels are
/// recorded. Calm and out of the way: no prompts, and hidden during a Take (`SettingsLock`).
struct ProSection: View {
    /// Off until the Pro and Trial products exist in App Store Connect, and not before 96 kHz (#195) and Templates
    /// (#33, #34) are built: the footer and the App Store text promise them (ADR 0004, launch scope). It also switches
    /// the limits on: while off, `record()` passes no allowance, so every USB Channel is recorded with every extra
    /// (#60), and the section, the first-launch Trial offer and the days-left chip stay hidden.
    static let isOffered = false

    @Bindable var model: RecordScreenModel

    private var store: ProStore { model.pro }
    @State private var showingTrial = false
    @State private var showingPaywall = false

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
            if tier == .free {
                freePicker
            }
        } header: {
            Text("Pro")
        } footer: {
            Text(footer)
        }
        .sheet(isPresented: $showingTrial) { TrialSheet(store: store).modifier(AppearanceRoot(mode: model.appearance)) }
        .sheet(isPresented: $showingPaywall) { PaywallSheet(store: store, moment: nil).modifier(AppearanceRoot(mode: model.appearance)) }
    }

    private var priceText: String {
        if let product = store.proProduct { return product.displayPrice }
        return store.loadingProducts ? "Loading…" : "Price unavailable"
    }

    private var footer: String {
        if store.tier() == .pro { return "Thank you. Every USB Channel is recorded." }
        return "Pro is a one-time purchase, shared with your family. It records every USB Channel and adds channel names you type, the Show report, Reaper export, 96 kHz recording and Templates for each venue."
    }

    /// The 2 USB Channels Free records, out of those the Armed input offers.
    @ViewBuilder private var freePicker: some View {
        let count = model.recorder.usbChannelCount
        if count > 0 {
            let recorded = Entitlement.allowance(for: .free, channelCount: count, freeChoice: store.freeChoice)
                .recordedChannels.sorted()
            ForEach(Array(recorded.enumerated()), id: \.offset) { index, channel in
                Picker(index == 0 ? "First recorded channel" : "Second recorded channel", selection: Binding(
                    get: { channel },
                    set: { store.freeChoice = FreeChannelChoice.picking($0, slot: index, in: recorded) }
                )) {
                    ForEach(1...count, id: \.self) { usb in
                        Text("USB \(usb)").tag(usb)
                    }
                }
                .pickerStyle(.menu)
            }
            Text("Free records 2 USB Channels. Every channel is still metered.")
                .font(.footnote).secondaryText()
        }
    }
}
