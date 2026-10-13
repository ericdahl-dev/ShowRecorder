import AudioIO
import Foundation
import MixerLink
@testable import Recording
import TakeFile
import Testing

/// Every gain change ShowRecorder makes on the Mixer is logged (#450): in the Take during a Take, with a Marker, and
/// in the Show between Takes.
@MainActor
@Suite("Gain log")
struct GainLogTests {
    @Test("The gain log shapes the Marker's name from the USB Channel's name, the change and why")
    func gainLogMarkerName() {
        let down = TakeMetadata.GainChange(usbChannel: 1, channel: 1, headamp: 1, fromGainDb: 30, toGainDb: 26, reason: .clipProtection, compensations: [])
        let up = TakeMetadata.GainChange(usbChannel: 2, channel: 2, headamp: 2, fromGainDb: 10, toGainDb: 13.5, reason: .autoGain, compensations: [])
        #expect(GainLog.markerName(for: down, channelName: "Kick") == "Kick: gain -4.0 dB (clip protection)")
        #expect(GainLog.markerName(for: up, channelName: "Snare") == "Snare: gain +3.5 dB (auto-gain)")
    }

    let root = FileManager.default.temporaryDirectory.appending(path: "GainLogTests-\(UUID().uuidString)")
    var show: URL { root.appending(path: "2026-10-06 Show") }

    static let change = TakeMetadata.GainChange(
        usbChannel: 1, channel: 1, headamp: 1, fromGainDb: 14.5, toGainDb: 17.5, reason: .autoGain,
        compensations: [.init(channel: 1, setting: "fader", fromDb: -6.2, toDb: -9.2)])

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test("During a Take: logged in Take.json at its sample position, with a Marker that says what changed")
    func duringATake() async throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        try recorder.startTake(sources: [Source(name: "Kick", color: .off), Source(name: "Snare", color: .off)])
        for _ in 0..<3 { device.deliver(Array(repeating: [0, 0, 0, 0], count: 2)) }

        recorder.logGainChange(Self.change)
        // Listed at once as a gain Marker, not as a Dropout (#528).
        #expect(recorder.markerEntries.map(\.kind) == [.gain])
        #expect(recorder.markerEntries.map(\.isDropout) == [false])
        try recorder.stopTake()
        await recorder.waitForRepair()

        let metadata = try Self.decoder().decode(TakeMetadata.self, from: Data(contentsOf: show.appending(path: "Take 01/Take.json")))
        let logged = try #require(metadata.gainChanges?.first)
        #expect(logged.usbChannel == 1 && logged.fromGainDb == 14.5 && logged.toGainDb == 17.5 && logged.reason == .autoGain)
        #expect(logged.position != nil)
        #expect(logged.compensations == Self.change.compensations)
        let marker = try #require(metadata.markers.first { $0.origin == .gain })
        #expect(marker.name == "Kick: gain +3.0 dB (auto-gain)")
        #expect(marker.position == logged.position)
        #expect(metadata.operatorMarkers.isEmpty, "a gain Marker isn't one of the operator's")
    }

    @Test("Between Takes: logged in Show.json, with no position")
    func betweenTakes() async throws {
        let device = FakeAudioDevice(inputChannelCount: 2)
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        try recorder.arm(device)
        try recorder.startTake()
        device.deliver(Array(repeating: [0], count: 2))
        try recorder.stopTake()
        await recorder.waitForRepair()

        recorder.logGainChange(Self.change)

        let file = try #require(ShowFile.read(from: show))
        let logged = try #require(file.gainChanges?.first)
        #expect(logged.toGainDb == 17.5)
        #expect(logged.position == nil)
    }

    /// A Take.json written before #496 renamed Re-Gain to Mix Hold (the format v1.1.x saves), as recorded then.
    static let takeJSONBeforeMixHold = """
{
  "dropouts" : [

  ],
  "gainChanges" : [
    {
      "at" : "2026-10-07T01:30:00Z",
      "channel" : 1,
      "compensations" : [
        {
          "channel" : 1,
          "fromDb" : -6.2,
          "setting" : "fader",
          "toDb" : -9.2
        }
      ],
      "fromGainDb" : 14.5,
      "headamp" : 1,
      "position" : 12,
      "reason" : "autoGain",
      "toGainDb" : 17.5,
      "usbChannel" : 1
    }
  ],
  "gaps" : [

  ],
  "markers" : [
    {
      "name" : "Kick: gain +3.0 dB (auto-gain)",
      "origin" : "gain",
      "position" : 12
    }
  ],
  "repairs" : [

  ],
  "sampleRate" : 48000,
  "show" : "2026-10-06 Show",
  "startedAt" : "2026-10-07T01:30:00Z",
  "take" : 1,
  "timeReference" : 3715200000,
  "usbChannels" : [
    {
      "averageDbfs" : -80,
      "color" : {
        "hue" : "off",
        "inverted" : false
      },
      "hasMixerName" : true,
      "name" : "Kick",
      "peakDbfs" : -80,
      "stemFile" : "01 Kick.wav",
      "usbChannel" : 1
    },
    {
      "averageDbfs" : -80,
      "color" : {
        "hue" : "off",
        "inverted" : false
      },
      "hasMixerName" : true,
      "name" : "Snare",
      "peakDbfs" : -80,
      "stemFile" : "02 Snare.wav",
      "usbChannel" : 2
    }
  ]
}
"""

    @Test("A Take saved before the Mix Hold rename (v1.1.x) still opens, with its gain log and what was compensated")
    func takeSavedBeforeTheRenameOpens() throws {
        let metadata = try Self.decoder().decode(TakeMetadata.self, from: Data(Self.takeJSONBeforeMixHold.utf8))
        let logged = try #require(metadata.gainChanges?.first)
        #expect(logged.reason == .autoGain && logged.fromGainDb == 14.5 && logged.toGainDb == 17.5)
        #expect(logged.compensations == [.init(channel: 1, setting: "fader", fromDb: -6.2, toDb: -9.2)])
    }
}
