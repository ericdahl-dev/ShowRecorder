import Foundation
@testable import Recording
import Testing

@Suite("A Take's Markers, from Take.json")
struct TakeMarkersTests {
    /// Operator Markers and Dropout Markers interleaved, as a Take that lost audio twice in a row holds them.
    func metadata() -> TakeMetadata {
        TakeMetadata(
            show: "Show", take: 1, startedAt: Date(timeIntervalSince1970: 1_800_000_000), sampleRate: 48_000, timeReference: 0,
            usbChannels: [.init(usbChannel: 1, stemFile: "01 USB 01.wav", source: .fallback(usbChannel: 1))],
            markers: [
                .init(position: 100, name: "Intro", origin: .operator),
                .init(position: 200, name: "Dropout", origin: .dropout),
                .init(position: 300, name: "Marker 2", origin: .operator),
                .init(position: 400, name: "Dropout", origin: .dropout),
                .init(position: 500, name: "Dropout", origin: .dropout),
                .init(position: 600, name: "Bridge", origin: .operator),
            ])
    }

    @Test("The operator's Markers leave out the Dropout Markers, in order")
    func operatorMarkers() {
        #expect(metadata().operatorMarkers.map(\.name) == ["Intro", "Marker 2", "Bridge"])
        #expect(metadata().operatorMarkers.map(\.position) == [100, 300, 600])
    }

    @Test("Each Marker's index among the operator's Markers; a Dropout Marker has none")
    func operatorIndex() {
        let take = metadata()
        #expect(take.markers.indices.map { take.operatorIndex(ofMarkerAt: $0) } == [0, nil, 1, nil, nil, 2])
        #expect(take.operatorIndex(ofMarkerAt: 6) == nil)
    }

    @Test("The operator Marker at an index is found among all the Markers")
    func markerPlace() {
        let take = metadata()
        #expect((0..<3).map { take.place(ofOperatorMarker: $0) } == [0, 2, 5])
        #expect(take.place(ofOperatorMarker: 3) == nil)
        #expect(take.place(ofOperatorMarker: -1) == nil)
    }

    @Test("The Dropout count is the number of Dropout Markers")
    func dropoutCount() {
        #expect(metadata().dropoutCount == 3)
        #expect(metadata().dropoutMarkers.map(\.position) == [200, 400, 500])
    }

    @Test("The next unnamed Marker counts the operator's Markers only")
    func nextMarkerName() {
        #expect(metadata().nextMarkerName == "Marker 4")
        var empty = metadata()
        empty.markers = [.init(position: 200, name: "Dropout", origin: .dropout)]
        #expect(empty.nextMarkerName == "Marker 1")
    }
}
