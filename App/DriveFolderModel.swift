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
    let store = DriveFolderStore()

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
