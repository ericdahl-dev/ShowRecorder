import Foundation
import MixerLink

/// Writes a Reaper project (.RPP): one track per USB Channel, each Take's Stems placed one after
/// another, and a project marker at the start of each Take. Stem paths are relative to the
/// Show folder, where the project is saved, so the Show folder can be moved or copied whole.
public struct ReaperExporter: ProjectExporter {
    public init() {}

    public var fileExtension: String { "RPP" }

    public func project(for show: ShowTimeline) -> [UInt8] {
        // Each Take starts where the previous one ends.
        var starts: [Double] = []
        var position = 0.0
        for take in show.takes {
            starts.append(position)
            position += take.duration
        }

        var out = "<REAPER_PROJECT 0.1 \"7.0/ShowRecorder\" 0\n"
        if let sampleRate = show.takes.last?.sampleRate {
            out += "  SAMPLERATE \(sampleRate) 0 0\n"
        }
        for (index, take) in show.takes.enumerated() {
            out += "  MARKER \(index + 1) \(Self.seconds(starts[index])) \(Self.quote(Self.takeName(take.number))) 0 0\n"
        }
        for track in show.usbChannels {
            out += "  <TRACK\n"
            out += "    NAME \(Self.quote(track.name))\n"
            out += "    PEAKCOL \(Self.peakColor(track.color))\n"
            for (index, take) in show.takes.enumerated() {
                guard let stem = take.stems.first(where: { $0.usbChannel == track.number }) else { continue }
                out += "    <ITEM\n"
                out += "      POSITION \(Self.seconds(starts[index]))\n"
                out += "      LENGTH \(Self.seconds(take.duration))\n"
                out += "      NAME \(Self.quote(stem.name))\n"
                out += "      <SOURCE WAVE\n"
                out += "        FILE \(Self.quote(stem.path))\n"
                out += "      >\n"
                out += "    >\n"
            }
            out += "  >\n"
        }
        out += ">\n"
        return Array(out.utf8)
    }

    static func takeName(_ number: Int) -> String {
        String(format: "Take %02d", number)
    }

    /// Seconds with sub-sample precision and no exponent.
    static func seconds(_ value: Double) -> String {
        String(format: "%.10f", value)
    }

    /// The track color for a Mixer color, as Reaper's PEAKCOL: `0x01000000 | B << 16 | G << 8 | R`
    /// (the flag marks a custom color). Each scribble-strip hue maps to a fixed, slightly softened
    /// RGB so tracks read on Reaper's dark and light themes:
    ///
    /// | Hue     | RGB             |
    /// |---------|-----------------|
    /// | red     | 220, 50, 47     |
    /// | green   | 60, 180, 75     |
    /// | yellow  | 230, 200, 40    |
    /// | blue    | 50, 110, 220    |
    /// | magenta | 200, 60, 200    |
    /// | cyan    | 40, 190, 210    |
    /// | white   | 230, 230, 230   |
    ///
    /// Inverted is how the scribble strip draws the hue (colored background), not a different
    /// color, so it maps to the same RGB. Off has no color and gets Reaper's default, 16576.
    public static func peakColor(_ color: MixerColor) -> Int {
        let rgb: (r: Int, g: Int, b: Int)
        switch color.hue {
        case .off: return 16_576
        case .red: rgb = (220, 50, 47)
        case .green: rgb = (60, 180, 75)
        case .yellow: rgb = (230, 200, 40)
        case .blue: rgb = (50, 110, 220)
        case .magenta: rgb = (200, 60, 200)
        case .cyan: rgb = (40, 190, 210)
        case .white: rgb = (230, 230, 230)
        }
        return 0x100_0000 | rgb.b << 16 | rgb.g << 8 | rgb.r
    }

    /// Reaper's quoting: plain when safe, otherwise the first of `"`, `'` or `` ` `` the string
    /// doesn't contain. If it contains all three, backticks become `'`.
    static func quote(_ string: String) -> String {
        for mark in ["\"", "'", "`"] where !string.contains(mark) {
            return mark + string + mark
        }
        return "`" + string.replacingOccurrences(of: "`", with: "'") + "`"
    }
}
