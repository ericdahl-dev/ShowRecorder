import AudioIO
import Foundation
import MixerLink
import ProjectExport
import Recording
import Testing

@MainActor
@Suite("Reaper project")
struct ReaperProjectTests {
    /// 2026-10-06 21:30:00 local time.
    static let showDay: Date = {
        var components = DateComponents(year: 2026, month: 10, day: 6, hour: 21, minute: 30)
        components.timeZone = .current
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    let root: URL
    let device: FakeAudioDevice
    let recorder: Recorder

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ReaperProjectTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        device = FakeAudioDevice(inputChannelCount: 3)
        recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(device)
    }

    var showFolder: URL { root.appending(path: "2026-10-06 Show") }
    var projectFile: URL { showFolder.appending(path: "2026-10-06 Show.RPP") }

    /// Records one Take of `frames` frames with the given Sources.
    func recordTake(frames: Int, sources: [Source]) throws {
        try recorder.startTake(sources: sources)
        var left = frames
        while left > 0 {
            let n = min(left, 480)
            device.deliver(Array(repeating: Array(repeating: 0, count: n), count: 3))
            left -= n
        }
        try recorder.stopTake()
    }

    func project() throws -> RPPNode {
        try RPPNode.parse(String(contentsOf: projectFile, encoding: .utf8))
    }

    @Test("Finalizing a Take writes <Show name>.RPP with one track per USB Channel, in order")
    func oneTrackPerUSBChannel() throws {
        try recordTake(frames: 4_800, sources: [
            Source(name: "Kick", color: .off),
            Source(name: "Snare", color: .off),
            Source(name: "Lead Vocal", color: .off),
        ])

        let rpp = try project()
        #expect(rpp.tag == "REAPER_PROJECT")
        #expect(rpp.children("TRACK").map { $0.value("NAME") } == ["Kick", "Snare", "Lead Vocal"])
    }

    @Test("Tracks are named and colored from the latest Take")
    func namesAndColorsFromLatestTake() throws {
        try recordTake(frames: 4_800, sources: [
            Source(name: "Kick", color: MixerColor(hue: .red, inverted: false)),
            Source(name: "Snare", color: .off),
            Source(name: "Vox", color: .off),
        ])
        try recordTake(frames: 4_800, sources: [
            Source(name: "Kick In", color: MixerColor(hue: .blue, inverted: true)),
            Source(name: "Snare", color: MixerColor(hue: .yellow, inverted: false)),
            Source(name: "Lead Vocal", color: .off),
        ])

        let tracks = try project().children("TRACK")
        #expect(tracks.map { $0.value("NAME") } == ["Kick In", "Snare", "Lead Vocal"])
        #expect(tracks.map { $0.value("PEAKCOL") } == [
            String(ReaperExporter.peakColor(MixerColor(hue: .blue, inverted: true))),
            String(ReaperExporter.peakColor(MixerColor(hue: .yellow, inverted: false))),
            "16576",
        ])
    }

    @Test("Mixer hues map to distinct custom Reaper colors; inverted keeps the hue; off is Reaper's default")
    func hueMapping() {
        let custom = MixerColor.Hue.allCases.filter { $0 != .off }.map { ReaperExporter.peakColor(MixerColor(hue: $0, inverted: false)) }
        #expect(Set(custom).count == custom.count)
        #expect(custom.allSatisfy { $0 & 0x100_0000 != 0 }, "custom-color flag set")
        #expect(ReaperExporter.peakColor(MixerColor(hue: .red, inverted: false)) == 0x100_0000 | 0x2F_32DC, "red is RGB(220, 50, 47), stored BGR")
        for hue in MixerColor.Hue.allCases {
            #expect(ReaperExporter.peakColor(MixerColor(hue: hue, inverted: true)) == ReaperExporter.peakColor(MixerColor(hue: hue, inverted: false)))
        }
        #expect(ReaperExporter.peakColor(.off) == 16_576)
    }

    @Test("Each Take's Stems sit one after another, named from that Take, with paths relative to the Show folder")
    func itemsPlacedOneAfterAnother() throws {
        try recordTake(frames: 24_000, sources: [Source(name: "Kick", color: .off), Source(name: "Snare", color: .off)])
        try recordTake(frames: 72_000, sources: [Source(name: "Kick In", color: .off), Source(name: "Snare", color: .off)])

        let tracks = try project().children("TRACK")
        #expect(tracks.count == 3)
        let kick = try #require(tracks.first).children("ITEM")
        #expect(kick.map { $0.double("POSITION") } == [0, 0.5])
        #expect(kick.map { $0.double("LENGTH") } == [0.5, 1.5])
        #expect(kick.map { $0.value("NAME") } == ["Kick", "Kick In"])
        #expect(kick.map { $0.child("SOURCE")?.values } == [["WAVE"], ["WAVE"]])
        #expect(kick.map { $0.child("SOURCE")?.value("FILE") } == ["Take 01/01 Kick.wav", "Take 02/01 Kick In.wav"])
        let third = tracks[2].children("ITEM")
        #expect(third.map { $0.child("SOURCE")?.value("FILE") } == ["Take 01/03 USB 03.wav", "Take 02/03 USB 03.wav"])

        // Every path resolves from the Show folder to a real Stem.
        for item in tracks.flatMap({ $0.children("ITEM") }) {
            let path = try #require(item.child("SOURCE")?.value("FILE"))
            #expect(FileManager.default.fileExists(atPath: showFolder.appending(path: path).path), "\(path)")
        }
    }

    @Test("A Take with Pre-roll is placed from the start of its Pre-roll, and its Markers are on the same timeline as its Stems")
    func preRollTake() throws {
        let armed = FakeAudioDevice(inputChannelCount: 3)
        let withPreRoll = Recorder(deviceFolder: root, now: { Self.showDay }, preRollSeconds: 1)
        try withPreRoll.arm(armed)
        func deliver(_ frames: Int) { armed.deliver(Array(repeating: Array(repeating: 0, count: frames), count: 3)) }
        deliver(48_000)  // 1 s while Armed
        try withPreRoll.startTake()
        deliver(12_000)
        withPreRoll.addMarker(named: "Chorus")  // 0.25 s after the press
        deliver(12_000)
        try withPreRoll.stopTake()

        let rpp = try project()
        let track = try #require(rpp.children("TRACK").first)
        let item = try #require(track.children("ITEM").first)
        #expect(item.double("POSITION") == 0)
        #expect(item.double("LENGTH") == 1.5, "1 s of Pre-roll and 0.5 s recorded")
        let markers = rpp.all("MARKER")
        #expect(markers.map { $0[2] } == ["Take 01", "Chorus"])
        #expect(markers.map { Double($0[1]) } == [0, 1.25], "the Marker is 1.25 s into the Stem, 0.25 s after the press")
    }

    @Test("A project marker sits at the start of each Take")
    func markerAtEachTakeStart() throws {
        try recordTake(frames: 24_000, sources: [])
        try recordTake(frames: 72_000, sources: [])
        try recordTake(frames: 4_800, sources: [])

        let rpp = try project()
        #expect(rpp.value("SAMPLERATE") == "48000")
        let markers = rpp.all("MARKER")
        #expect(markers.map { $0[0] } == ["1", "2", "3"])
        #expect(markers.map { Double($0[1]) } == [0, 0.5, 2])
        #expect(markers.map { $0[2] } == ["Take 01", "Take 02", "Take 03"])
        #expect(markers.map { $0[3] } == ["0", "0", "0"], "point markers, not regions")
    }

    @Test("Names with quotes survive Reaper's quoting", arguments: [
        (#"12" Snare"#, #"12" Snare"#),
        ("Rob's Vox", "Rob's Vox"),
        (#"Rob's "Box""#, #"Rob's "Box""#),
        (#"Rob's "`Box`""#, #"Rob's "'Box'""#),  // all three quote marks: backticks become '
    ])
    func quotedNames(name: String, expected: String) throws {
        try recordTake(frames: 480, sources: [Source(name: name, color: .off)])

        let track = try #require(try project().children("TRACK").first)
        #expect(track.value("NAME") == expected)
        #expect(track.children("ITEM").first?.value("NAME") == expected)
    }

    @Test("The exporter renders a Show it is handed, with no Show folder")
    func rendersAnyTimeline() throws {
        let show = ShowTimeline(
            showName: "Fixture",
            usbChannels: [.init(number: 1, name: "Main L", color: MixerColor(hue: .white, inverted: false))],
            takes: [
                .init(number: 1, sampleRate: 44_100, frameCount: 44_100, stems: [.init(usbChannel: 1, path: "Take 01/01 Main L.wav", name: "Main L")]),
                .init(number: 2, sampleRate: 44_100, frameCount: 22_050, stems: []),
                .init(number: 3, sampleRate: 44_100, frameCount: 441, stems: [.init(usbChannel: 1, path: "Take 03/01 Mix.wav", name: "Mix")]),
            ])
        let exporter: any ProjectExporter = ReaperExporter()
        #expect(exporter.fileExtension == "RPP")

        let rpp = try RPPNode.parse(String(decoding: exporter.project(for: show), as: UTF8.self))
        let items = try #require(rpp.child("TRACK")).children("ITEM")
        #expect(items.map { $0.double("POSITION") } == [0, 1.5], "a Take missing a Stem leaves a hole, not a shift")
        #expect(items.map { $0.double("LENGTH") } == [1, 0.01])
        #expect(rpp.all("MARKER").map { Double($0[1]) } == [0, 1, 1.5])
    }
}
