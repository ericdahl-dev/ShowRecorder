import Foundation
@testable import Recording
import Testing

/// A Take or Show written by a newer ShowRecorder opens here, and saving it again keeps what this version doesn't know
/// (v1.0.2: 1.0 reading Takes from 1.1).
@Suite("Files from a newer version")
struct NewerFileTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "NewerFileTests-\(UUID().uuidString)")

    init() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    static let takeJSON = """
    {
      "show": "Friday", "take": 1, "startedAt": "2026-10-06T20:00:00Z", "sampleRate": 48000, "timeReference": 0,
      "usbChannels": [{"usbChannel": 1, "stemFile": "01 Kick.wav", "name": "Kick", "hasMixerName": true,
                       "color": {"hue": "red", "inverted": false}}],
      "markers": [
        {"position": 100, "name": "Marker 1", "origin": "operator"},
        {"position": 200, "name": "Kick: gain +3.0 dB (auto-gain)", "origin": "gain"},
        {"position": 300, "name": "USB 01 re-patched: Kick to Snare", "origin": "routing"},
        {"position": 400, "name": "Sparkle", "origin": "sparkle"}
      ],
      "gainChanges": [{"position": 200, "usbChannel": 1, "channel": 1, "headamp": 1, "fromGainDb": 20, "toGainDb": 23,
                       "reason": "sparkleGain", "compensations": []}],
      "futureLog": [{"position": 500, "what": "something new"}]
    }
    """

    func writeTake() throws {
        try Data(Self.takeJSON.utf8).write(to: folder.appending(path: "Take.json"))
    }

    func savedJSON(_ file: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appending(path: file))) as? [String: Any])
    }

    @Test("A Take with Marker kinds and a gain reason this version doesn't know opens; the operator's Marker is still the operator's")
    func unknownKindsOpen() throws {
        try writeTake()
        let take = try TakeMetadata.read(fromTakeFolder: folder)
        #expect(take.markers.map(\.origin) == [.operator, .gain, .routing, .other("sparkle")])
        #expect(take.operatorMarkers.map(\.name) == ["Marker 1"])
        #expect(take.gainChanges?.first?.reason == .other("sparkleGain"))
        #expect(take.gainChanges?.first?.reason.word == "sparkleGain")
    }

    @Test("Saving that Take again keeps the unknown Marker kind, the unknown reason and the fields this version doesn't know")
    func savingKeepsWhatIsUnknown() throws {
        try writeTake()
        var take = try TakeMetadata.read(fromTakeFolder: folder)
        take.markers[0].name = "Intro"
        try take.write(to: folder)

        let saved = try savedJSON("Take.json")
        let markers = try #require(saved["markers"] as? [[String: Any]])
        #expect(markers.compactMap { $0["origin"] as? String } == ["operator", "gain", "routing", "sparkle"])
        #expect(markers.first?["name"] as? String == "Intro")
        let gain = try #require((saved["gainChanges"] as? [[String: Any]])?.first)
        #expect(gain["reason"] as? String == "sparkleGain")
        let future = try #require((saved["futureLog"] as? [[String: Any]])?.first)
        #expect(future["what"] as? String == "something new")
        #expect(try TakeMetadata.read(fromTakeFolder: folder).markers.map(\.origin) == [.operator, .gain, .routing, .other("sparkle")])
    }

    @Test("A Marker of an unknown kind is neither the operator's nor a Dropout, and no Stem carries it")
    func unknownKindIsLeftAlone() throws {
        try writeTake()
        let take = try TakeMetadata.read(fromTakeFolder: folder)
        #expect(take.operatorIndex(ofMarkerAt: 3) == nil)
        #expect(take.dropoutCount == 0)
        #expect(!take.stemCueMarkers.contains { $0.origin == .other("sparkle") })
    }

    @Test("A Take this version wrote, read, renamed and saved again is written exactly as JSONEncoder writes it")
    func ownTakeUnchanged() throws {
        let take = TakeMetadata(show: "Friday", take: 1, startedAt: Date(timeIntervalSince1970: 0), sampleRate: 48_000, timeReference: 0,
                                usbChannels: [], markers: [.init(position: 1, name: "Marker 1", origin: .operator)])
        try take.write(to: folder)
        var read = try TakeMetadata.read(fromTakeFolder: folder)
        #expect(read.unknownFields == nil)
        read.markers[0].name = "Intro"
        try read.write(to: folder)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        #expect(try Data(contentsOf: folder.appending(path: "Take.json")) == (try encoder.encode(read)))
    }

    @Test("An open Show from a newer version, resumed here, keeps its unknown fields when a Take ends and on the Drive")
    func resumedShowKeepsWhatIsUnknown() throws {
        let device = folder.appending(path: "Device"), drive = folder.appending(path: "Drive")
        let showFolder = device.appending(path: "2026-10-06 Friday")
        try FileManager.default.createDirectory(at: showFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        try Data("""
        {"name": "2026-10-06 Friday", "startedAt": "2026-10-06T20:00:00Z", "futureSetting": {"level": 3}}
        """.utf8).write(to: showFolder.appending(path: "Show.json"))

        var show = try #require(Show.findOpen(in: device))
        show.noteTakeEnded(at: Date(timeIntervalSince1970: 1_791_000_000))
        try show.useDrive(drive)

        for copy in [showFolder, drive.appending(path: "2026-10-06 Friday")] {
            let saved = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: copy.appending(path: "Show.json"))) as? [String: Any])
            #expect((saved["futureSetting"] as? [String: Any])?["level"] as? Int == 3, "\(copy.lastPathComponent)")
            #expect(saved["lastTakeEndedAt"] != nil)
        }
    }

    @Test("A Show.json with fields this version doesn't know opens, and saving it keeps them")
    func showKeepsWhatIsUnknown() throws {
        try Data("""
        {"name": "Friday", "startedAt": "2026-10-06T20:00:00Z", "futureSetting": {"level": 3}}
        """.utf8).write(to: folder.appending(path: "Show.json"))
        var show = try #require(ShowFile.read(from: folder))
        show.venue = "The Hall"
        try show.write(to: folder)

        let saved = try savedJSON("Show.json")
        #expect(saved["venue"] as? String == "The Hall")
        #expect((saved["futureSetting"] as? [String: Any])?["level"] as? Int == 3)
    }
}
