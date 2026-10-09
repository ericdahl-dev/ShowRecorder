import Destinations
import Recording
import SwiftUI

/// Deletes a Show, or one Take of it, for good from the Copies you choose. You type the Show's name to confirm.
struct DeleteShowSheet: View {
    let model: RecordScreenModel
    let show: ShowSummary
    /// Set to delete just this Take of the Show.
    var take: Int?
    /// Set with `take` to delete just this channel's file from the Take.
    var channel: Int?
    var deleted: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var fromDevice = true
    @State private var fromDrive = true
    @State private var typed = ""
    @State private var message: String?

    private var isOpenShow: Bool { model.recorder.currentShow?.name == show.name }
    private var blocked: String? {
        if model.recorder.isRecording { return "A Take is running. Stop it first." }
        if isOpenShow { return "This Show is open. End it first (tap the Show name on the record screen)." }
        return nil
    }
    private var chosen: Set<DestinationKind> {
        var kinds: Set<DestinationKind> = []
        if fromDevice, show.deviceCopy != nil { kinds.insert(.device) }
        if fromDrive, show.driveCopy != nil { kinds.insert(.drive) }
        return kinds
    }

    var body: some View {
        NavigationStack {
            Form {
                if let blocked {
                    Section { Label(blocked, systemImage: "lock.fill").foregroundStyle(.secondary) }
                }
                Section {
                    Toggle("Device copy", isOn: $fromDevice).disabled(show.deviceCopy == nil)
                    Toggle("Drive copy", isOn: $fromDrive).disabled(show.driveCopy == nil)
                } header: {
                    Text("Delete from")
                } footer: {
                    Text(footer)
                }
                Section {
                    TextField("Type the Show's name", text: $typed)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Type \(show.name) to confirm")
                }
                Section {
                    Button(channel != nil ? "Delete channel \(channel ?? 0)'s file" : take.map { "Delete Take \(String(format: "%02d", $0))" } ?? "Delete \(show.name)", role: .destructive) { delete() }
                        .disabled(blocked != nil || chosen.isEmpty || !ShowDeleter.confirms(typed: typed, for: show.name))
                    if let message { Text(message).foregroundStyle(.red) }
                }
            }
            .navigationTitle(channel != nil ? "Delete File" : take == nil ? "Delete Show" : "Delete Take")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 380)
        #endif
    }

    private var footer: String {
        let takes = show.takeCount == 1 ? "1 Take" : "\(show.takeCount) Takes"
        let what: String
        if let take, let channel { what = "channel \(channel)'s file in Take \(String(format: "%02d", take)) of \(show.name)" }
        else if let take { what = "Take \(String(format: "%02d", take)) of \(show.name)" }
        else { what = "\(show.name) (\(takes))" }
        let names = chosen.sorted { $0.index < $1.index }.map { $0 == .device ? "the Device copy" : "the Drive copy" }
        return names.isEmpty ? "Choose a Copy to delete."
            : "This permanently deletes \(what) from \(names.joined(separator: " and ")). There is no Trash, and it can't be undone."
    }

    private func delete() {
        let outcome: ShowDeleter.Outcome
        if let take, let channel { outcome = model.recorder.deleteChannel(channel, inTake: take, ofShow: show.name, from: chosen) }
        else if let take { outcome = model.recorder.deleteTake(take, ofShow: show.name, from: chosen) }
        else { outcome = model.recorder.deleteShow(named: show.name, from: chosen) }
        if outcome.failed.isEmpty {
            deleted()
            dismiss()
        } else {
            let failed = outcome.failed.map { "\($0.copy == .device ? "Device" : "Drive"): \($0.reason)" }.joined(separator: " ")
            message = (outcome.deleted.isEmpty ? "Nothing was deleted. " : "Deleted from \(outcome.deleted.map { $0 == .device ? "the Device" : "the Drive" }.joined(separator: " and ")). ") + failed
            if !outcome.deleted.isEmpty { deleted() }
        }
    }
}
