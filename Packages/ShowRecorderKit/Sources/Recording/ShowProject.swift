import BroadcastWave
import Foundation
import MixerLink
import ProjectExport

extension Show {
    /// Reads the Show folder: every Take folder's `Take.json`, with each Take's length taken from
    /// its Stems. USB Channels are named and colored from the latest Take they appear in.
    /// Take folders without a readable `Take.json` are left out.
    public func timeline() throws -> ShowTimeline {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let metadata = entries
            .compactMap { takeFolder -> (folder: URL, take: TakeMetadata)? in
                guard let data = try? Data(contentsOf: takeFolder.appending(path: TakeMetadata.fileName)),
                      let take = try? decoder.decode(TakeMetadata.self, from: data)
                else { return nil }
                return (takeFolder, take)
            }
            .sorted { $0.take.take < $1.take.take }

        var channels: [Int: ShowTimeline.USBChannel] = [:]
        let takes = metadata.map { entry in
            let folderName = entry.folder.lastPathComponent
            var frameCount: UInt64 = 0
            var stems: [ShowTimeline.Stem] = []
            for channel in entry.take.usbChannels {
                channels[channel.usbChannel] = ShowTimeline.USBChannel(
                    number: channel.usbChannel, name: channel.name, color: channel.color.mixerColor)
                guard let frames = try? StemLength.frameCount(at: entry.folder.appending(path: channel.stemFile)) else { continue }
                frameCount = max(frameCount, frames)
                stems.append(.init(usbChannel: channel.usbChannel, path: "\(folderName)/\(channel.stemFile)", name: channel.name))
            }
            return ShowTimeline.Take(number: entry.take.take, sampleRate: entry.take.sampleRate, frameCount: frameCount, stems: stems)
        }
        return ShowTimeline(showName: name, usbChannels: channels.values.sorted { $0.number < $1.number }, takes: takes)
    }

    /// Writes every DAW project the Show folder carries (Reaper for now). Called when a Take finalizes.
    func writeProjects() throws {
        try writeProject(using: ReaperExporter())
    }

    /// Writes "<Show name>.<extension>" into the Show folder, replacing any earlier one.
    public func writeProject(using exporter: some ProjectExporter) throws {
        let file = folder.appending(path: "\(name).\(exporter.fileExtension)")
        try Data(exporter.project(for: timeline())).write(to: file, options: .atomic)
    }
}

extension TakeMetadata.USBChannel.Color {
    var mixerColor: MixerColor {
        MixerColor(hue: MixerColor.Hue.allCases.first { $0.name == hue } ?? .off, inverted: inverted)
    }
}
