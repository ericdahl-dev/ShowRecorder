import AudioIO
import Foundation
import MixerLink
import Recording
import Testing

@MainActor
@Suite("Source names in Stems")
struct SourceNamesTests {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "SourceNamesTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var take: URL { root.appending(path: "2026-10-06 Show/Take 01") }

    func record(channels: Int, sources: [Source]) throws {
        let device = FakeAudioDevice(inputChannelCount: channels)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        try recorder.startTake(sources: sources)
        device.deliver(Array(repeating: [0], count: channels))
        try recorder.stopTake()
    }

    @Test("Stems are named after their Source, and bext carries the Source name")
    func stemsNamedAfterSources() throws {
        try record(channels: 2, sources: [
            Source(name: "Kick", color: MixerColor(hue: .red, inverted: false)),
            Source(name: "Lead Vocal", color: MixerColor(hue: .yellow, inverted: true)),
        ])

        #expect(try StemFile(contentsOf: take.appending(path: "01 Kick.wav")).description == "Kick")
        #expect(try StemFile(contentsOf: take.appending(path: "02 Lead Vocal.wav")).description == "Lead Vocal")
    }

    @Test("Names unsafe for file systems are cleaned in the file name but kept in bext", arguments: [
        ("Gtr/Vox: L", "01 Gtr-Vox- L.wav"),
        ("  ..Keys..  ", "01 Keys.wav"),
        ("A*B?C\"D<E>F|G\\H", "01 A-B-C-D-E-F-G-H.wav"),
        ("...", "01 USB 01.wav"),
        (String(repeating: "x", count: 100), "01 " + String(repeating: "x", count: 64) + ".wav"),
    ])
    func unsafeNamesCleaned(name: String, file: String) throws {
        try record(channels: 1, sources: [Source(name: name, color: .off)])

        #expect(try StemFile(contentsOf: take.appending(path: file)).description == name)
    }

    @Test("Take.json records each USB Channel's Stem and Source state")
    func takeMetadataRecordsSources() throws {
        try record(channels: 2, sources: [
            Source(name: "Kick", color: MixerColor(hue: .red, inverted: false), isMuted: false, fader: 0.75, inputSource: 1),
            Source.fallback(usbChannel: 2),
        ])

        let data = try Data(contentsOf: take.appending(path: "Take.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["show"] as? String == "2026-10-06 Show")
        #expect(json["take"] as? Int == 1)
        #expect(json["sampleRate"] as? Int == 48_000)
        #expect(json["timeReference"] as? Int == 3_715_200_000)
        #expect(json["startedAt"] as? String != nil)

        let channels = try #require(json["usbChannels"] as? [[String: Any]])
        #expect(channels.count == 2)
        #expect(channels[0]["usbChannel"] as? Int == 1)
        #expect(channels[0]["stemFile"] as? String == "01 Kick.wav")
        #expect(channels[0]["name"] as? String == "Kick")
        #expect(channels[0]["hasMixerName"] as? Bool == true)
        #expect(channels[0]["color"] as? [String: AnyHashable] == ["hue": "red", "inverted": false])
        #expect(channels[0]["muted"] as? Bool == false)
        #expect(channels[0]["fader"] as? Double == 0.75)
        #expect(channels[0]["inputSource"] as? Int == 1)
        #expect(channels[1]["stemFile"] as? String == "02 USB 02.wav")
        #expect(channels[1]["hasMixerName"] as? Bool == false)
        #expect(channels[1]["muted"] == nil, "unknown state is left out, not guessed")
    }

    @Test("USB Channels without a Source get the USB Channel name")
    func missingSourcesFallBack() throws {
        try record(channels: 3, sources: [Source(name: "Kick", color: .off)])

        let files = try FileManager.default.contentsOfDirectory(atPath: take.path).filter { $0.hasSuffix(".wav") }.sorted()
        #expect(files == ["01 Kick.wav", "02 USB 02.wav", "03 USB 03.wav"])
    }
}
