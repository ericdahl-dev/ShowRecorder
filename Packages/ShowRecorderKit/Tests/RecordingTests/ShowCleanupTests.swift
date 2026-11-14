import Foundation
import Testing

@testable import Recording

/// The Shows list's Select mode (#1217): what each Show takes on the Device, which Shows can be picked, and
/// "Select empty".
@Suite("Show clean-up")
struct ShowCleanupTests {
    let device = FileManager.default.temporaryDirectory.appending(path: "ShowCleanupTests-\(UUID().uuidString)")

    /// A Show folder with a "Take 01" folder holding `bytes` bytes, or an empty "Take 01" when `bytes` is 0.
    func makeShow(_ name: String, bytes: Int) throws {
        let take = device.appending(path: name).appending(path: "Take 01")
        try FileManager.default.createDirectory(at: take, withIntermediateDirectories: true)
        if bytes > 0 { try Data(count: bytes).write(to: take.appending(path: "Ch01.wav")) }
    }

    @Test("A Show's size on the Device adds up every file in its folder")
    func deviceBytes() throws {
        defer { try? FileManager.default.removeItem(at: device) }
        try makeShow("2026-11-12 Show", bytes: 5000)
        try Data(count: 300).write(to: device.appending(path: "2026-11-12 Show/Show.html"))
        let show = try #require(ShowList.read(device: device, drive: nil).first)

        #expect(ShowCleanup.deviceBytes(of: show) == 5300)
    }

    @Test("The open Show can't be picked: it is left out of the Shows offered")
    func openShowLeftOut() throws {
        defer { try? FileManager.default.removeItem(at: device) }
        try makeShow("2026-11-12 Show", bytes: 0)
        try makeShow("2026-11-14 Show", bytes: 0)
        let shows = ShowList.read(device: device, drive: nil)

        #expect(ShowCleanup.selectable(shows, openShow: "2026-11-14 Show").map(\.name) == ["2026-11-12 Show"])
        #expect(ShowCleanup.selectable(shows, openShow: nil).count == 2)
    }

    @Test("Select empty picks the Shows with no Takes left, never the open Show")
    func selectEmpty() throws {
        defer { try? FileManager.default.removeItem(at: device) }
        try makeShow("2026-11-09 Show", bytes: 0)
        try makeShow("2026-11-12 Show", bytes: 0)
        try makeShow("2026-11-14 Show", bytes: 0)
        var shows = ShowList.read(device: device, drive: nil)
        // One Show with a Take: the list reads it as 1 Take.
        if let index = shows.firstIndex(where: { $0.name == "2026-11-12 Show" }) { shows[index].takeCount = 1 }

        #expect(ShowCleanup.empty(shows, openShow: "2026-11-14 Show") == ["2026-11-09 Show"])
    }
}
