import Foundation
@testable import Recording
import Telemetry
import Testing

/// A Show delete that fails is reported (ADR 0007, #1026, #1021): the failure carries a delete_show
/// `TelemetryFailure` with the error's type, domain and code, never the Show's name or its path.
@Suite("Show delete telemetry")
struct ShowDeleteTelemetryTests {
    @Test("A delete the file system refuses carries a delete_show failure without the Show's name")
    func refusedDelete() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ShowDeleteTelemetryTests-\(UUID().uuidString)")
        let device = root.appending(path: "Device")
        let show = device.appending(path: "Sunday Service")
        try FileManager.default.createDirectory(at: show, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: show.appending(path: "Show.json"))
        // A read-only Shows folder: the Show can't be removed from it.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: device.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: device.path)
            try? FileManager.default.removeItem(at: root)
        }

        let outcome = ShowDeleter.delete(show: "Sunday Service", from: [.device], device: device, drive: nil, openShow: nil)

        let failure = try #require(outcome.failed.first?.telemetry)
        #expect(failure.area == .deleteShow)
        #expect(failure.domain == NSCocoaErrorDomain)
        #expect(!failure.summary.contains("Sunday"))
    }
}
