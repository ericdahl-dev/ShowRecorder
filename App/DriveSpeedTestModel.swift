import Destinations
import Recording
import Synchronization
import SwiftUI

/// The Drive speed test's state for the screen (#807, Debug only): whether it runs, what it is doing, what it found.
/// While it runs the record screen counts as busy, so Record is locked.
@MainActor
@Observable
final class DriveSpeedTestModel {
    private(set) var isRunning = false
    /// A launch sweep is still removing an earlier run's folders; a new run waits for it.
    private(set) var isSweeping = false
    private(set) var progress: String?
    private(set) var result: String?
    @ObservationIgnored private let cancelFlag = CancelFlag()

    private final class CancelFlag: Sendable {
        private let canceled = Atomic<Bool>(false)
        var isSet: Bool { canceled.load(ordering: .relaxed) }
        func set(_ value: Bool) { canceled.store(value, ordering: .relaxed) }
    }

    /// Runs the test on the chosen Drive. Never during a Take (the caller checks); Record is locked until it ends.
    func start(store: DriveFolderStore) {
        guard !isRunning else { return }
        guard !isSweeping else {
            result = "Still removing an earlier run's files from the Drive. Try again in a moment."
            return
        }
        guard let access = store.beginAccess() else {
            result = "Choose a Drive folder first."
            return
        }
        isRunning = true
        result = nil
        progress = nil
        cancelFlag.set(false)
        let flag = cancelFlag
        Task { [weak self] in
            let outcome = await DriveSpeedTest.runOffThread(
                on: access.folder, isCancelled: { flag.isSet },
                progress: { text in Task { @MainActor in self?.progress = text } })
            access.end()
            guard let self else { return }
            switch outcome {
            case .success(let report): result = report.summary
            case .failure(let error): result = "The test couldn't run: \(error.localizedDescription)"
            }
            progress = nil
            isRunning = false
        }
    }

    func cancel() { cancelFlag.set(true) }

    /// A run the app quit in the middle of leaves a scratch folder on the Drive: remove it, at launch.
    func removeLeftovers(store: DriveFolderStore) {
        guard !isRunning, !isSweeping, let access = store.beginAccess() else { return }
        isSweeping = true
        Task { [weak self] in
            await DriveSpeedTest.removeLeftoversOffThread(in: access.folder)
            access.end()
            self?.isSweeping = false
        }
    }
}

/// The Settings row for the speed test, with what it found. Only where `DriveSpeedTestAvailability` offers it.
struct DriveSpeedTestRow: View {
    let model: DriveSpeedTestModel
    let canStart: Bool
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isRunning {
                Button("Cancel Drive Speed Test", role: .cancel) { model.cancel() }
                HStack(spacing: 8) {
                    ProgressView()
                    Text(model.progress ?? "Starting…").font(.footnote).secondaryText()
                }
            } else {
                Button("Test Drive Speed (Debug)", action: start)
                    .disabled(!canStart)
                Text("Writes up to 32 channels to the Drive for a few minutes to find how many it keeps up with. Not during a Take.")
                    .font(.footnote).secondaryText()
            }
            if let result = model.result {
                Text(result).font(.footnote).textSelection(.enabled)
            }
        }
    }
}

extension DriveStatus {
    var isAvailable: Bool { if case .available = self { true } else { false } }
}
