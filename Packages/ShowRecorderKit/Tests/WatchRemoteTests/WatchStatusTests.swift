import Foundation
import Testing
@testable import WatchRemote

@Suite("Watch status")
struct WatchStatusTests {
    static let recording = WatchStatus(
        state: .recording(startedAt: Date(timeIntervalSince1970: 1_000), takeTitle: "Take 03", markerCount: 2),
        problems: [.driveLowSpace, .mixerLinkLost])

    @Test("Status, commands and replies go over WatchConnectivity as one entry of plain data, and come back the same")
    func roundTrip() throws {
        #expect(try WatchStatus(message: Self.recording.message) == Self.recording)
        let command = WatchCommand(kind: .marker, sentAt: Date(timeIntervalSince1970: 2_000))
        #expect(try WatchCommand(message: command.message) == command)
        for reply in [WatchReply.done, .refused("Choose where Takes go"), .tooLate] {
            #expect(try WatchReply(message: reply.message) == reply)
        }
    }

    @Test("A message of the wrong kind, or none, doesn't read as one")
    func wrongKind() {
        #expect(throws: (any Error).self) { try WatchStatus(message: WatchCommand(kind: .stop, sentAt: .now).message) }
        #expect(throws: (any Error).self) { try WatchCommand(message: [:]) }
    }

    @Test("Each problem reads without color: a symbol and a few words", arguments: WatchStatus.Problem.allCases)
    func problemText(problem: WatchStatus.Problem) {
        #expect(!problem.symbol.isEmpty)
        #expect(!problem.text.isEmpty && problem.text.count <= 20, "fits the wrist: \(problem.text)")
    }
    @Test("The state keys on the wire stay \"armed\" and \"notArmed\": a paired watch a version behind still reads them")
    func stateKeysOnTheWire() throws {
        for (state, key) in [(WatchStatus.State.ready, "armed"), (.notReady, "notArmed")] {
            let json = try String(decoding: JSONEncoder().encode(WatchStatus(state: state, sentAt: Date(timeIntervalSince1970: 0))), as: UTF8.self)
            #expect(json.contains("\"\(key)\":{}"), "\(json)")
            let old = Data(#"{"version":1,"sentAt":0,"state":{"\#(key)":{}},"problems":[]}"#.utf8)
            #expect(try WatchStatus(message: [WatchStatus.key: old]).state == state)
        }
    }

    @Test("A newer iPhone's problem or reply the watch doesn't know yet doesn't stop the rest reading")
    func newerVersion() throws {
        let status = Data(#"{"version":2,"sentAt":0,"state":{"armed":{}},"problems":["driveLowSpace","somethingNew"]}"#.utf8)
        let read = try WatchStatus(message: [WatchStatus.key: status])
        #expect(read.state == .ready)
        #expect(read.problems == [.driveLowSpace])
        let reply = Data(#"{"somethingNew":{}}"#.utf8)
        #expect(try WatchReply(message: [WatchReply.key: reply]) == .refused(WatchReply.updateText))
    }
}
