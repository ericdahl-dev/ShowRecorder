#if os(iOS)
import Foundation
import Observation
import WatchConnectivity
import WatchRemote

/// The iPhone's end of the Apple Watch remote (#100), over WatchConnectivity: sends the watch what to show whenever
/// it changes, and answers its commands through `WatchCommandDesk`.
///
/// Show-Safe Promise: nothing here acts on the link itself. Losing the watch changes nothing on the iPhone; only a
/// fresh command from the wrist does anything, and only what the record screen's own buttons do.
@MainActor
final class WatchLink: NSObject {
    private let desk: WatchCommandDesk
    private let status: @MainActor () -> WatchStatus
    private var session: WCSession?
    /// What the watch was last sent, so an unchanged status isn't sent again.
    private var sent: WatchStatus?

    init(status: @escaping @MainActor () -> WatchStatus, actions: WatchCommandDesk.Actions) {
        self.status = status
        desk = WatchCommandDesk(actions: actions)
    }

    func start() {
        guard session == nil, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        self.session = session
        follow()
    }

    /// Sends the status now, then again whenever anything it's made from changes.
    private func follow() {
        withObservationTracking {
            push(status())
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
    }

    private func push(_ now: WatchStatus) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        // The time it was sent changes every time; what it says is what counts.
        if let sent, sent.state == now.state, sent.problems == now.problems { return }
        do {
            try session.updateApplicationContext(now.message)
            sent = now
        } catch {
            sent = nil
        }
    }

    fileprivate func handle(_ command: WatchCommand) -> WatchReply {
        desk.handle(command)
    }

    fileprivate func activated() {
        sent = nil
        push(status())
    }
}

/// WatchConnectivity's reply handler, carried to the main actor. WatchConnectivity calls it once, from any thread.
private struct ReplyHandler: @unchecked Sendable {
    let send: ([String: Any]) -> Void
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.activated() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The user switched watches: start again with the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.activated() }
    }

    /// The watch app came to the front: send what's true now, with the time now, rather than leave it an old status.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.activated() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let reply = ReplyHandler(send: replyHandler)
        if WatchStatusRequest.isRequest(message) {
            // The watch asking what is true now: answer with the status and the time now. Nothing else happens.
            Task { @MainActor in reply.send(self.status().message) }
            return
        }
        guard let command = try? WatchCommand(message: message) else {
            reply.send(WatchReply.refused(WatchReply.updateText).message)
            return
        }
        Task { @MainActor in
            reply.send(self.handle(command).message)
        }
    }
}
#endif
