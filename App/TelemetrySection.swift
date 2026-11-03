import Recording
import SwiftUI
import Telemetry

/// Settings › Share crash reports and usage (ADR 0007, #1026). Shown only where the build sends them
/// (`TelemetryAvailability`, Debug + TestFlight). Off stops both and deletes this install's random ID.
struct TelemetrySection: View {
    @State private var sharing = TelemetryConsent.isOn()

    var body: some View {
        if TelemetryAvailability.isAvailableInThisBuild {
            Section {
                Toggle("Share crash reports and usage", isOn: $sharing)
                    .onChange(of: sharing) { _, on in AppTelemetry.shared.setSharing(on) }
            } footer: {
                Text("Crash reports go to the developer's GlitchTip server, and usage (Takes started and stopped, Shows, the Drive, the Mixer Link) to PostHog, with a random ID for this install. Never your recordings, Show names, notes or channel names. Turning it off deletes the ID.")
            }
        }
    }
}
