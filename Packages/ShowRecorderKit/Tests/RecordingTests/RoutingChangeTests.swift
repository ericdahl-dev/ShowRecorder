import AudioIO
import Foundation
import MixerLink
@testable import Recording
import Testing

/// A USB routing change during a Take (#21): the Take goes on and keeps its Stems' names; the change is logged with
/// a Marker, and the screen is told. A rename on the Mixer stays a quiet rename.
@MainActor
@Suite("Routing change")
struct RoutingChangeTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "RoutingChangeTests-\(UUID().uuidString)")
    var take: URL { root.appending(path: "2026-10-06 Show/Take 01") }

    static func source(_ name: String, routedFrom: String?) -> Source {
        var source = Source(name: name, color: .off)
        source.routedFrom = routedFrom
        return source
    }
    static let start = [source("Kick", routedFrom: "ch:1"), source("Lead Vocal", routedFrom: "ch:2")]

    func metadata() throws -> TakeMetadata {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: Data(contentsOf: take.appending(path: "Take.json")))
    }

    @Test("A re-patch mid-Take is logged with its position and old and new Source, with a Marker; the Take goes on, its Stem keeps its name")
    func repatchIsLogged() async throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        try recorder.startTake(sources: Self.start)
        for _ in 0..<3 { device.deliver(Array(repeating: [0, 0, 0, 0], count: 2)) }

        recorder.offerSources([Self.source("Snare", routedFrom: "ch:3"), Self.start[1]])

        #expect(recorder.isRecording)
        #expect(recorder.routingChanges.map(\.usbChannel) == [1])
        try recorder.stopTake()
        await recorder.waitForRepair()
        let changes = try #require(try metadata().routingChanges)
        #expect(changes.map(\.usbChannel) == [1] && changes[0].from == "Kick" && changes[0].to == "Snare" && changes[0].position > 0)
        let marker = try #require(try metadata().markers.first { $0.origin == .routing })
        #expect(marker.position == changes[0].position)
        #expect(marker.name == "USB 01 re-patched: Kick to Snare")
        #expect(try metadata().renames == nil, "a re-patch isn't also a rename")
        #expect(FileManager.default.fileExists(atPath: take.appending(path: "01 Kick.wav").path))
    }

    @Test("A rename on the Mixer, same routing, stays a quiet rename: no routing change, no Marker")
    func renameIsNotARepatch() async throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        try recorder.startTake(sources: Self.start)
        for _ in 0..<3 { device.deliver(Array(repeating: [0, 0, 0, 0], count: 2)) }

        recorder.offerSources([Self.source("Kick In", routedFrom: "ch:1"), Self.start[1]])

        #expect(recorder.routingChanges.isEmpty)
        try recorder.stopTake()
        await recorder.waitForRepair()
        #expect(try metadata().routingChanges == nil)
        #expect(try metadata().renames?.map(\.to) == ["Kick In"])
        #expect(try metadata().markers.allSatisfy { $0.origin != .routing })
    }
}

/// Review findings on #21: names, late links, bursts and later Marker renames.
@MainActor
@Suite("Routing change, edges")
struct RoutingChangeEdgeTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "RoutingChangeEdgeTests-\(UUID().uuidString)")
    var take: URL { root.appending(path: "2026-10-06 Show/Take 01") }
    let audio = FakeAudioDevice(inputChannelCount: 2)

    func source(_ name: String, _ routedFrom: String?) -> Source { RoutingChangeTests.source(name, routedFrom: routedFrom) }
    func metadata() throws -> TakeMetadata { try TakeMetadata.read(fromTakeFolder: take) }

    func start(_ sources: [Source] = RoutingChangeTests.start) throws -> Recorder {
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(audio)
        try recorder.startTake(sources: sources)
        return recorder
    }

    @Test("The warning names the Stem's own name, even after a rename on the desk")
    func noticeNamesTheStem() async throws {
        let recorder = try start()
        try await deliver(4_800, to: audio, recorder)
        recorder.offerSources([source("Kick In", "ch:1"), source("Lead Vocal", "ch:2")])   // quiet rename
        recorder.offerSources([source("Snare", "ch:3"), source("Lead Vocal", "ch:2")])     // re-patch
        #expect(recorder.routingNotice == "USB 01 now carries Snare (was Kick In). Its Stem keeps the name Kick; a Marker marks the change.")
        try recorder.stopTake()
    }

    @Test("A Mixer Link that arrives after the press sets the routing to watch; a re-patch after that is caught")
    func lateLink() async throws {
        let recorder = try start([])
        try await deliver(4_800, to: audio, recorder)
        recorder.offerSources(RoutingChangeTests.start)
        #expect(recorder.routingChanges.isEmpty, "the first routing seen is the baseline")
        try await deliver(4_800, to: audio, recorder)
        recorder.offerSources([source("Snare", "ch:3"), source("Lead Vocal", "ch:2")])
        #expect(recorder.routingChanges.map(\.usbChannel) == [1])
        try recorder.stopTake()
    }

    @Test("Stepping one USB Channel's source through several channels within a second is one routing change, one Marker")
    func burstIsOneChange() async throws {
        let recorder = try start()
        try await deliver(4_800, to: audio, recorder)
        for channel in 3...6 {
            recorder.offerSources([source("Ch \(channel)", "ch:\(channel)"), source("Lead Vocal", "ch:2")])
            try await deliver(480, to: audio, recorder)
        }
        #expect(recorder.routingChanges.count == 1)
        try recorder.stopTake()
        let changes = try #require(try metadata().routingChanges)
        #expect(changes.count == 1 && changes[0].from == "Kick" && changes[0].to == "Ch 6" && changes[0].position == 4_800)
        #expect(try metadata().markers.filter { $0.origin == .routing }.map(\.name) == ["USB 01 re-patched: Kick to Ch 6"])
    }

    @Test("Re-patches a second or more apart are separate changes")
    func separateChanges() async throws {
        let recorder = try start()
        try await deliver(4_800, to: audio, recorder)
        recorder.offerSources([source("Snare", "ch:3"), source("Lead Vocal", "ch:2")])
        try await deliver(48_000, to: audio, recorder)
        recorder.offerSources([source("Tom", "ch:4"), source("Lead Vocal", "ch:2")])
        #expect(recorder.routingChanges.map(\.to) == ["Snare", "Tom"])
        #expect(recorder.routingNotice == "2 re-patches during this Take (USB 01). The Stems keep their names; Markers mark each change.")
        try recorder.stopTake()
    }

    @Test("Renaming an operator Marker after the Take keeps the routing cue in every Stem")
    func markerRenameKeepsRoutingCue() async throws {
        let recorder = try start()
        try await deliver(4_800, to: audio, recorder)
        recorder.addMarker()
        try await deliver(2_400, to: audio, recorder)
        recorder.offerSources([source("Snare", "ch:3"), source("Lead Vocal", "ch:2")])
        try await deliver(480, to: audio, recorder)
        try recorder.stopTake()
        await recorder.waitForRepair()

        let outcome = MarkerRenamer.rename(markerAt: 0, to: "Intro", in: [.device: take], allowsProExtras: true)
        #expect(outcome.result == .renamed)
        #expect(try cuePoints(take.appending(path: "01 Kick.wav")).map(\.label) == ["Intro", "USB 01 re-patched: Kick to Snare"])
    }
}

/// What the record screen's warning says about routing changes (#21).
@Suite("Routing change notice")
struct RoutingChangeNoticeTests {
    @Test("One change names the USB Channel, the new Source, the old one and the Stem's name; several are counted")
    func message() {
        let one = TakeMetadata.RoutingChange(position: 4_800, usbChannel: 3, from: "Kick", to: "Snare")
        let stems = [3: "Kick", 5: "Tom"]
        #expect(RoutingChangeNotice.message(for: [], stemNames: stems) == nil)
        #expect(RoutingChangeNotice.message(for: [one], stemNames: stems) ==
            "USB 03 now carries Snare (was Kick). Its Stem keeps the name Kick; a Marker marks the change.")
        let two = TakeMetadata.RoutingChange(position: 9_600, usbChannel: 5, from: "Tom", to: "Bus 1")
        #expect(RoutingChangeNotice.message(for: [one, two], stemNames: stems) ==
            "2 re-patches during this Take (USB 03, 05). The Stems keep their names; Markers mark each change.")
    }
}
