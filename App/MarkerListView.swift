import Recording
import SwiftUI

/// The current (or last) Take's Markers with their time in the Take, and a way to rename each of yours,
/// during the Take and after it. The Markers the recorder placed (Dropouts, gain and routing changes) are listed but
/// can't be renamed.
struct MarkerListView: View {
    @Bindable var model: RecordScreenModel
    @State private var renaming: MarkerEntry?
    @State private var draft = ""
    @State private var message: String?

    var body: some View {
        List {
            if model.recorder.markerEntries.isEmpty {
                Text("No Markers yet. Press the flag during a Take to place one.")
                    .secondaryText()
            }
            ForEach(model.recorder.markerEntries) { entry in
                row(entry)
            }
            if model.recorder.takePreRollSeconds > 0, !model.recorder.markerEntries.isEmpty {
                Text("Times are from when you pressed Record. The Stems, the report and the Reaper project count from the start of the Pre-roll, \(Int(model.recorder.takePreRollSeconds.rounded())) s earlier.")
                    .font(.footnote)
                    .secondaryText()
            }
            if let message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .warningText()
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
                .secondaryText()
                .frame(minWidth: 56, alignment: .leading)
            if entry.isDropout {
                Label("Dropout: audio was lost here", systemImage: "waveform.badge.exclamationmark")
            } else if entry.operatorIndex == nil {
                Label(entry.name, systemImage: entry.kind == .routing ? "arrow.triangle.branch" : "slider.vertical.3")
            } else {
                Text(entry.name)
                Spacer()
                Image(systemName: "pencil").secondaryText()
            }
        }
        .frame(minHeight: 44)
        if entry.operatorIndex == nil {
            label.accessibilityHint("Can't be renamed")
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
