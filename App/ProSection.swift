import Recording
import SwiftUI

/// The Pro section of Settings: the tier, Buy Pro, Restore Purchases and, on Free, which 2 USB Channels are
/// recorded. Calm and out of the way: no prompts, and hidden during a Take (`SettingsLock`).
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
            if tier == .free {
                freePicker
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
        case .pro: return "Thank you. Every USB Channel is recorded."
        case nil: return "Your plan shows here once the App Store answers. Until then, every USB Channel is recorded."
        default: break
        }
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
