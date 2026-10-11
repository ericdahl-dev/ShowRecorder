import MixerLink
import Recording
import SwiftUI

/// The Soundcheck (#63): proves the rig in about a minute. Mixer Link, USB Channels, a 30 s test Take on every Copy,
/// and the files it writes; each step passes or says what to do. Never during a Take.
struct SoundcheckView: View {
    @Bindable var model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var steps: [Soundcheck.Step] = []
    @State private var current: Soundcheck.Step.Kind?
    @State private var running = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Checks the Mixer Link, the USB Channels, a 30 s test Take on every Copy, and the report and Reaper project it writes. Play something through the Mixer while it runs.")
                    if let show = model.recorder.currentShow, !running, steps.isEmpty {
                        Text("The test Take goes into its own Show, so \(show.name) is ended first.")
                            .secondaryText()
                    }
                }
                Section {
                    ForEach(Soundcheck.Step.Kind.allCases, id: \.self) { kind in row(kind) }
                }
                if let failed = steps.first(where: { !$0.passed }) {
                    Section { Text("Fix \(Self.title(failed.kind)) and run it again.").font(.headline) }
                } else if !steps.isEmpty {
                    Section { Text("Everything checked out. The rig is ready.").font(.headline) }
                }
            }
            .navigationTitle("Soundcheck")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(steps.isEmpty ? "Not Now" : "Done") { dismiss() }.disabled(running)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(steps.isEmpty ? "Start" : "Run Again") { Task { await run() } }
                        .disabled(running || model.recorder.isRecording || !model.recorder.isArmed)
                }
            }
        }
        // Opening it, from the banner or Settings, counts as the one offer.
        .onAppear { model.soundcheckOffered = true }
        .interactiveDismissDisabled(running)
    }

    private func run() async {
        running = true
        steps = []
        // Each result shows as soon as it's known; the Mixer's doesn't wait for the 30 s Take.
        steps = await model.runSoundcheck(progress: { current = $0 }, result: { steps.append($0) })
        current = nil
        running = false
    }

    private func row(_ kind: Soundcheck.Step.Kind) -> some View {
        let step = steps.first { $0.kind == kind }
        return HStack(alignment: .top, spacing: 12) {
            Group {
                if let step {
                    Image(systemName: step.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(step.passed ? .green : .red)
                } else if current == kind {
                    ProgressView()
                } else {
                    Image(systemName: "circle").secondaryText()
                }
            }
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(kind)).font(.headline)
                if let step { Text(step.message).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            }
        }
        // Say passed or failed in words; the icons alone read as "Selected" and "Error".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.title(kind))
        .accessibilityValue(step.map { "\($0.passed ? "Passed" : "Failed"). \($0.message)" } ?? (current == kind ? "Checking" : "Not checked yet"))
    }

    static func title(_ kind: Soundcheck.Step.Kind) -> String {
        switch kind {
        case .mixer: "Mixer Link"
        case .channels: "USB Channels"
        case .take: "Test Take"
        case .files: "Report and Reaper project"
        }
    }
}
