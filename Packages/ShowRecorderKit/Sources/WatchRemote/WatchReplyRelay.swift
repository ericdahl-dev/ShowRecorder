import Foundation

/// Carries a send's answer from WatchConnectivity's queue to the main actor (#741). WatchConnectivity calls its reply
/// and error handlers on a background queue, so they must not be main-actor isolated closures: Swift 6 traps when one
/// is called off the actor. These entry points are nonisolated; the answer then lands on the main actor. WatchConnectivity
/// calls one of them, once.
public struct WatchReplyRelay: @unchecked Sendable {
    private let reply: @MainActor (WatchReply?) -> Void

    public init(reply: @escaping @MainActor (WatchReply?) -> Void) {
        self.reply = reply
    }

    /// The iPhone's answer; one that can't be read is no answer.
    public nonisolated func replied(_ message: [String: Any]) {
        deliver(try? WatchReply(message: message))
    }

    /// The send failed: no answer.
    public nonisolated func failed(_ error: any Error) {
        deliver(nil)
    }

    private nonisolated func deliver(_ answer: WatchReply?) {
        let reply = reply
        Task { @MainActor in reply(answer) }
    }
}
