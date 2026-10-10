import Recording
import SwiftUI

/// The past Shows, newest first, read from the files (Device and Drive). Reached from the record screen.
struct ShowListView: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @State private var shows: [ShowSummary]?
    @State private var deleting: ShowSummary?

    var body: some View {
        NavigationStack {
            Group {
                if let shows {
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
            shows = await load()
            // `-deleteShowSheet` opens the delete sheet on the second Show, for screenshots.
            if launchFlag("-deleteShowSheet"), let shows, shows.count > 1 { deleting = shows[1] }
        }
        .sheet(item: $deleting) { show in
            DeleteShowSheet(model: model, show: show) { Task { shows = await load() } }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    private func row(_ show: ShowSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(show.name).font(.headline)
            Text(detail(show)).font(.subheadline).foregroundStyle(.secondary)
            Text(copies(show)).font(.caption).foregroundStyle(copiesAreProblem(show) ? Color.red : .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func detail(_ show: ShowSummary) -> String {
        let date = show.startedAt.formatted(date: .abbreviated, time: .shortened)
        let takes = show.takeCount == 1 ? "1 Take" : "\(show.takeCount) Takes"
        guard show.takeCount > 0 else { return "\(date) · \(takes)" }
        let minutes = Int(show.duration / 60)
        let length = minutes < 1 ? "under a minute" : minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
        return "\(date) · \(length) · \(takes)"
    }

    private func copies(_ show: ShowSummary) -> String {
        "Device copy: \(Self.word(show.deviceCopy)) · Drive copy: \(Self.word(show.driveCopy))"
    }

    private func copiesAreProblem(_ show: ShowSummary) -> Bool {
        [show.deviceCopy, show.driveCopy].contains { $0 == .hasGaps || $0 == .repairFailed }
    }

    /// The same words as the record screen and the report.
    private static func word(_ outcome: CopyOutcome?) -> String {
        switch outcome {
        case nil: "not there"
        case .complete: "complete"
        case .hasGaps: "has Gaps"
        case .repaired: "Repaired"
        case .repairFailed: "Repair failed"
        }
    }

    private func load() async -> [ShowSummary] {
        let store = model.drive.store
        let device = Recorder.defaultDeviceFolder
        return await Task.detached {
            let access = store.beginAccess()
            defer { access?.end() }
            return ShowList.read(device: device, drive: access?.folder)
        }.value
    }
}
