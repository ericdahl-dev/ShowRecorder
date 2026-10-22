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
        var statusAnswers: [(WatchStatus?) -> Void] = []
        func requestStatus(reply: @escaping @MainActor (WatchStatus?) -> Void) {
            statusAnswers.append(reply)
        }
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

    @Test("Nothing heard from the iPhone yet shows no link; a dropped link keeps the last status, shown as last known, not live (#737)")
    func noLink() {
        let link = Link()
        #expect(Self.model(link, status: nil).display == .noLink)
        let model = Self.model(link)
        #expect(model.display == .status(Self.recording))
        link.isReachable = false
        model.reachabilityChanged()
        #expect(model.display == .lastKnown(Self.recording), "the iPhone is likely still recording: say so, but not as live")
    }

    @Test("A status that landed while the link was down doesn't strand the watch on last known: the link coming back asks the iPhone what's true now (#751)")
    func asksWhenTheLinkComesBack() {
        let link = Link()
        link.isReachable = false
        let model = Self.model(link, status: nil)
        model.received(Self.recording)
        #expect(model.display == .lastKnown(Self.recording))

        link.isReachable = true
        model.reachabilityChanged()
        #expect(link.statusAnswers.count == 1, "the watch asks; it doesn't wait for a push that may not come")
        link.statusAnswers[0](Self.armed)
        #expect(model.display == .status(Self.armed))
    }

    @Test("A wrist raise on a running model reaches the same live state as a cold launch: it asks, and the answer is live (#751)")
    func asksOnWake() {
        let link = Link()
        let model = Self.model(link)
        link.isReachable = false
        model.reachabilityChanged()
        link.isReachable = true
        model.reachabilityChanged()
        link.statusAnswers[0](nil)
        #expect(model.display == .lastKnown(Self.recording), "no answer: wait for the push")

        model.appBecameActive()
        #expect(link.statusAnswers.count == 2)
        link.statusAnswers[1](Self.armed)
        #expect(model.display == .status(Self.armed))
    }

    @Test("A wrist raise with no link doesn't ask")
    func noAskWhenDown() {
        let link = Link()
        link.isReachable = false
        let model = Self.model(link, status: nil)
        model.appBecameActive()
        #expect(link.statusAnswers.isEmpty)
    }

    @Test("An answer that arrives after a newer push, or after a newer ask, doesn't overwrite it (#751)")
    func staleAnswersLose() {
        let link = Link()
        link.isReachable = false
        let model = Self.model(link, status: nil)
        link.isReachable = true
        model.reachabilityChanged()
        model.received(Self.armed)
        link.statusAnswers[0](Self.recording)
        #expect(model.display == .status(Self.armed), "the push came after the ask, so it's the newer one")

        model.appBecameActive()
        model.appBecameActive()
        link.statusAnswers[2](Self.recording)
        link.statusAnswers[1](Self.armed)
        #expect(model.display == .status(Self.recording), "the older ask's answer is dropped")
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
    @Test("A Marker after a status that arrived 30 s late still lands: commands carry the watch's own clock")
    func markerAfterLateStatus() {
        let link = Link()
        let now = Date(timeIntervalSince1970: 5_000)   // the iPhone and the watch keep the same time
        let model = WatchRemoteModel(link: link, now: { now })
        model.received(WatchStatus(state: .recording(startedAt: now.addingTimeInterval(-600), takeTitle: "Take 01", markerCount: 0),
                                   sentAt: now.addingTimeInterval(-30)))   // sent 30 s ago, nothing changed since
        var markers = 0
        let desk = WatchCommandDesk(now: { now }, actions: .init(start: { nil }, stop: { true }, marker: { markers += 1; return nil }))

        model.send(.marker)
        let reply = desk.handle(link.sent[0])
        link.replies[0](reply)

        #expect(reply == .done)
        #expect(markers == 1)
        #expect(model.commands[.marker] == .confirmed)
    }

    @Test("A Marker the iPhone didn't place, past the Free limit, plays no confirm click and shows why (#882)")
    func markerPastTheLimitNotConfirmed() {
        let link = Link()
        let now = Date(timeIntervalSince1970: 5_000)
        let model = WatchRemoteModel(link: link, now: { now })
        var haptics: [WatchRemoteModel.Haptic] = []
        model.haptic = { haptics.append($0) }
        model.received(WatchStatus(state: .recording(startedAt: now.addingTimeInterval(-60), takeTitle: "Take 01", markerCount: 3), sentAt: now))
        let desk = WatchCommandDesk(now: { now }, actions: .init(start: { nil }, stop: { true }, marker: { "3 per Take on Free" }))

        model.send(.marker)
        link.replies[0](desk.handle(link.sent[0]))

        #expect(!haptics.contains(.markerConfirmed))
        #expect(model.commands[.marker] == .failed("3 per Take on Free"))
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

    @Test("When the link drops and returns, the last status stays last known until the iPhone says what's true now")
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
        #expect(model.display == .lastKnown(status), "not live until a fresh status")
        model.received(status)
        #expect(model.display == .status(status))
        #expect(haptics == [.problem], "a problem already told isn't tapped again")
    }

    @Test("A status that arrives in the background, with no live link, shows as last known, not live (#737)")
    func contextWhileUnreachable() {
        let link = Link()
        link.isReachable = false
        let model = Self.model(link, status: nil)
        model.received(Self.recording)
        #expect(model.display == .lastKnown(Self.recording))
        link.isReachable = true
        model.reachabilityChanged()
        model.received(Self.recording)
        #expect(model.display == .status(Self.recording))
    }

    @Test("While last known, Start is not offered and a command fails at once")
    func lastKnownBlocksCommands() {
        let link = Link()
        let model = Self.model(link, status: Self.armed)
        link.isReachable = false
        model.reachabilityChanged()
        #expect(!model.canStart)
        model.send(.marker)
        #expect(link.sent.isEmpty)
        #expect(model.commands[.marker] == .failed(WatchRemoteModel.noLinkText))
    }

    @Test("Reachable again but no fresh status yet: Marker and Stop are not sent (#737 review)")
    func notFreshBlocksCommands() {
        let link = Link()
        let model = Self.model(link)
        link.isReachable = false
        model.reachabilityChanged()
        link.isReachable = true
        model.reachabilityChanged()
        model.send(.marker)
        model.send(.stop)
        #expect(link.sent.isEmpty)
        #expect(model.commands[.stop] == .failed(WatchRemoteModel.noLinkText))
    }

    @Test("A status is live only if the link is reachable when it arrives, whichever callback comes first (#737 review)")
    func receivedReadsReachabilityNow() {
        let link = Link()
        let model = Self.model(link)
        link.isReachable = false   // dropped; reachabilityChanged hasn't run yet
        model.received(Self.recording)
        #expect(model.display == .lastKnown(Self.recording), "a context landing as the link drops isn't live")
        link.isReachable = true    // back; the fresh status arrives before reachabilityChanged
        model.received(Self.recording)
        model.reachabilityChanged()
        #expect(model.display == .status(Self.recording), "not stuck dimmed while connected")
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
    @Test("A status delivered late (sent an hour ago) doesn't set the clock: commands aren't stamped an hour back")
    func lateStatusKeepsClock() {
        let link = Link()
        let watchNow = Date(timeIntervalSince1970: 50_000)
        let model = WatchRemoteModel(link: link, now: { watchNow })
        model.received(WatchStatus(state: .armed, sentAt: watchNow.addingTimeInterval(-3_600)))
        model.send(.start)
        #expect(link.sent.first?.sentAt == watchNow)
    }
    /// Runs scheduled work when the test says, not after real time.
    final class Clock {
        var pending: [(TimeInterval, @MainActor () -> Void)] = []
        func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) { pending.append((delay, work)) }
        @MainActor func runAll() {
            let due = pending
            pending = []
            for (_, work) in due { work() }
        }
    }

    @Test("Raising the wrist shows Connecting for a moment, not No link, while the iPhone sends what's true now")
    func connecting() {
        let link = Link()
        let clock = Clock()
        let model = WatchRemoteModel(link: link, after: clock.schedule)
        link.isReachable = false
        model.reachabilityChanged()
        model.appBecameActive()
        #expect(model.display == .connecting)
        link.isReachable = true
        model.reachabilityChanged()
        model.received(Self.recording)
        #expect(model.display == .status(Self.recording))
        let other = WatchRemoteModel(link: link, after: clock.schedule)
        link.isReachable = false
        other.reachabilityChanged()
        other.appBecameActive()
        clock.runAll()
        #expect(other.display == .noLink, "after a few seconds with nothing, it's no link")
    }

    @Test("A command with no answer after a few seconds stops saying Sending: it's unconfirmed")
    func sendTimeout() {
        let link = Link()
        let clock = Clock()
        let model = WatchRemoteModel(link: link, after: clock.schedule)
        model.received(Self.recording)
        model.send(.marker)
        #expect(model.commands[.marker] == .pending)
        clock.runAll()
        #expect(model.commands[.marker] == .unconfirmed)
        link.replies[0](.done)
        #expect(model.commands[.marker] == .confirmed, "a late answer still counts")
    }
}
