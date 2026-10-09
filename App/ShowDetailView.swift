import Recording
import SwiftUI

/// One Show's Markers by Take, with rename for the operator's Markers (not Dropout Markers).
struct ShowDetailView: View {
    let model: RecordScreenModel
    let show: ShowSummary
    @State private var takes: [TakeDetail]?
    @State private var renaming: (take: Int, marker: MarkerDetail)?
    @State private var newName = ""
    @State private var message: String?

    var body: some View {
        Group {
            if let takes {
                List {
                    ForEach(takes) { take in
                        Section(String(format: "Take %02d", take.number)) {
                            if take.markers.isEmpty {
                                Text("No Markers").foregroundStyle(.secondary)
                            }
                            ForEach(Array(take.markers.enumerated()), id: \.offset) { _, marker in row(marker, take: take.number) }
                        }
                    }
                    if let message {
                        Section { Text(message).foregroundStyle(.red) }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(show.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await reload() }
        .alert("Rename Marker", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { if let renaming { Task { await rename(renaming.marker, inTake: renaming.take) } } }
        }
    }

    @ViewBuilder private func row(_ marker: MarkerDetail, take: Int) -> some View {
        let content = HStack {
            Text(marker.name)
            Spacer()
            Text(Self.clock(marker.seconds)).monospacedDigit().foregroundStyle(.secondary)
        }
        if marker.operatorIndex != nil {
            Button { newName = marker.name; renaming = (take, marker) } label: { content }
                .buttonStyle(.plain)
                .accessibilityHint("Renames this Marker")
        } else {
            content.accessibilityHint("A Dropout Marker, which can't be renamed")
        }
    }

    private static func clock(_ seconds: Double) -> String {
        let total = Int(seconds)
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    private func reload() async {
        let folder = show.folder
        takes = await Task.detached { ShowDetail.read(showFolder: folder) }.value
    }

    private func rename(_ marker: MarkerDetail, inTake take: Int) async {
        guard let index = marker.operatorIndex else { return }
        let store = model.drive.store
        let device = show.folder.deletingLastPathComponent(), name = show.name, newName = newName
        let outcome = await Task.detached { () -> MarkerRenamer.Outcome in
            let access = store.beginAccess()
            defer { access?.end() }
            return ShowDetail.renameMarker(at: index, to: newName, inTake: take, ofShow: name, device: device, drive: access?.folder)
        }.value
        switch outcome.result {
        case .emptyName: message = "A Marker needs a name."
        case .renamed:
            message = outcome.failed.isEmpty ? nil : "Not renamed in the " + outcome.failed.map { $0.copy == .drive ? "Drive" : "Device" }.joined(separator: " and ") + " Copy: " + outcome.failed.map(\.reason).joined(separator: " ")
        default: message = "That Marker couldn't be renamed."
        }
        await reload()
    }
}
