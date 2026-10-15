import Foundation
import Testing
@testable import WatchRemote

/// WatchConnectivity calls a send's reply and error handlers on its own queue (#741). The relay's entry points are
/// nonisolated, so calling them off the main actor is safe; the answer then lands on the main actor.
@Suite("Watch reply relay")
struct WatchReplyRelayTests {
    @Test("A reply that arrives on another thread is decoded and delivered on the main actor")
    func replyFromBackground() async {
        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<(WatchReply?, Bool), Never>) in
            let relay = WatchReplyRelay { reply in continuation.resume(returning: (reply, Thread.isMainThread)) }
            Task.detached { relay.replied(WatchReply.done.message) }
        }
        #expect(answer.0 == .done)
        #expect(answer.1, "delivered on the main actor")
    }

    @Test("An error that arrives on another thread is delivered as no answer")
    func errorFromBackground() async {
        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<(WatchReply?, Bool), Never>) in
            let relay = WatchReplyRelay { reply in continuation.resume(returning: (reply, Thread.isMainThread)) }
            Task.detached { relay.failed(CocoaError(.fileReadUnknown)) }
        }
        #expect(answer.0 == nil)
        #expect(answer.1)
    }

    @Test("A reply that can't be read is delivered as no answer, not dropped")
    func unreadable() async {
        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<WatchReply?, Never>) in
            let relay = WatchReplyRelay { reply in continuation.resume(returning: reply) }
            Task.detached { relay.replied(["nonsense": 1]) }
        }
        #expect(answer == nil)
    }
}
