import Destinations
import Foundation
import MixerLink
@testable import Recording
import Testing

@Suite("Dropouts in Take.json")
struct DropoutMetadataTests {
    func metadata() -> TakeMetadata {
        TakeMetadata(
            show: "Show", take: 1, startedAt: Date(timeIntervalSince1970: 1_800_000_000), sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))])
    }

    func roundTrip(_ take: TakeMetadata) throws -> TakeMetadata {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TakeMetadata.self, from: encoder.encode(take))
    }

    @Test("Dropouts and a Dropout Marker survive Take.json")
    func roundTripsDropouts() throws {
        var take = metadata()
        take.dropouts = [.init(copy: .drive, start: 480, end: 1_000), .init(copy: .device, start: 480, end: 960)]
        take.markers = [.init(position: 480, name: "Dropout", origin: .dropout)]
        let decoded = try roundTrip(take)
        #expect(decoded.dropouts == take.dropouts)
        #expect(decoded.markers.first?.origin == .dropout)
    }

    @Test("A Take.json from before Dropouts existed still reads, with none")
    func oldTakeHasNoDropouts() throws {
        let json = """
            {"show":"Show","take":1,"startedAt":"2026-10-07T12:00:00Z","sampleRate":48000,"timeReference":0,
             "usbChannels":[],"markers":[{"position":10,"name":"Marker 1","origin":"operator"}]}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let take = try decoder.decode(TakeMetadata.self, from: Data(json.utf8))
        #expect(take.dropouts.isEmpty)
        #expect(take.markers.first?.origin == .operator)
    }
}
