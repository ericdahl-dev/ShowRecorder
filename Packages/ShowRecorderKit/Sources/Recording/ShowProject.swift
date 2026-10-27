import BroadcastWave
import Foundation
import MixerLink
import ProjectExport
import ShowReport

extension Show {
    /// Reads the Show folder: every Take folder's `Take.json`, with each Take's length taken from
    /// its Stems, or its kept stand-ins when they run longer (#629). USB Channels are named and colored from the latest Take they appear in.
    /// Take folders without a readable `Take.json` are left out.
    public func timeline() throws -> ShowTimeline {
        let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        // A folder whose name starts with "." isn't a Take, such as one a move set aside (#630).
        let metadata = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { takeFolder -> (folder: URL, take: TakeMetadata)? in
                guard let take = try? TakeMetadata.read(fromTakeFolder: takeFolder) else { return nil }
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
                guard let frames = try? StemFile.inspect(entry.folder.appending(path: channel.stemFile)).frameCount else { continue }
                frameCount = max(frameCount, frames)
                stems.append(.init(usbChannel: channel.usbChannel, path: "\(folderName)/\(channel.stemFile)", name: channel.name))
            }
            // A kept stand-in's Stems are under `Stand-in N/` and aren't items yet; the Take is still as long as its
            // stand-ins, so later Takes don't overlap it (#629).
            if let standIns = entry.take.standIns {
                frameCount = max(frameCount, UInt64(clamping: standIns.map(\.end).max() ?? 0))
            }
            return ShowTimeline.Take(
                number: entry.take.take, sampleRate: entry.take.sampleRate, frameCount: frameCount, stems: stems,
                markers: entry.take.markers.map { .init(position: $0.position, name: $0.name) }
                    // A rename on the Mixer is a marker only here: none in the Stems, no banner, no track or file renamed (#577).
                    + (entry.take.renames ?? []).map { .init(position: $0.position, name: "USB \($0.usbChannel): \($0.from) → \($0.to)") },
                routingChanges: (entry.take.routingChanges ?? []).map { .init(usbChannel: $0.usbChannel, position: $0.position, name: $0.to) })
        }
        return ShowTimeline(showName: name, usbChannels: channels.values.sorted { $0.number < $1.number }, takes: takes)
    }

    /// Everything recorded in the Show, from its Stems: each Take's length at its own sample rate (#328), from whichever
    /// Copy has it, so a Drive only Show counts its Takes on the Drive (#625). `take` is left out: the running one, whose
    /// time the record screen counts live. Throws when the Device's Show folder can't be read. Reads `driveFolder` without
    /// its security scope; for the record screen's Drive-aware total use `Recorder.showRecordedSeconds(leavingOut:)`.
    public func recordedSeconds(leavingOut take: Int?) throws -> Double {
        try recordedSeconds(leavingOut: take, driveShow: driveFolder)
    }

    /// `recordedSeconds(leavingOut:)` with the Drive Copy at `driveShow`.
    func recordedSeconds(leavingOut take: Int?, driveShow: URL?) throws -> Double {
        _ = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        return ShowList.takeLengths(deviceShow: folder, driveShow: driveShow)
            .filter { $0.take.take != take }
            .reduce(0) { $0 + ($1.take.sampleRate > 0 ? Double($1.frames) / Double($1.take.sampleRate) : 0) }
    }

    /// Writes every DAW project the Show folder carries (Reaper for now). Called when a Take finalizes.
    func writeProjects() throws {
        try writeProject(using: ReaperExporter())
    }

    /// Rewrites the Show report and Reaper project after the Show's files change, such as a rename: each when the
    /// License allows it, or when it is already there, so a kept report never shows stale names (#438).
    static func refreshExtras(showFolder: URL, allowed: Bool) {
        let show = Show(name: showFolder.lastPathComponent, folder: showFolder, takeCount: 0)
        let fm = FileManager.default
        if allowed || fm.fileExists(atPath: showFolder.appending(path: ShowReport.htmlFileName).path) {
            try? ShowReport.write(showFolder: showFolder)
        }
        if allowed || fm.fileExists(atPath: showFolder.appending(path: "\(show.name).\(ReaperExporter().fileExtension)").path) {
            try? show.writeProjects()
        }
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
