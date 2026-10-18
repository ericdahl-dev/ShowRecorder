import Destinations
import Recording
import SwiftUI

/// The Drive folder and the Device's free space, kept current by the record screen's model so the
/// status strip, Settings and the recorder all read the same state, whether or not Settings is open.
@MainActor
@Observable
final class DriveFolderModel {
    private(set) var status: DriveStatus = .notChosen
    private(set) var deviceAvailableBytes: Int64 = 0
    /// Shared with the recorder, which opens the folder at record time.
    let store: DriveFolderStore
    /// A read of the Drive is under way (`refreshInBackground`).
    private var isRefreshing = false

    init(store: DriveFolderStore = DriveFolderStore()) {
        self.store = store
    }

    /// Bumped by every synchronous read, so a background read that began before it doesn't overwrite what it found.
    private var generation = 0

    /// The periodic re-read (#814). The Device's free space is read off the main actor every time, so its chip keeps
    /// counting down during a Take. The Drive is not asked during a Take (`busy`), when a Drive that is writing answers
    /// slowly and the recorder already knows how it is doing; between Takes it is asked on a thread of its own, one read at
    /// a time. What a read found is dropped if a newer one has been published meanwhile or a Take began (`stillIdle`).
    func refreshInBackground(whileBusy busy: Bool, stillIdle: @MainActor () -> Bool = { true }) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let started = generation
        // Where the Device Copy is written, so the two can't drift apart.
        let deviceFolder = Recorder.defaultDeviceFolder
        let device = await DriveFolderStore.onOwnThread { DriveFolderStore.availableBytes(forFolder: deviceFolder) }
        if started == generation { deviceAvailableBytes = device }
        guard !busy else { return }
        let found = await store.currentStatus()
        guard started == generation, stillIdle() else { return }
        status = found
    }

    func refresh() {
        generation += 1
        status = store.status()
        // Where the Device Copy is written, so the two can't drift apart.
        deviceAvailableBytes = DriveFolderStore.availableBytes(forFolder: Recorder.defaultDeviceFolder)
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
