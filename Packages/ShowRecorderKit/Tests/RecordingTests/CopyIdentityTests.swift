import Destinations
import Foundation
@testable import Recording
import Testing

@Suite("Copy identity")
struct CopyIdentityTests {
    /// A Take.json written before Copies had a type: the Gap and Repair name their Copy as a string.
    static let existing = """
        {"gaps":[{"copy":"drive","end":4800,"start":480}],"markers":[],"repairs":[{"copy":"drive","end":4800,"outcome":"repaired","start":480}],\
        "sampleRate":48000,"show":"S","startedAt":"2026-10-07T00:00:00Z","take":1,"timeReference":0,"usbChannels":[]}
        """

    @Test("A Take.json from before Copies had a type still reads, and writes the same names back")
    func takeJSONKeepsItsCopyNames() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let take = try decoder.decode(TakeMetadata.self, from: Data(Self.existing.utf8))

        #expect(take.gaps == [.init(copy: .drive, start: 480, end: 4800)])
        #expect(take.repairs == [.init(copy: .drive, start: 480, end: 4800, outcome: .repaired)])
        #expect(take.outcome(ofCopy: .drive) == .repaired)
        #expect(take.outcome(ofCopy: .device) == .complete)

        let folder = FileManager.default.temporaryDirectory.appending(path: "CopyIdentityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try take.write(to: folder)
        let written = try String(contentsOf: folder.appending(path: "Take.json"), encoding: .utf8)
        #expect(written.contains(#""copy" : "drive""#))
        #expect(!written.contains(#""copy" : "device""#))
    }

    @Test("Copies are numbered device first, then drive, in one place")
    func indexes() {
        #expect(DestinationKind.device.index == 0)
        #expect(DestinationKind.drive.index == 1)
        #expect(DestinationKind(index: 1) == .drive)
    }
}
