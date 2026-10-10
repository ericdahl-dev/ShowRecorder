import AudioIO
import Foundation
@testable import Recording
import Testing

/// Show and Marker names are cut to a safe length: a Show name becomes a folder name, which has a 255-byte limit.
@MainActor
@Suite("Name limits")
struct NameLimitTests {
    @Test("A name over the limit is cut at a whole character, by bytes not characters")
    func cutsByBytesAtACharacter() {
        #expect(NameLimit.cut("short", maxBytes: 100) == "short")
        #expect(NameLimit.cut(String(repeating: "a", count: 150), maxBytes: 100).utf8.count == 100)
        // Each emoji is 4 bytes: 10 bytes allows 2 whole emoji, never half of a third.
        let cut = NameLimit.cut("😀😀😀😀", maxBytes: 10)
        #expect(cut == "😀😀")
        #expect(NameLimit.cut("héllo wörld", maxBytes: 3) == "hé", "é is 2 bytes: h + é = 3")
    }

    @Test("A Show with a very long name is created with a folder name the file system accepts")
    func longShowName() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NameLimitTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })

        try recorder.startNewShow(name: String(repeating: "Ö", count: 300), venue: "")

        let folder = try #require(recorder.currentShow?.name)
        #expect(folder.utf8.count <= 255)
        #expect(folder.hasPrefix("2026-10-06 Ö"))
        #expect(FileManager.default.fileExists(atPath: root.appending(path: folder).path))
    }

    @Test("A Marker name is cut to the limit when it is added or renamed")
    func longMarkerName() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "NameLimitTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 1)
        try recorder.arm(audio)
        try recorder.startTake()
        audio.deliver([[0.1]])
        recorder.addMarker(named: String(repeating: "x", count: 500))
        #expect(recorder.takeMarkers.last?.name.utf8.count == NameLimit.maxBytes)

        recorder.addMarker()
        _ = recorder.renameMarker(at: 1, to: String(repeating: "é", count: 500))
        #expect(recorder.takeMarkers.last?.name.utf8.count == NameLimit.maxBytes)
        try recorder.stopTake()
    }
}
