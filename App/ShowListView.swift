import Recording
import StoreKit
import SwiftUI
import Telemetry

/// The past Shows, newest first, read from the files (Device and Drive). Reached from the record screen.
struct ShowListView: View {
    let model: RecordScreenModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var shows: [ShowSummary]?
    @State private var unreadable = false
    @State private var deleting: ShowSummary?
    /// Select mode (#1217): pick several Shows and delete them at once, to free space.
    @State private var selecting = false
    @State private var selection: Set<String> = []
    /// Each Show's size on the Device, read off the main thread for Select mode.
    @State private var sizes: [String: Int64] = [:]
    @State private var confirmingSelected = false
    @State private var deletingSelected = false
    @State private var selectMessage: String?

    private var offersSelect: Bool { ShowCleanupAvailability.isAvailableInThisBuild }
    private var openShow: String? { model.recorder.currentShow?.name }

    var body: some View {
        NavigationStack {
            Group {
                if unreadable {
                    ContentUnavailableView {
                        Label("Can't read the Shows folder", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text("The Shows on the Device or the Drive couldn't be opened.")
                    } actions: {
                        Button("Try again") { Task { await reload() } }
                    }
                } else if let shows {
                    if shows.isEmpty {
                        ContentUnavailableView("No Shows yet", systemImage: "music.mic", description: Text("Press record to start one."))
                    } else {
                        List(shows, selection: selecting ? $selection : nil) { show in
                            NavigationLink { ShowDetailView(model: model, show: show) } label: { row(show) }
                                .contextMenu {
                                    if let folder = show.shareFolder { ShareLink("Share…", item: folder) }
                                    Button("Delete…", role: .destructive) { deleting = show }
                                }
                                // Not `role: .destructive` and no full swipe: this only opens the delete sheet, and a destructive
                                // swipe makes the List drop the row while `shows` still has it, which crashes UIKit (#1021).
                                .swipeActions(allowsFullSwipe: false) {
                                    Button("Delete…") { deleting = show }.tint(.red)
                                }
                                .swipeActions(edge: .leading) {
                                    if let folder = show.shareFolder { ShareLink(item: folder) { Label("Share", systemImage: "square.and.arrow.up") }.tint(.blue) }
                                }
                                // The open Show is ended and deleted only from its own sheet.
                                .selectionDisabled(show.name == openShow)
                        }
                        #if os(iOS)
                        .environment(\.editMode, .constant(selecting ? .active : .inactive))
                        #endif
                        .safeAreaInset(edge: .bottom) { if selecting { selectBar(shows) } }
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
                if offersSelect, let shows, !shows.isEmpty {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(selecting ? "Cancel" : "Select") {
                            selecting.toggle()
                            selection = []
                            selectMessage = nil
                        }
                        .disabled(deletingSelected)
                    }
                }
            }
        }
        .task {
            await reload()
            // The App Store rating prompt, when one is due after a clean Take: here, with no Take running.
            model.askForRatingIfDue { requestReview() }
            // `-deleteShowSheet` opens the delete sheet on the second Show, for screenshots.
            if launchFlag("-deleteShowSheet"), let shows, shows.count > 1 { deleting = shows[1] }
        }
        .sheet(item: $deleting) { show in
            DeleteShowSheet(model: model, show: show) { Task { await reload() } }
                .modifier(AppearanceRoot(mode: model.appearance))
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }

    /// Under the list in Select mode: "Select empty", what is picked and its size, and Delete.
    private func selectBar(_ shows: [ShowSummary]) -> some View {
        let empty = ShowCleanup.empty(shows, openShow: openShow)
        return VStack(spacing: 8) {
            if let selectMessage { Text(selectMessage).font(.caption).errorText() }
            HStack {
                Button("Select empty") { selection = empty }.disabled(empty.isEmpty || deletingSelected)
                Spacer()
                Text(selectedSummary).font(.subheadline).secondaryText()
                Spacer()
                Button(deletingSelected ? "Deleting…" : "Delete", role: .destructive) { confirmingSelected = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selection.isEmpty || deletingSelected)
                    .confirmationDialog(selection.count == 1 ? "Delete 1 Show for good?" : "Delete \(selection.count) Shows for good?",
                                        isPresented: $confirmingSelected, titleVisibility: .visible) {
                        Button(selection.count == 1 ? "Delete 1 Show" : "Delete \(selection.count) Shows", role: .destructive) { deleteSelected(shows) }
                    } message: {
                        Text("This permanently deletes them from the Device and the Drive (\(selectedBytes.formatted(.byteCount(style: .file))) on the Device). There is no Trash, and it can't be undone.")
                    }
            }
        }
        .padding()
        .background(.bar)
    }

    private var selectedBytes: Int64 { selection.reduce(0) { $0 + (sizes[$1] ?? 0) } }
    private var selectedSummary: String {
        selection.isEmpty ? "None selected" : "\(selection.count) selected · \(selectedBytes.formatted(.byteCount(style: .file)))"
    }

    /// Deletes the picked Shows, never the open one, off the main thread (#1021), then reads the list again.
    private func deleteSelected(_ shows: [ShowSummary]) {
        guard !deletingSelected else { return }
        let picked = ShowCleanup.selectable(shows, openShow: openShow).filter { selection.contains($0.name) }
        deletingSelected = true
        Task {
            let outcomes = await model.recorder.deleteShowsOffMain(picked)
            // A delete the file system refused goes to crash reports, without the Show's name (ADR 0007, #1021).
            for failure in outcomes.flatMap(\.outcome.failed).compactMap(\.telemetry) { AppTelemetry.shared.report(failure) }
            let failed = outcomes.filter { !$0.outcome.failed.isEmpty }
            selectMessage = failed.isEmpty ? nil
                : "\(failed.count) of \(outcomes.count) couldn't be deleted. " + failed.map { "\($0.name): \($0.outcome.failed.map(\.reason).joined(separator: " "))" }.joined(separator: " ")
            selection = []
            if failed.isEmpty { selecting = false }
            deletingSelected = false
            await reload()
        }
    }

    private func row(_ show: ShowSummary) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(show.name).font(.headline)
                Text(detail(show)).font(.subheadline).secondaryText()
                if selecting, let bytes = sizes[show.name] {
                    Text(bytes.formatted(.byteCount(style: .file)) + " on the Device").font(.caption).secondaryText()
                }
                if let note = show.copyNote {
                    Text(note.text).font(.caption).inlineText(note.severity == .problem ? .error : .warning)
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
        case .shows(let found):
            shows = found
            unreadable = false
            if offersSelect {
                sizes = await Task.detached { Dictionary(found.map { ($0.name, ShowCleanup.deviceBytes(of: $0)) }, uniquingKeysWith: { a, _ in a }) }.value
            }
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
