import Foundation
import WatchConnectivity
import WatchKit
import WatchRemote

/// The watch's end of the remote, over WatchConnectivity: takes the iPhone's status from its application context and
/// sends commands with `sendMessage`, now or not at all (never `transferUserInfo`, which would queue them).
@MainActor
final class WatchSessionLink: NSObject, WatchLinkTransport {
    private(set) var model: WatchRemoteModel!
    private let session = WCSession.isSupported() ? WCSession.default : nil

    override init() {
        super.init()
        model = WatchRemoteModel(link: self)
        model.haptic = { haptic in
            switch haptic {
            case .markerConfirmed: WKInterfaceDevice.current().play(.click)
            case .problem: WKInterfaceDevice.current().play(.notification)
            }
        }
    }

    func start() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    var isReachable: Bool { session?.activationState == .activated && session?.isReachable == true }

    func send(_ command: WatchCommand, reply: @escaping @MainActor (WatchReply?) -> Void) {
        guard let session, isReachable else {
            reply(nil)
            return
        }
        let answer = Answer(reply: reply)
        session.sendMessage(command.message, replyHandler: { message in
            let decoded = try? WatchReply(message: message)
            Task { @MainActor in answer.reply(decoded) }
        }, errorHandler: { _ in
            Task { @MainActor in answer.reply(nil) }
        })
    }

    fileprivate func receivedContext(_ status: WatchStatus) {
        model.received(status)
    }

    fileprivate func reachabilityChanged() {
        model.reachabilityChanged()
    }
}

/// The reply closure, carried back to the main actor from WatchConnectivity's queue. Called once.
private struct Answer: @unchecked Sendable {
    let reply: @MainActor (WatchReply?) -> Void
}

extension WatchSessionLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: (any Error)?) {
        let status = try? WatchStatus(message: session.receivedApplicationContext)
        Task { @MainActor in
            if let status { self.receivedContext(status) }
            self.reachabilityChanged()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let status = try? WatchStatus(message: context) else { return }
        Task { @MainActor in self.receivedContext(status) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.reachabilityChanged() }
    }
}
