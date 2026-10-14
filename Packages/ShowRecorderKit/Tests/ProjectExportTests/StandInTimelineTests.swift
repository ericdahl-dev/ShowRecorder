import BroadcastWave
import Foundation
import ProjectExport
@testable import Recording
import TakeFile
import Testing

/// A Drive only Take whose stand-in is kept on the Device (#629, option C): its Stems are under `Stand-in N/`, so the
/// Device's timeline takes the Take's length from its stand-ins, and later Takes in the Reaper project don't overlap it.
@Suite("Device timeline with a kept stand-in")
struct StandInTimelineTests {
    let show = FileManager.default.temporaryDirectory.appending(path: "StandInTimelineTests-\(UUID().uuidString)/2026-10-06 Show")

    /// Writes Take `number` with one USB Channel: its Stem of `frames` at `stemFolder` inside the Take folder.
    func writeTake(_ number: Int, frames: Int, stemFolder: String = "", standIns: [TakeMetadata.StandIn]? = nil) throws {
        let folder = show.appending(path: TakeMetadata.name(take: number))
        let stems = stemFolder.isEmpty ? folder : folder.appending(path: stemFolder)
        try FileManager.default.createDirectory(at: stems, withIntermediateDirectories: true)
        var take = TakeMetadata(
            show: "2026-10-06 Show", take: number, startedAt: Date(timeIntervalSince1970: 0), sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", name: "USB 01", hasMixerName: false, color: .init(hue: "off", inverted: false))])
        take.standIns = standIns
        try take.write(to: folder)
        let stem = try StemWriter.open(
            url: stems.appending(path: "01 USB 01.wav"),
            info: .init(sampleRate: 48_000, description: "USB 01", originator: "ShowRecorder", timeReference: 0, originationDate: Date(timeIntervalSince1970: 0)),
            resumingAt: nil)
        try [Float](repeating: 0, count: frames).withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    @Test("A kept stand-in Take is as long as its stand-ins, and the next Take starts after it in the Reaper project")
    func keptStandIn() throws {
        try writeTake(1, frames: 4_800, stemFolder: "Stand-in 9600", standIns: [.init(start: 9_600, end: 14_400)])
        try writeTake(2, frames: 4_800)

        let timeline = try Show(name: "2026-10-06 Show", folder: show, takeCount: 2).timeline()
        #expect(timeline.takes.map(\.frameCount) == [14_400, 4_800])
        #expect(timeline.takes[0].stems.isEmpty, "the stand-in's Stems aren't items yet")
        let project = String(decoding: ReaperExporter().project(for: timeline), as: UTF8.self)
        #expect(project.contains("POSITION 0.3000000000"), "Take 02 starts after Take 01's 14 400 frames")
    }

    @Test("Ordinary Takes keep their length from their Stems")
    func ordinaryTakes() throws {
        try writeTake(1, frames: 9_600)
        try writeTake(2, frames: 4_800)

        let timeline = try Show(name: "2026-10-06 Show", folder: show, takeCount: 2).timeline()
        #expect(timeline.takes.map(\.frameCount) == [9_600, 4_800])
        let project = String(decoding: ReaperExporter().project(for: timeline), as: UTF8.self)
        #expect(project.contains("POSITION 0.2000000000"))
    }
}
