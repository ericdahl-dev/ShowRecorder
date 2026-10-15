import BroadcastWave
import Foundation
@testable import Recording
import Testing

/// A Stem that can't be read is never taken to match (#630): the Copy check gates deleting the Device Copy.
@Suite("Copy check: unreadable audio")
struct CopyCheckReadTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "CopyCheckReadTests-\(UUID().uuidString)")

    @Test("Audio that can't be read on either Copy is a problem, not a match")
    func unreadableOnBoth() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let a = root.appending(path: "a.wav"), b = root.appending(path: "b.wav")
        try Data(count: 100).write(to: a)
        try Data(count: 100).write(to: b)
        // A region past the end of both files: neither can be read whole.
        let region = (offset: UInt64(0), length: UInt64(1_000_000))

        let problem = try CopyCheck.audioProblem(name: "Take 01", channel: 1, device: a, region, drive: b, region, shouldStop: { false })

        #expect(problem == "Take 01, channel 1 can't be read on the Device.")
    }

    @Test("Audio that can't be read on the Drive is a problem")
    func unreadableOnTheDrive() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let a = root.appending(path: "a.wav"), b = root.appending(path: "b.wav")
        try Data(count: 100).write(to: a)
        try Data(count: 100).write(to: b)

        let problem = try CopyCheck.audioProblem(
            name: "Take 01", channel: 1, device: a, (offset: 0, length: 100), drive: b, (offset: 0, length: 1_000_000), shouldStop: { false })

        #expect(problem == "Take 01, channel 1 can't be read on the Drive.")
    }
}
