import MixerLink
import SwiftUI

/// Find mixers (#289): asks every address on this device's network for /xinfo and lists the mixers that answer.
/// Tapping one fills in its address and connects; with more than one of the Ready kind, it also picks it as the one
/// plugged in by USB (#1018). Only when the operator taps it; Settings is locked during a Take.
struct FindMixersRow: View {
    @Bindable var model: RecordScreenModel
    let disabled: Bool
    @State private var searching = false
    /// Nil before the first search.
    @State private var found: [FoundMixer]?
    @State private var noNetwork = false

    var body: some View {
        Button(searching ? "Finding Mixers…" : "Find Mixers") { find() }
            .disabled(searching || disabled)
        if noNetwork {
            Text("Not on a Wi-Fi or Ethernet network.")
                .font(.footnote).secondaryText()
        } else if let found, found.isEmpty, !searching {
            // On iOS the first search is also the first local-network send, so it asks for Local Network access and
            // the replies are lost while it asks.
            Text("No Mixer answered. Check you're on the Mixer's network and Local Network access is on. If it just asked about Local Network, tap Find Mixers again.")
                .font(.footnote).secondaryText()
        } else if let found {
            // Two Mixers of the Ready kind: auto-gain moves preamps only on the one plugged in by USB (#1018).
            if model.mixer.asksForUSBMixer(among: found) {
                Text("More than one Mixer of this kind answered. Tap the one plugged in by USB.")
                    .font(.footnote).secondaryText()
            }
            ForEach(found, id: \.host) { mixer in
                Button {
                    model.chooseMixer(mixer, among: found)
                } label: {
                    LabeledContent("\(mixer.identity.networkName) (\(mixer.identity.model))", value: mixer.host)
                }
                .disabled(disabled)
            }
        }
    }

    private func find() {
        guard let range = ScanRange.currentNetwork() else {
            noNetwork = true
            found = nil
            return
        }
        noNetwork = false
        searching = true
        Task {
            found = await MixerScanner.scan(hosts: range.hosts)
            searching = false
        }
    }
}
