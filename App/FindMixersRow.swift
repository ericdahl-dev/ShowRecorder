import MixerLink
import SwiftUI

/// Find mixers (#289): asks every address on this device's network for /xinfo and lists the mixers that answer.
/// Tapping one fills in its address and connects. Only when the operator taps it; Settings is locked during a Take.
struct FindMixersRow: View {
    @Bindable var model: RecordScreenModel
    let disabled: Bool
    @State private var searching = false
    /// Nil before the first search.
    @State private var found: [FoundMixer]?
    @State private var noNetwork = false

    var body: some View {
        Button(searching ? "Finding mixers…" : "Find mixers") { find() }
            .disabled(searching || disabled)
        if noNetwork {
            Text("Not on a Wi-Fi or Ethernet network.")
                .font(.footnote).foregroundStyle(.secondary)
        } else if let found, found.isEmpty, !searching {
            // On iOS the first search is also the first local-network send, so it asks for Local Network access and
            // the replies are lost while it asks.
            Text("No mixers answered. Check this device is on the mixer's network and Local Network access is on. If it just asked about Local Network, tap Find mixers again.")
                .font(.footnote).foregroundStyle(.secondary)
        } else if let found {
            ForEach(found, id: \.host) { mixer in
                Button {
                    model.mixerAddress = mixer.host
                    model.connectMixer()
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
