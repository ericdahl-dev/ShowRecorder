import Recording
import SwiftUI

/// The past Shows, newest first, read from the files (Device and Drive). Reached from the record screen.
struct ShowListView: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var shows: [ShowSummary]?
    @State private var unreadable = false
    @State private var deleting: ShowSummary?

    var body: some View {
        NavigationStack {
            Group {
                if unreadable {
                    ContentUnavailableView {
                        Label("Can't read the Shows folder", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("The Shows on this device or the Drive couldn't be opened.")
                    } actions: {
                        Button("Try again") { Task { await reload() } }
                    }
                } else if let shows {
                    if shows.isEmpty {
                        ContentUnavailableView("No Shows yet", systemImage: "music.mic", description: Text("Press record to start one."))
                    } else {
                        List(shows) { show in
                            NavigationLink { ShowDetailView(model: model, show: show) } label: { row(show) }
                                .contextMenu {
                                    if let folder = show.shareFolder { ShareLink("Share…", item: folder) }
                                    Button("Delete…", role: .destructive) { deleting = show }
                                }
                                .swipeActions {
                                    Button("Delete…", role: .destructive) { deleting = show }
                                }
                                .swipeActions(edge: .leading) {
                                    if let folder = show.shareFolder { ShareLink(item: folder) { Label("Share", systemImage: "square.and.arrow.up") }.tint(.blue) }
                                }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Shows")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task {
            await reload()
            // `-deleteShowSheet` opens the delete sheet on the second Show, for screenshots.
            if launchFlag("-deleteShowSheet"), let shows, shows.count > 1 { deleting = shows[1] }
        }
        .sheet(item: $deleting) { show in
            DeleteShowSheet(model: model, show: show) { Task { await reload() } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    private func row(_ show: ShowSummary) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(show.name).font(.headline)
                Text(detail(show)).font(.subheadline).foregroundStyle(.secondary)
                if let note = show.copyNote {
                    Text(note.text).font(.caption).foregroundStyle(note.severity == .problem ? Color.red : .orange)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let folder = show.shareFolder {
                ShareLink(item: folder) { Label("Share", systemImage: "square.and.arrow.up").labelStyle(.iconOnly) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Share \(show.name)")
            }
        }
    }

    private func detail(_ show: ShowSummary) -> String {
        let date = show.startedAt.formatted(date: .abbreviated, time: .shortened)
        let takes = show.takeCount == 1 ? "1 Take" : "\(show.takeCount) Takes"
        guard show.takeCount > 0 else { return "\(date) · \(takes)" }
        let minutes = Int(show.duration / 60)
        let length = minutes < 1 ? "under a minute" : minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
        return "\(date) · \(length) · \(takes)"
    }

    private func reload() async {
        switch await load() {
        case .shows(let found): shows = found; unreadable = false
        case .unreadable: shows = nil; unreadable = true
        }
    }

    private func load() async -> ShowList.Result {
        let store = model.drive.store
        let device = Recorder.defaultDeviceFolder
        return await Task.detached {
            let access = store.beginAccess()
            defer { access?.end() }
            return ShowList.load(device: device, drive: access?.folder)
        }.value
    }
}
