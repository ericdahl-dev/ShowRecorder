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

    @Test("A Take with Pre-roll reports when its audio started, when record was pressed, and the Pre-roll, with Marker times from the audio start")
    func preRollInReport() async throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay }, preRollSeconds: 1)
        try recorder.arm(device)
        device.deliver([Array(repeating: 0, count: 48_000)])  // 1 s while Armed
        try recorder.startTake()
        device.deliver([Array(repeating: 0, count: 12_000)])
        recorder.addMarker(named: "Chorus")  // 0.25 s after the press, 1.25 s into the audio
        device.deliver([Array(repeating: 0, count: 12_000)])
        try recorder.stopTake()

        let report = try ShowReport(showFolder: show)
        let take = try #require(report.takes.first)
        #expect(take.preRollSeconds == 1)
        #expect(take.duration == 1.5, "the Stems hold the Pre-roll and the live audio")
        #expect(take.markers.map(\.seconds) == [1.25])

        let html = report.html
        #expect(html.contains("<dt>Started</dt><dd>2026-10-06 21:29:59</dd>"), "the audio starts a second before the press")
        #expect(html.contains("<dt>Record pressed</dt><dd>2026-10-06 21:30:00</dd>"))
        #expect(html.contains("<dt>Pre-roll</dt><dd>1.0 s</dd>"))
        #expect(html.contains("0:01.2"), "the Marker, from the start of the audio")
    }

    @Test("A Take without Pre-roll is reported as before")
    func noPreRollInReport() async throws {
        try await record(channels: 1, sources: [], takes: [480])
        let report = try ShowReport(showFolder: show)
        #expect(report.takes.first?.preRollSeconds == nil)
        #expect(report.html.contains("<dt>Started</dt><dd>2026-10-06 21:30:00</dd>"))
        #expect(!report.html.contains("Record pressed"))
        #expect(!report.html.contains("Pre-roll"))
    }

    /// Records a Take of 0.5 s, then 300,000 frames at once (more than a ring holds, so it is dropped), then 480.
    func recordWithADropout() throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(device)
        try recorder.startTake()
        device.deliver([Array(repeating: 0, count: 24_000)])
        device.deliver([Array(repeating: 0, count: 300_000)])
        device.deliver([Array(repeating: 0, count: 480)])
        try recorder.stopTake()
    }

    @Test("A Take that lost audio lists each Dropout with its Copy and times")
    func dropoutsInReport() throws {
        try recordWithADropout()
        let take = try #require(try ShowReport(showFolder: show).takes.first)
        #expect(take.dropouts.map(\.copy) == ["Device"])
        #expect(take.dropouts.map(\.startSeconds) == [0.5])
        #expect(take.dropouts.map(\.endSeconds) == [6.75])
        #expect(take.dropouts.first?.lengthSeconds == 6.25)
    }

    @Test("Report.html has a Dropouts section for a Take that lost audio")
    func dropoutsSection() throws {
        try recordWithADropout()
        let html = try String(contentsOf: show.appending(path: "Report.html"), encoding: .utf8)
        #expect(html.contains("<h3>Dropouts</h3>"))
        #expect(html.contains("0:00.5") && html.contains("0:06.7"), "from and to, to a tenth of a second")
        #expect(html.contains("Device"))
    }

    @Test("A Take lists the Source renames made on the Mixer during it, with times from the audio start, and escapes the names")
    func renamesInReport() async throws {
        let device = FakeAudioDevice(inputChannelCount: 1)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(device)
        try recorder.startTake(sources: [Source(name: "Kick", color: .off)])
        device.deliver([Array(repeating: 0, count: 24_000)])  // 0.5 s
        recorder.offerSources([Source(name: "<b>Bass</b> Drum", color: .off)])
        device.deliver([Array(repeating: 0, count: 24_000)])
        try recorder.stopTake()

        let report = try ShowReport(showFolder: show)
        let rename = try #require(report.takes.first?.renames.first)
        #expect(rename.seconds == 0.5)
        #expect((rename.usbChannel, rename.from, rename.to) == (1, "Kick", "<b>Bass</b> Drum"))
        let html = report.html
        #expect(html.contains("<h3>Renames on the mixer</h3>"))
        #expect(html.contains("0:00.5") && html.contains("&lt;b&gt;Bass&lt;/b&gt; Drum"))
    }

    @Test("A Take with no renames has no renames section")
    func noRenamesSection() async throws {
        try await record(channels: 1, sources: [], takes: [480])
        let html = try String(contentsOf: show.appending(path: "Report.html"), encoding: .utf8)
        #expect(!html.contains("Renames"))
    }

    @Test("A Take with no Dropouts reports as before, with no Dropouts section")
    func noDropoutsSection() async throws {
        try await record(channels: 1, sources: [], takes: [480])
        let html = try String(contentsOf: show.appending(path: "Report.html"), encoding: .utf8)
        #expect(!html.contains("Dropouts"))
    }

    /// Records a Take of 1 s of a steady 0.1 on channel 1 and silence on channel 2.
    func recordWithLevels() throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { Self.showDay })
        try recorder.arm(device)
        try recorder.startTake()
        device.deliver([Array(repeating: 0.1, count: 48_000), Array(repeating: 0, count: 48_000)])
        try recorder.stopTake()
    }

    @Test("A Take lists each channel's peak and average level, and Report.html has a Levels table")
    func levelsInReport() throws {
        try recordWithLevels()
        let report = try ShowReport(showFolder: show)
        let channels = try #require(report.takes.first?.usbChannels)
        #expect(abs(try #require(channels[0].peakDbfs) + 20) < 0.01)
        #expect(abs(try #require(channels[0].averageDbfs) - 20 * log10(0.1 * 1.1107207345)) < 0.01)
        let html = try String(contentsOf: show.appending(path: "Report.html"), encoding: .utf8)
        #expect(html.contains("<h3>Levels</h3>"))
        #expect(html.contains("-20.0") && html.contains("-19.1"), "to a tenth of a dB")
        #expect(html.contains("silent"), "a silent channel isn't -80")
    }

    @Test("A Take from before levels were recorded has no Levels section")
    func noLevelsSection() throws {
        try recordWithLevels()
        let takeJSON = show.appending(path: "Take 01/Take.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: takeJSON)) as? [String: Any])
        var channels = try #require(object["usbChannels"] as? [[String: Any]])
        for index in channels.indices {
            channels[index].removeValue(forKey: "peakDbfs")
            channels[index].removeValue(forKey: "averageDbfs")
        }
        object["usbChannels"] = channels
        try JSONSerialization.data(withJSONObject: object).write(to: takeJSON)
        let report = try ShowReport(showFolder: show)
        #expect(!report.html.contains("Levels"))
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
