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
    @State private var deletingTake: Int?
    @State private var deletingFile: (take: Int, channel: Int)?

    var body: some View {
        Group {
            if let takes {
                List {
                    if takes.isEmpty {
                        Text("No Takes yet").foregroundStyle(.secondary)
                    }
                    ForEach(takes) { take in
                        Section {
                            if take.markers.isEmpty {
                                Text("No Markers").foregroundStyle(.secondary)
                            }
                            ForEach(Array(take.markers.enumerated()), id: \.offset) { _, marker in row(marker, take: take.number) }
                            if !take.channels.isEmpty {
                                DisclosureGroup("Channel files (\(take.channels.count))") {
                                    ForEach(take.channels, id: \.number) { channel in
                                        HStack {
                                            Text("\(channel.number)").monospacedDigit().foregroundStyle(.secondary)
                                            Text(channel.name)
                                            Spacer()
                                            Button("Delete…", role: .destructive) { deletingFile = (take.number, channel.number) }
                                                .buttonStyle(.borderless)
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                        } header: {
                            HStack {
                                Text(String(format: "Take %02d", take.number))
                                Spacer()
                                Button("Delete…", role: .destructive) { deletingTake = take.number }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                            }
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
        .toolbar {
            if let folder = show.shareFolder {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: folder) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await reload() }
        .sheet(item: Binding(get: { deletingFile.map { FileID(take: $0.take, channel: $0.channel) } }, set: { deletingFile = $0.map { ($0.take, $0.channel) } })) { id in
            DeleteShowSheet(model: model, show: show, take: id.take, channel: id.channel) { Task { await reload() } }
        }
        .sheet(item: Binding(get: { deletingTake.map { TakeID(number: $0) } }, set: { deletingTake = $0?.number })) { id in
            DeleteShowSheet(model: model, show: show, take: id.number) { Task { await reload() } }
        }
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

private struct TakeID: Identifiable { let number: Int; var id: Int { number } }
private struct FileID: Identifiable { let take: Int; let channel: Int; var id: Int { take * 1000 + channel } }
