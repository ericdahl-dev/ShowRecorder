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
        #expect(marker.name == "USB 1: Kick → Snare (routing)")
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
