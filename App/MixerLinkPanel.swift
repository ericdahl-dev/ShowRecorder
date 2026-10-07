import MixerLink
import SwiftUI

/// Mixer address entry and Mixer Link status. The address is remembered between launches.
struct MixerLinkPanel: View {
    let link: MixerLinkController
    let usbChannelCount: Int
    @AppStorage("mixerAddress") private var address = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Mixer IP address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(connect)
                    .frame(maxWidth: 260)
                Button(isConnecting ? "Connecting…" : "Connect", action: connect)
                    .disabled(isConnecting || address.isEmpty)
            }
            statusLine
        }
        .task {
            // Reconnect to the remembered Mixer when the record screen opens.
            if !address.isEmpty, link.status == .idle { await link.connect(to: address, usbChannelCount: max(usbChannelCount, 18)) }
        }
    }

    private var isConnecting: Bool {
        if case .connecting = link.status { true } else { false }
    }

    @ViewBuilder private var statusLine: some View {
        switch link.status {
        case .idle:
            Label("Not connected to a mixer. Stems use USB Channel names.", systemImage: "link")
                .foregroundStyle(.secondary)
        case .connecting(let host):
            Label("Connecting to \(host)…", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        case .up(let identity, let path):
            Label("Mixer Link up · \(identity.networkName) (\(identity.model)) · \(path == .wifi ? "Wi-Fi" : "USB")", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .down(let problem):
            Label(problem.message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    private func connect() {
        let address = address
        Task { await link.connect(to: address, usbChannelCount: max(usbChannelCount, 18)) }
    }
}
