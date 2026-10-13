import Foundation
import Testing
@testable import WatchRemote

/// The watch's side of the remote (#100): what it shows, and each command pending until the iPhone confirms it.
@MainActor
@Suite("Watch remote model")
struct WatchRemoteModelTests {
    /// A link in memory: reachable or not, holding each command's reply until the test answers it.
    final class Link: WatchLinkTransport {
        var isReachable = true
        var sent: [WatchCommand] = []
        var replies: [(WatchReply?) -> Void] = []
        func send(_ command: WatchCommand, reply: @escaping @MainActor (WatchReply?) -> Void) {
            sent.append(command)
            replies.append(reply)
        }
    }

    static let armed = WatchStatus(state: .armed)
    static let recording = WatchStatus(state: .recording(startedAt: .now, takeTitle: "Take 01", markerCount: 0))

    static func model(_ link: Link, status: WatchStatus? = recording) -> WatchRemoteModel {
        let model = WatchRemoteModel(link: link)
        if let status { model.received(status) }
        return model
    }

    @Test("With no link, or nothing heard from the iPhone yet, it shows no link, never a stale Recording")
    func noLink() {
        let link = Link()
        #expect(Self.model(link, status: nil).display == .noLink)
        let model = Self.model(link)
        #expect(model.display == .status(Self.recording))
        link.isReachable = false
        model.reachabilityChanged()
        #expect(model.display == .noLink)
    }

    @Test("A Marker is pending until the iPhone confirms it, then confirmed, with a light tap on the wrist")
    func markerConfirmed() {
        let link = Link()
        var haptics: [WatchRemoteModel.Haptic] = []
        let model = Self.model(link)
        model.haptic = { haptics.append($0) }

        model.send(.marker)
        #expect(model.commands[.marker] == .pending)
        link.replies[0](.done)
        #expect(model.commands[.marker] == .confirmed)
        #expect(haptics == [.markerConfirmed])
    }

    @Test("With no link a command fails at once and is never sent or queued")
    func noLinkFails() {
        let link = Link()
        link.isReachable = false
        let model = Self.model(link)
        model.reachabilityChanged()

        model.send(.stop)
        #expect(link.sent.isEmpty)
        #expect(model.commands[.stop] == .failed(WatchRemoteModel.noLinkText))
    }

    @Test("A command the iPhone refuses says why; one whose answer the link loses is unconfirmed")
    func failures() {
        let link = Link()
        let model = Self.model(link, status: Self.armed)
        model.send(.start)
        link.replies[0](.refused("Choose where Takes go in Settings"))
        #expect(model.commands[.start] == .failed("Choose where Takes go in Settings"))
        model.send(.start)
        link.replies[1](nil)
        #expect(model.commands[.start] == .unconfirmed, "it may have started: no answer isn't a failure")
    }

    @Test("Start is offered only when the iPhone is Armed; otherwise it says to open ShowRecorder, and sends nothing")
    func startNeedsArmed() {
        let link = Link()
        let model = Self.model(link, status: WatchStatus(state: .notArmed))
        #expect(!model.canStart)
        model.send(.start)
        #expect(link.sent.isEmpty)
        #expect(model.commands[.start] == .failed(WatchRemoteModel.openPhoneText))
        model.received(Self.armed)
        #expect(model.canStart)
    }

    @Test("A problem that appears taps the wrist once; one already showing doesn't again")
    func problemHaptic() {
        let link = Link()
        var haptics: [WatchRemoteModel.Haptic] = []
        let model = Self.model(link)
        model.haptic = { haptics.append($0) }
        var status = Self.recording
        status.problems = [.driveLowSpace]
        model.received(status)
        model.received(status)
        #expect(haptics == [.problem])
    }
    @Test("Commands are stamped in the iPhone's time, from the last status, so the two clocks needn't agree")
    func phoneTime() {
        let link = Link()
        let watchNow = Date(timeIntervalSince1970: 5_000)
        let model = WatchRemoteModel(link: link, now: { watchNow })
        model.received(WatchStatus(state: .armed, sentAt: watchNow.addingTimeInterval(-30)))   // the iPhone is 30 s behind
        model.send(.start)
        #expect(link.sent.first?.sentAt == watchNow.addingTimeInterval(-30))
    }

    @Test("Only the latest command of a kind sets what shows: an older one's late answer doesn't")
    func latestOnly() {
        let link = Link()
        let model = Self.model(link)
        model.send(.marker)
        model.send(.marker)
        link.replies[1](.done)
        link.replies[0](nil)
        #expect(model.commands[.marker] == .confirmed)
    }

    @Test("When the link drops, the last status goes: back again, nothing shows until the iPhone says what's true now")
    func reconnect() {
        let link = Link()
        var haptics: [WatchRemoteModel.Haptic] = []
        let model = Self.model(link)
        model.haptic = { haptics.append($0) }
        var status = Self.recording
        status.problems = [.driveLowSpace]
        model.received(status)
        link.isReachable = false
        model.reachabilityChanged()
        link.isReachable = true
        model.reachabilityChanged()
        #expect(model.display == .noLink, "no stale Recording")
        model.received(status)
        #expect(model.display == .status(status))
        #expect(haptics == [.problem], "a problem already told isn't tapped again")
    }

    @Test("An answer that never came back is unknown, not a failure; one too late says so")
    func unknownAndLate() {
        let link = Link()
        let model = Self.model(link)
        model.send(.stop)
        link.replies[0](nil)
        #expect(model.commands[.stop] == .unconfirmed)
        model.send(.stop)
        link.replies[1](.tooLate)
        #expect(model.commands[.stop] == .failed(WatchRemoteModel.tooLateText))
    }
}
