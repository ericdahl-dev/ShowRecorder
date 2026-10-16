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

/// The watch asking what is true now (#751): the iPhone answers with a status, and an iPhone a version behind answers
/// with something else, which reads as no answer.
@Suite("Watch status relay")
struct WatchStatusRelayTests {
    static func deliver(_ body: @escaping @Sendable (WatchStatusRelay) -> Void) async -> (WatchStatus?, Bool) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(WatchStatus?, Bool), Never>) in
            let relay = WatchStatusRelay { status in continuation.resume(returning: (status, Thread.isMainThread)) }
            Task.detached { body(relay) }
        }
    }

    @Test("A status answer that arrives on another thread is delivered on the main actor")
    func answerFromBackground() async {
        let status = WatchStatus(state: .armed)
        let answer = await Self.deliver { $0.replied(status.message) }
        #expect(answer.0 == status)
        #expect(answer.1)
    }

    @Test("An error, or the answer of an iPhone a version behind, is no answer")
    func noAnswer() async {
        #expect(await Self.deliver { $0.failed(CocoaError(.fileReadUnknown)) }.0 == nil)
        #expect(await Self.deliver { $0.replied(WatchReply.refused(WatchReply.updateText).message) }.0 == nil)
    }

    @Test("The request is told from a command, and a command isn't taken for one")
    func requestKind() {
        #expect(WatchStatusRequest.isRequest(WatchStatusRequest.message))
        #expect(!WatchStatusRequest.isRequest(WatchCommand(kind: .stop, sentAt: .now).message))
        #expect(throws: (any Error).self, "an iPhone a version behind can't read it as a command, so it refuses rather than acts") {
            try WatchCommand(message: WatchStatusRequest.message)
        }
    }
}
