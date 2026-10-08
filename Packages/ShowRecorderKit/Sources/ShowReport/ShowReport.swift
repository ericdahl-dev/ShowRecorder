import Foundation

/// A Show's report: every Take and each USB Channel's Stem and Source, read back from the Show folder.
///
/// Built only from what is on disk: each Take's `Take.json` and the Stems themselves. Durations come
/// from the Stems' data chunks, so they show what was actually written.
public struct ShowReport: Equatable, Sendable {
    public struct Take: Equatable, Sendable {
        public var number: Int
        public var folderName: String
        public var startedAt: Date
        public var sampleRate: Int
        public var usbChannels: [USBChannel]
        /// Markers placed during the Take: seconds from its start, and name.
        public var markers: [Marker] = []

        public struct Marker: Equatable, Sendable {
            public var seconds: Double
            public var name: String
        }

        /// Stretches of the Take missing from one Copy, held there as silence.
        public var gaps: [Gap] = []

        public struct Gap: Equatable, Sendable {
            /// "Device" or "Drive".
            public var copy: String
            public var startSeconds: Double
            public var endSeconds: Double
            /// "Repaired", "Repair failed", or "Not repaired" when Repair hasn't run for it.
            public var result: String
        }

        /// Stretches of one Copy the recorder lost because its writer couldn't keep up, held as silence.
        public var dropouts: [Dropout] = []

        public struct Dropout: Equatable, Sendable {
            /// "Device" or "Drive".
            public var copy: String
            public var startSeconds: Double
            public var endSeconds: Double
            public var lengthSeconds: Double { endSeconds - startSeconds }
        }

        /// How much of the start of the Take is Pre-roll: audio from before record was pressed. `startedAt` is
        /// the press; the Stems, Markers and Gaps all count from the start of the audio, this much earlier.
        public var preRollSeconds: Double?

        /// When the Take's audio starts: `startedAt`, or earlier by the Pre-roll.
        var audioStartedAt: Date { startedAt.addingTimeInterval(-(preRollSeconds ?? 0)) }

        /// The longest Stem's duration in seconds, or nil when no Stem could be read.
        public var duration: Double? {
            usbChannels.compactMap(\.duration).max()
        }
    }

    public struct USBChannel: Equatable, Sendable {
        public var usbChannel: Int
        public var stemFile: String
        public var sourceName: String
        public var hasMixerName: Bool
        public var hue: String
        public var inverted: Bool
        public var muted: Bool?
        public var fader: Float?
        public var inputSource: Int?
        /// The channel's loudest peak and its average level over the Take, in dBFS; -80 when silent. Nil in
        /// Takes made before levels were recorded.
        public var peakDbfs: Double?
        public var averageDbfs: Double?
        /// Samples in the Stem's data chunk, or nil when the Stem is missing or unreadable.
        public var sampleCount: UInt64?
        public var sampleRate: Int

        public var duration: Double? {
            sampleCount.map { Double($0) / Double(max(sampleRate, 1)) }
        }
    }

    public static let htmlFileName = "Report.html"
    public static let csvFileName = "Channels.csv"

    public var showName: String
    public var takes: [Take]

    /// Reads every Take folder in `showFolder` that has a `Take.json`, in Take order.
    public init(showFolder: URL) throws {
        let fm = FileManager.default
        let folders = try fm.contentsOfDirectory(at: showFolder, includingPropertiesForKeys: nil)
        var takes: [Take] = []
        for folder in folders {
            let json = folder.appending(path: TakeFile.fileName)
            guard fm.fileExists(atPath: json.path) else { continue }
            let file = try TakeFile.read(from: json)
            takes.append(Take(
                number: file.take,
                folderName: folder.lastPathComponent,
                startedAt: file.startedAt,
                sampleRate: file.sampleRate,
                usbChannels: file.usbChannels.map { channel in
                    USBChannel(
                        usbChannel: channel.usbChannel,
                        stemFile: channel.stemFile,
                        sourceName: channel.name,
                        hasMixerName: channel.hasMixerName,
                        hue: channel.color.hue,
                        inverted: channel.color.inverted,
                        muted: channel.muted,
                        fader: channel.fader,
                        inputSource: channel.inputSource,
                        peakDbfs: channel.peakDbfs,
                        averageDbfs: channel.averageDbfs,
                        sampleCount: StemDuration.sampleCount(of: folder.appending(path: channel.stemFile)),
                        sampleRate: file.sampleRate)
                },
                markers: (file.markers ?? []).map { marker in
                    Take.Marker(seconds: file.sampleRate > 0 ? Double(marker.position) / Double(file.sampleRate) : 0, name: marker.name)
                },
                gaps: (file.gaps ?? []).map { gap in
                    let rate = Double(max(file.sampleRate, 1))
                    let repair = (file.repairs ?? []).first { $0.copy == gap.copy && $0.start == gap.start && $0.end == gap.end }
                    let result = switch repair?.outcome {
                    case "repaired": "Repaired"
                    case nil: "Not repaired"
                    default: "Repair failed"
                    }
                    return Take.Gap(copy: gap.copy.capitalized, startSeconds: Double(gap.start) / rate, endSeconds: Double(gap.end) / rate, result: result)
                },
                dropouts: (file.dropouts ?? []).map { dropout in
                    let rate = Double(max(file.sampleRate, 1))
                    return Take.Dropout(copy: dropout.copy.capitalized, startSeconds: Double(dropout.start) / rate, endSeconds: Double(dropout.end) / rate)
                },
                preRollSeconds: (file.preRollFrames ?? 0) > 0 && file.sampleRate > 0
                    ? Double(file.preRollFrames ?? 0) / Double(file.sampleRate) : nil))
        }
        self.showName = showFolder.lastPathComponent
        self.takes = takes.sorted { $0.number < $1.number }
    }

    /// Writes `Report.html` and `Channels.csv` into `showFolder`, replacing any earlier ones.
    public static func write(showFolder: URL) throws {
        let report = try ShowReport(showFolder: showFolder)
        try Data(report.html.utf8).write(to: showFolder.appending(path: htmlFileName), options: .atomic)
        try Data(report.csv.utf8).write(to: showFolder.appending(path: csvFileName), options: .atomic)
    }

    // MARK: - CSV

    /// One row per Take and USB Channel, RFC 4180 quoting, CRLF line ends.
    public var csv: String {
        var rows = [["Take", "USB Channel", "Stem", "Source", "Mixer named", "Color", "Muted", "Fader", "Input source", "Duration (s)"]]
        for take in takes {
            for channel in take.usbChannels {
                rows.append([
                    String(take.number),
                    String(channel.usbChannel),
                    channel.stemFile,
                    channel.sourceName,
                    String(channel.hasMixerName),
                    channel.colorName,
                    channel.muted.map { String($0) } ?? "",
                    channel.fader.map { String($0) } ?? "",
                    channel.inputSource.map { String($0) } ?? "",
                    channel.duration.map { String(format: "%.3f", $0) } ?? "",
                ])
            }
        }
        return rows.map { $0.map(Self.csvField).joined(separator: ",") + "\r\n" }.joined()
    }

    static func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - HTML

    /// A self-contained page: inline styles, no scripts or external assets, light and dark.
    public var html: String {
        var out = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="color-scheme" content="light dark">
            <title>\(Self.escape(showName))</title>
            <style>
            \(Self.style)
            </style>
            </head>
            <body>
            <h1>\(Self.escape(showName))</h1>
            <p class="summary">\(takes.count == 1 ? "1 Take" : "\(takes.count) Takes")</p>

            """
        for take in takes {
            out += section(for: take)
        }
        out += "</body>\n</html>\n"
        return out
    }

    /// One Take: when it started, how long it ran, and every USB Channel's Stem and Source.
    /// Later sections (Markers, Gaps, Repairs, Dropouts) belong inside this section.
    private func section(for take: Take) -> String {
        var out = """
            <section>
            <h2>Take \(take.number)</h2>
            <dl>
            <dt>Started</dt><dd>\(Self.timestamp(take.audioStartedAt))</dd>
            \(Self.preRollRows(for: take))<dt>Duration</dt><dd>\(take.duration.map(Self.clock) ?? "unknown")</dd>
            <dt>Sample rate</dt><dd>\(take.sampleRate) Hz</dd>
            <dt>Folder</dt><dd>\(Self.escape(take.folderName))</dd>
            </dl>
            <div class="scroll"><table>
            <thead><tr><th>USB Channel</th><th>Source</th><th>Stem</th><th>Color</th><th>Muted</th><th>Fader</th><th>Input source</th><th>Duration</th></tr></thead>
            <tbody>

            """
        for channel in take.usbChannels {
            let note = channel.hasMixerName ? "" : " <span class=\"note\">(not named on the Mixer)</span>"
            let swatch = "<span class=\"swatch\" style=\"\(Self.swatchStyle(hue: channel.hue, inverted: channel.inverted))\"></span>"
            out += "<tr>"
            out += "<td class=\"num\">\(channel.usbChannel)</td>"
            out += "<td class=\"source\">\(Self.escape(channel.sourceName))\(note)</td>"
            out += "<td>\(Self.escape(channel.stemFile))</td>"
            out += "<td>\(swatch)\(Self.escape(channel.colorName))</td>"
            out += "<td>\(channel.muted.map { $0 ? "Muted" : "No" } ?? "")</td>"
            out += "<td class=\"num\">\(channel.fader.map { "\(Int(($0 * 100).rounded()))%" } ?? "")</td>"
            out += "<td class=\"num\">\(channel.inputSource.map(String.init) ?? "")</td>"
            out += "<td class=\"num\">\(channel.duration.map(Self.clock) ?? "missing")</td>"
            out += "</tr>\n"
        }
        out += "</tbody>\n</table></div>\n"
        if take.usbChannels.contains(where: { $0.peakDbfs != nil }) {
            out += "<h3>Levels</h3>\n<p class=\"note\">From when record was pressed. Average is the power average of the VU level, as on the meters.</p>\n<div class=\"scroll\"><table>\n<thead><tr><th>USB Channel</th><th>Source</th><th>Peak (dBFS)</th><th>Average (dBFS)</th></tr></thead>\n<tbody>\n"
            for channel in take.usbChannels {
                out += "<tr><td class=\"num\">\(channel.usbChannel)</td><td class=\"source\">\(Self.escape(channel.sourceName))</td><td class=\"num\">\(Self.level(channel.peakDbfs))</td><td class=\"num\">\(Self.level(channel.averageDbfs))</td></tr>\n"
            }
            out += "</tbody>\n</table></div>\n"
        }
        if !take.markers.isEmpty {
            out += "<h3>Markers</h3>\n<div class=\"scroll\"><table>\n<thead><tr><th>Time</th><th>Marker</th></tr></thead>\n<tbody>\n"
            for marker in take.markers {
                out += "<tr><td class=\"num\">\(Self.markerClock(marker.seconds))</td><td>\(Self.escape(marker.name))</td></tr>\n"
            }
            out += "</tbody>\n</table></div>\n"
        }
        if !take.gaps.isEmpty {
            out += "<h3>Gaps</h3>\n<p class=\"note\">Missing from that Copy and held as silence until repaired from the other Copy.</p>\n<div class=\"scroll\"><table>\n<thead><tr><th>Copy</th><th>From</th><th>To</th><th>Result</th></tr></thead>\n<tbody>\n"
            for gap in take.gaps {
                out += "<tr><td>\(Self.escape(gap.copy))</td><td class=\"num\">\(Self.markerClock(gap.startSeconds))</td><td class=\"num\">\(Self.markerClock(gap.endSeconds))</td><td>\(Self.escape(gap.result))</td></tr>\n"
            }
            out += "</tbody>\n</table></div>\n"
        }
        if !take.dropouts.isEmpty {
            out += "<h3>Dropouts</h3>\n<p class=\"note\">Audio the recorder couldn't keep up with. It is silence of the right length in that Copy's Stems.</p>\n<div class=\"scroll\"><table>\n<thead><tr><th>Copy</th><th>From</th><th>To</th><th>Length</th></tr></thead>\n<tbody>\n"
            for dropout in take.dropouts {
                out += "<tr><td>\(Self.escape(dropout.copy))</td><td class=\"num\">\(Self.markerClock(dropout.startSeconds))</td><td class=\"num\">\(Self.markerClock(dropout.endSeconds))</td><td class=\"num\">\(Self.markerClock(dropout.lengthSeconds))</td></tr>\n"
            }
            out += "</tbody>\n</table></div>\n"
        }
        out += "</section>\n"
        return out
    }

    /// A level in dBFS to a tenth, with "silent" for a channel that had no signal.
    private static func level(_ dbfs: Double?) -> String {
        guard let dbfs else { return "" }
        return dbfs <= -80 ? "silent" : String(format: "%.1f", dbfs)
    }

    /// For a Take with Pre-roll: when record was pressed and how much audio came before it. Marker and Gap
    /// times in the report count from the start of the audio, so "Started" is that moment, not the press.
    private static func preRollRows(for take: Take) -> String {
        guard let preRoll = take.preRollSeconds else { return "" }
        return """
            <dt>Record pressed</dt><dd>\(timestamp(take.startedAt))</dd>
            <dt>Pre-roll</dt><dd>\(String(format: "%.1f", preRoll)) s</dd>

            """
    }

    /// A Marker's time in the Take, to a tenth of a second ("1:05.3").
    static func markerClock(_ seconds: Double) -> String {
        let tenths = Int((seconds * 10).rounded(.down))
        return "\(clock(Double(tenths / 10))).\(tenths % 10)"
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for c in text {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }

    /// "1:05" or "1:02:03", whole seconds.
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Local time on the device that wrote the report.
    static func timestamp(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// Mixer hues map to fixed colors; an unknown hue is drawn like "off". Inverted is a filled swatch.
    static func swatchStyle(hue: String, inverted: Bool) -> String {
        let colors = [
            "red": "#e5484d", "green": "#30a46c", "yellow": "#f5d90a", "blue": "#3e63dd",
            "magenta": "#d6409f", "cyan": "#05a2c2", "white": "#e8e8ed",
        ]
        guard let color = colors[hue] else { return "border-color:var(--muted)" }
        return inverted ? "background:\(color);border-color:\(color)" : "border-color:\(color)"
    }

    static let style = """
        :root{--bg:#fff;--fg:#1c1c1e;--muted:#6e6e73;--line:#d1d1d6;--head:#f2f2f7}
        @media (prefers-color-scheme: dark){:root{--bg:#000;--fg:#f2f2f7;--muted:#98989d;--line:#38383a;--head:#1c1c1e}}
        *{box-sizing:border-box}
        body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:15px/1.4 -apple-system,system-ui,sans-serif;-webkit-text-size-adjust:100%}
        h1{font-size:1.6em;margin:0 0 4px;overflow-wrap:anywhere}
        h2{font-size:1.25em;margin:28px 0 8px}
        .summary,.note{color:var(--muted)}
        dl{display:grid;grid-template-columns:max-content 1fr;gap:2px 12px;margin:0 0 12px}
        dt{color:var(--muted)}
        dd{margin:0;overflow-wrap:anywhere}
        .scroll{overflow-x:auto;-webkit-overflow-scrolling:touch}
        table{border-collapse:collapse;width:100%;font-size:.9em}
        th,td{text-align:left;padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:top;white-space:nowrap}
        th{background:var(--head)}
        td.source{white-space:pre-wrap;min-width:8em}
        .num{text-align:right;font-variant-numeric:tabular-nums}
        .swatch{display:inline-block;width:.9em;height:.9em;margin-right:6px;border:2px solid;border-radius:3px;vertical-align:-.1em}
        """
}

extension ShowReport.USBChannel {
    /// "red", or "red inverted" for the X-Air style with colored background.
    var colorName: String { inverted ? "\(hue) inverted" : hue }
}

/// The parts of a Take's `Take.json` the report uses. Mirrors `TakeMetadata` in Recording.
struct TakeFile: Decodable {
    struct USBChannel: Decodable {
        struct Color: Decodable {
            var hue: String
            var inverted: Bool
        }

        var usbChannel: Int
        var stemFile: String
        var name: String
        var hasMixerName: Bool
        var color: Color
        var muted: Bool?
        var fader: Float?
        var inputSource: Int?
        var peakDbfs: Double?
        var averageDbfs: Double?
    }

    var take: Int
    var startedAt: Date
    var sampleRate: Int
    var usbChannels: [USBChannel]
    var markers: [Marker]?
    var gaps: [Gap]?
    var dropouts: [Gap]?
    var repairs: [Repair]?
    var preRollFrames: Int?

    struct Repair: Decodable {
        var copy: String
        var start: Int
        var end: Int
        var outcome: String
    }

    struct Gap: Decodable {
        var copy: String
        var start: Int
        var end: Int
    }

    struct Marker: Decodable {
        var position: Int
        var name: String
    }

    static let fileName = "Take.json"

    static func read(from url: URL) throws -> TakeFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeFile.self, from: Data(contentsOf: url))
    }
}

/// Reads a Stem's length from its chunk headers without loading the audio.
enum StemDuration {
    /// Samples in the data chunk (data size ÷ block align), capped at the bytes actually on disk.
    /// Reads RIFF and RF64 (EBU Tech 3306), where a 32-bit size of 0xFFFFFFFF defers to `ds64`.
    static func sampleCount(of url: URL) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd(), (try? handle.seek(toOffset: 0)) != nil,
              let riff = try? handle.read(upToCount: 12), riff.count == 12,
              riff.prefix(4) == Data("RIFF".utf8) || riff.prefix(4) == Data("RF64".utf8),
              riff.suffix(4) == Data("WAVE".utf8)
        else { return nil }

        var offset: UInt64 = 12
        var blockAlign: UInt64?
        var ds64DataSize: UInt64?
        while offset + 8 <= fileSize {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let header = try? handle.read(upToCount: 8), header.count == 8 else { return nil }
            let id = String(decoding: header.prefix(4), as: UTF8.self)
            let size = UInt64(header.littleEndianUInt32(at: 4))
            let body = offset + 8
            switch id {
            case "ds64":
                guard let ds64 = try? handle.read(upToCount: 16), ds64.count == 16 else { return nil }
                ds64DataSize = ds64.littleEndianUInt64(at: 8)
            case "fmt ":
                guard let fmt = try? handle.read(upToCount: 16), fmt.count == 16 else { return nil }
                blockAlign = UInt64(fmt.littleEndianUInt16(at: 12))
            case "data":
                guard let blockAlign, blockAlign > 0 else { return nil }
                let dataSize = size == 0xFFFF_FFFF ? ds64DataSize ?? (fileSize - body) : size
                return min(dataSize, fileSize - body) / blockAlign
            default:
                break
            }
            offset = body + size + (size % 2)
        }
        return nil
    }
}

private extension Data {
    func littleEndianUInt16(at offset: Int) -> UInt16 {
        UInt16(self[startIndex + offset]) | UInt16(self[startIndex + offset + 1]) << 8
    }

    func littleEndianUInt32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[startIndex + offset + $1]) << (8 * $1) }
    }

    func littleEndianUInt64(at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(self[startIndex + offset + $1]) << (8 * $1) }
    }
}
