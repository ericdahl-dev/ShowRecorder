import AudioIO
@testable import BroadcastWave
import Foundation
import MixerLink
@testable import Recording
import ShowReport
import Testing

@MainActor
@Suite("Show report")
struct ShowReportTests {
    static let showDay: Date = {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (2026, 10, 6, 21, 30, 0)
        return Calendar.current.date(from: c)!
    }()

    static let hostileName = "Kick, \"the\" <script>alert('x')</script>\nDrum & Bass"

    let root: URL
    var show: URL { root.appending(path: "2026-10-06 Show") }

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShowReportTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Records one Take per entry in `takes`, each `frames` long, into one Show.
    func record(channels: Int, sources: [Source], takes frames: [Int]) async throws {
        let device = FakeAudioDevice(inputChannelCount: channels)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(device)
        for count in frames {
            try recorder.startTake(sources: sources)
            var left = count
            while left > 0 {
                let block = min(left, 480)
                device.deliver(Array(repeating: Array(repeating: 0, count: block), count: channels))
                left -= block
                // The fake runs faster than real time: let the writer catch up before the ring fills.
                while recorder.bufferedFrameCount > 48_000 * 2 {
                    try await Task.sleep(for: .milliseconds(2))
                }
            }
            try recorder.stopTake()
        }
        #expect(recorder.droppedFrameCount == 0)
    }

    func csvRows() throws -> [[String]] {
        try CSV.parse(String(contentsOf: show.appending(path: "Channels.csv"), encoding: .utf8))
    }

    @Test("Stopping a Take writes Channels.csv with one row per Take and USB Channel")
    func csvRowsAfterTake() async throws {
        try await record(channels: 2, sources: [
            Source(name: "Kick", color: MixerColor(hue: .red, inverted: false), isMuted: false, fader: 0.75, inputSource: 1),
            Source.fallback(usbChannel: 2),
        ], takes: [48_000 * 3 + 480])

        let rows = try csvRows()
        #expect(rows == [
            ["Take", "USB Channel", "Stem", "Source", "Mixer named", "Color", "Muted", "Fader", "Input source", "Duration (s)"],
            ["1", "1", "01 Kick.wav", "Kick", "true", "red", "false", "0.75", "1", "3.010"],
            ["1", "2", "02 USB 02.wav", "USB 02", "false", "off", "", "", "", "3.010"],
        ])
    }

    @Test("A Source name with commas, quotes, a line break and markup survives the CSV")
    func hostileNameInCSV() async throws {
        try await record(channels: 1, sources: [
            Source(name: Self.hostileName, color: MixerColor(hue: .cyan, inverted: true)),
        ], takes: [480])

        let rows = try csvRows()
        #expect(rows.count == 2)
        #expect(rows[1][3] == Self.hostileName)
        #expect(rows[1][5] == "cyan inverted")
        #expect(rows[1].count == rows[0].count)
    }

    @Test("Every Take is listed in order with its own duration, and the report is rewritten after each")
    func everyTakeInOrder() async throws {
        try await record(channels: 1, sources: [Source(name: "Vox", color: .off)], takes: [48_000, 24_000, 96_000])

        let rows = try csvRows()
        #expect(rows.dropFirst().map { [$0[0], $0[9]] } == [["1", "1.000"], ["2", "0.500"], ["3", "2.000"]])
    }

    @Test("A missing Stem is reported with no duration instead of a guess")
    func missingStem() async throws {
        try await record(channels: 2, sources: [], takes: [480])
        let take = show.appending(path: "Take 01")
        try FileManager.default.removeItem(at: take.appending(path: "02 USB 02.wav"))

        try ShowReport.write(showFolder: show)

        let rows = try csvRows()
        #expect(rows[1][9] == "0.010")
        #expect(rows[2][9] == "")
        #expect(try ShowReport(showFolder: show).takes[0].duration == 0.01)
    }

    @Test("A Stem promoted to RF64 reports its duration from ds64")
    func rf64StemDuration() throws {
        let take = show.appending(path: "Take 01")
        try FileManager.default.createDirectory(at: take, withIntermediateDirectories: true)
        try Data("""
            {"show": "2026-10-06 Show", "take": 1, "startedAt": "2026-10-06T21:30:00Z", "sampleRate": 48000,
             "timeReference": 0, "usbChannels": [{"usbChannel": 1, "stemFile": "01 Kick.wav", "name": "Kick",
             "hasMixerName": true, "color": {"hue": "red", "inverted": false}}]}
            """.utf8).write(to: take.appending(path: "Take.json"))
        let stem = try StemWriter(
            url: take.appending(path: "01 Kick.wav"),
            info: .init(sampleRate: 48_000, description: "Kick", originator: "ShowRecorder", timeReference: 0, originationDate: Self.showDay),
            rf64Threshold: 1_000)
        let samples = [Float](repeating: 0, count: 24_000)
        try samples.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
        let head = try FileHandle(forReadingFrom: take.appending(path: "01 Kick.wav")).read(upToCount: 4)
        #expect(head == Data("RF64".utf8))

        try ShowReport.write(showFolder: show)

        #expect(try csvRows()[1][9] == "0.500")
    }

    @Test("Report.html names the Show, each Take and each Source, with names escaped")
    func htmlListsTakesAndSources() async throws {
        try await record(channels: 2, sources: [
            Source(name: Self.hostileName, color: MixerColor(hue: .red, inverted: false), isMuted: true, fader: 0.5, inputSource: 3),
            Source(name: "Lead Vocal", color: MixerColor(hue: .yellow, inverted: true)),
        ], takes: [48_000 * 65, 480])

        let html = try String(contentsOf: show.appending(path: "Report.html"), encoding: .utf8)
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<title>2026-10-06 Show</title>"))
        #expect(html.contains("Take 1"))
        #expect(html.contains("Take 2"))
        #expect(html.contains("Lead Vocal"))
        #expect(html.contains("1:05"), "Take 1 lasts 65 seconds")
        #expect(!html.contains("<script>"))
        #expect(!html.contains(Self.hostileName))
        #expect(html.contains("Kick, &quot;the&quot; &lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt;"))
        #expect(html.contains("Drum &amp; Bass"))
        #expect(html.contains("prefers-color-scheme: dark"))
        #expect(!html.contains("http://") && !html.contains("https://") && !html.contains("src="), "self-contained")
    }
}

/// A small RFC 4180 reader: quoted fields may hold commas, doubled quotes and line breaks.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars.removeFirst() } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\r\n" || c == "\n" {
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
