import Destinations
import Recording
import SwiftUI
import UniformTypeIdentifiers

/// The Drive folder: chosen once, remembered, and checked so the operator knows before recording
/// whether the Drive is there.
struct DrivePanel: View {
    let usbChannelCount: Int
    @State private var model = DriveFolderModel()
    @State private var choosing = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                statusLabel
                Spacer(minLength: 8)
                Button(model.status == .notChosen ? "Choose Drive Folder…" : "Change…") { choosing = true }
            }
            timeLeftLine
        }
        .font(.callout)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.choose(url) }
        }
        .task {
            // Re-check every few seconds so an unplugged Drive shows up before record is pressed.
            while !Task.isCancelled {
                model.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .onChange(of: scenePhase) { if scenePhase == .active { model.refresh() } }
    }

    /// Time left on each Destination for the Armed USB Channels.
    @ViewBuilder private var timeLeftLine: some View {
        if usbChannelCount > 0 {
            let device = TimeLeft(availableBytes: model.deviceAvailableBytes, usbChannelCount: usbChannelCount, sampleRate: 48_000)
            let drive: TimeLeft? = if case .available(let d) = model.status {
                TimeLeft(availableBytes: d.availableBytes, usbChannelCount: usbChannelCount, sampleRate: 48_000)
            } else { nil }
            Text("Time left · This device: \(device.description)" + (drive.map { " · Drive: \($0.description)" } ?? ""))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch model.status {
        case .notChosen:
            Label("No Drive folder. Takes go to this device only.", systemImage: "externaldrive.badge.questionmark")
                .foregroundStyle(.secondary)
        case .available(let drive):
            Label("Drive: \(drive.name) · \(drive.availableBytes.formatted(.byteCount(style: .file))) free", systemImage: "externaldrive.fill.badge.checkmark")
                .foregroundStyle(.green)
        case .unavailable(let problem):
            Label(problem.message, systemImage: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.orange)
        }
    }
}

@MainActor
@Observable
final class DriveFolderModel {
    private(set) var status: DriveStatus = .notChosen
    private(set) var deviceAvailableBytes: Int64 = 0
    private let store = DriveFolderStore()

    func refresh() {
        status = store.status()
        deviceAvailableBytes = DriveFolderStore.availableBytes(at: URL.documentsDirectory)
    }

    func choose(_ url: URL) {
        do {
            try store.choose(url)
            refresh()
        } catch {
            status = .unavailable(error)
        }
    }
}
