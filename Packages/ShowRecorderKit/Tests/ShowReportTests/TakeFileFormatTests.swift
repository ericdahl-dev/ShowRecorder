@testable import BroadcastWave
import Foundation
import MixerLink
import ProjectExport
@testable import Recording
import ShowReport
import Testing

/// A Take folder as current builds write it, read back by the Show report and the Reaper export. Pins what
/// both make of every field in `Take.json`, so a change to how `Take.json` is read can't change either.
@Suite("Take.json as the Show report and Reaper export read it")
struct TakeFileFormatTests {
    let show: URL
    var take: URL { show.appending(path: "Take 02") }

    static let takeJSON = """
        {
          "dropouts" : [ { "copy" : "device", "end" : 50480, "start" : 50000 } ],
          "gaps" : [
            { "copy" : "drive", "end" : 48000, "start" : 0 },
            { "copy" : "drive", "end" : 120000, "start" : 96000 },
            { "copy" : "device", "end" : 4800, "start" : 2400 }
          ],
          "markers" : [
            { "name" : "Verse", "origin" : "operator", "position" : 48000 },
            { "name" : "Dropout", "origin" : "dropout", "position" : 96000 }
          ],
          "preRollFrames" : 24000,
          "renames" : [ { "from" : "Kick", "position" : 72000, "to" : "Kick In", "usbChannel" : 1 } ],
          "repairs" : [
            { "copy" : "drive", "end" : 48000, "outcome" : "repaired", "start" : 0 },
            { "copy" : "drive", "end" : 120000, "outcome" : "failed", "start" : 96000 }
          ],
          "sampleRate" : 48000,
          "show" : "2026-10-06 Show",
          "startedAt" : "2026-10-06T21:30:00Z",
          "take" : 2,
          "timeReference" : 3801600000,
          "usbChannels" : [
            {
              "averageDbfs" : -21.5, "color" : { "hue" : "red", "inverted" : false }, "fader" : 0.75,
              "hasMixerName" : true, "inputSource" : 1, "muted" : false, "name" : "Kick",
              "nameArrivedLate" : true, "peakDbfs" : -3.25, "stemFile" : "01 Kick.wav", "usbChannel" : 1
            },
            {
              "color" : { "hue" : "off", "inverted" : false }, "hasMixerName" : false,
              "name" : "USB 02", "stemFile" : "02 USB 02.wav", "usbChannel" : 2
            }
          ]
        }
        """

    init() throws {
        show = FileManager.default.temporaryDirectory.appending(path: "TakeFileFormatTests-\(UUID().uuidString)/2026-10-06 Show")
        try FileManager.default.createDirectory(at: show.appending(path: "Take 02"), withIntermediateDirectories: true)
        try Data(Self.takeJSON.utf8).write(to: take.appending(path: "Take.json"))
        // Channel 1 a plain RIFF Stem, channel 2 promoted to RF64.
        try writeStem("01 Kick.wav", frames: 144_000, rf64Threshold: nil)
        try writeStem("02 USB 02.wav", frames: 120_000, rf64Threshold: 1_000)
    }

    func writeStem(_ name: String, frames: Int, rf64Threshold: UInt64?) throws {
        let info = StemWriter.Info(sampleRate: 48_000, description: name, originator: "ShowRecorder", timeReference: 0, originationDate: Date(timeIntervalSince1970: 0))
        let stem = if let rf64Threshold {
            try StemWriter(url: take.appending(path: name), info: info, rf64Threshold: rf64Threshold)
        } else {
            try StemWriter(url: take.appending(path: name), info: info)
        }
        let samples = [Float](repeating: 0, count: frames)
        try samples.withUnsafeBufferPointer { try stem.append($0) }
        try stem.finalize()
    }

    /// A Take folder a move has set aside (`.moved Take 02`, #630), with the same files as the Take.
    func setAside() throws {
        try FileManager.default.copyItem(at: take, to: show.appending(path: ".moved Take 02"))
    }

    @Test("A Take folder set aside by a move isn't read as a Take by the Show list (#630)")
    func showListSkipsSetAside() throws {
        try setAside()
        #expect(ShowList.takeMetadata(in: show).map(\.folder.lastPathComponent) == ["Take 02"])
    }

    @Test("A Take folder set aside by a move isn't in the Show report (#630)")
    func reportSkipsSetAside() throws {
        try setAside()
        #expect(try ShowReport(showFolder: show).takes.count == 1)
    }

    @Test("A Take folder set aside by a move isn't in the Reaper export's timeline (#630)")
    func timelineSkipsSetAside() throws {
        try setAside()
        #expect(try Show(name: "2026-10-06 Show", folder: show, takeCount: 2).timeline().takes.count == 1)
    }

    @Test("The Show report's CSV has every channel with its Stem length")
    func csv() throws {
        let report = try ShowReport(showFolder: show)
        #expect(report.csv == """
            Take,USB Channel,Stem,Source,Mixer named,Color,Muted,Fader,Input source,Duration (s)\r
            2,1,01 Kick.wav,Kick,true,red,false,0.75,1,3.000\r
            2,2,02 USB 02.wav,USB 02,false,off,,,,2.500\r

            """)
    }

    @Test("The Show report lists Pre-roll, levels, Markers, renames, Gaps with their Repair result, and Dropouts")
    func html() throws {
        let html = try ShowReport(showFolder: show).html
        for row in [
            "<dt>Pre-roll</dt><dd>0.5 s</dd>",
            "<dt>Duration</dt><dd>0:03</dd>",
            "<dt>Folder</dt><dd>Take 02</dd>",
            #"<tr><td class="num">1</td><td class="source">Kick</td><td class="num">-3.2</td><td class="num">-21.5</td></tr>"#,
            #"<tr><td class="num">2</td><td class="source">USB 02</td><td class="num"></td><td class="num"></td></tr>"#,
            #"<tr><td class="num">0:01.0</td><td>Verse</td></tr>"#,
            #"<tr><td class="num">0:02.0</td><td>Dropout</td></tr>"#,
            #"<tr><td class="num">0:01.5</td><td class="num">1</td><td class="source">Kick</td><td class="source">Kick In</td></tr>"#,
            #"<tr><td>Drive</td><td class="num">0:00.0</td><td class="num">0:01.0</td><td>Repaired</td></tr>"#,
            #"<tr><td>Drive</td><td class="num">0:02.0</td><td class="num">0:02.5</td><td>Repair failed</td></tr>"#,
            #"<tr><td>Device</td><td class="num">0:00.0</td><td class="num">0:00.1</td><td>Not repaired</td></tr>"#,
            #"<tr><td>Device</td><td class="num">0:01.0</td><td class="num">0:01.0</td><td class="num">0:00.0</td></tr>"#,
        ] {
            #expect(html.contains(row), "missing: \(row)")
        }
    }

    @Test("Each Gap in the report keeps its Copy and what Repair did as values, not words")
    func typedGaps() throws {
        let take = try #require(try ShowReport(showFolder: show).takes.first)
        #expect(take.gaps.map(\.copy) == [.drive, .drive, .device])
        #expect(take.gaps.map(\.repair) == [.repaired, .failed, nil])
        #expect(take.dropouts.map(\.copy) == [.device])
    }

    @Test("The Show's recorded time is its Takes' lengths from their Stems, leaving out a Take that is still running")
    func recordedSeconds() throws {
        let show = Show(name: "2026-10-06 Show", folder: show, takeCount: 2)
        #expect(try show.recordedSeconds(leavingOut: nil) == 3.0)
        #expect(try show.recordedSeconds(leavingOut: 2) == 0)
    }

    @Test("The Reaper export's timeline has the Take's length, Stems and Markers")
    func timeline() throws {
        let timeline = try Show(name: "2026-10-06 Show", folder: show, takeCount: 1).timeline()
        #expect(timeline == ShowTimeline(
            showName: "2026-10-06 Show",
            usbChannels: [
                .init(number: 1, name: "Kick", color: MixerColor(hue: .red, inverted: false)),
                .init(number: 2, name: "USB 02", color: MixerColor(hue: .off, inverted: false)),
            ],
            takes: [
                .init(
                    number: 2, sampleRate: 48_000, frameCount: 144_000,
                    stems: [
                        .init(usbChannel: 1, path: "Take 02/01 Kick.wav", name: "Kick"),
                        .init(usbChannel: 2, path: "Take 02/02 USB 02.wav", name: "USB 02"),
                    ],
                    markers: [
                        .init(position: 48_000, name: "Verse"), .init(position: 96_000, name: "Dropout"),
                        .init(position: 72_000, name: "USB 1: Kick → Kick In"),  // the rename (#577)
                    ]),
            ]))
    }
}
