import Recording
import SwiftUI

/// The current (or last) Take's Markers with their time in the Take, and a way to rename each of yours,
/// during the Take and after it. The recorder's Dropout Markers are listed but can't be renamed.
struct MarkerListView: View {
    @Bindable var model: RecordScreenModel
    @State private var renaming: MarkerEntry?
    @State private var draft = ""
    @State private var message: String?

    var body: some View {
        List {
            if model.recorder.markerEntries.isEmpty {
                Text("No Markers yet. Press the flag during a Take to place one.")
                    .foregroundStyle(.secondary)
            }
            ForEach(model.recorder.markerEntries) { entry in
                row(entry)
            }
            if model.recorder.takePreRollSeconds > 0, !model.recorder.markerEntries.isEmpty {
                Text("Times are from when you pressed Record. The Stems, the report and the Reaper project count from the start of the Pre-roll, \(Int(model.recorder.takePreRollSeconds.rounded())) s earlier.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .alert("Rename Marker", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draft)
            Button("Rename") {
                guard let entry = renaming else { return }
                let name = draft
                Task { message = await model.renameMarker(entry, to: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func row(_ entry: MarkerEntry) -> some View {
        let label = HStack {
            Text(ElapsedTime.format(seconds: Int(entry.secondsSincePress)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .leading)
            if entry.isDropout {
                Label("Dropout: audio was lost here", systemImage: "waveform.badge.exclamationmark")
            } else {
                Text(entry.name)
                Spacer()
                Image(systemName: "pencil").foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        if entry.isDropout {
            label
        } else {
            Button {
                draft = entry.name
                renaming = entry
            } label: { label }
            .buttonStyle(.plain)
            .accessibilityLabel("\(entry.name), at \(ElapsedTime.format(seconds: Int(entry.secondsSincePress))). Rename")
        }
    }
}
