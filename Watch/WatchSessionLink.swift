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
        start()
    }

    /// At launch, before the first screen, so the iPhone's last status is there as early as it can be.
    private func start() {
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
        // WatchConnectivity calls these handlers on its own queue (#741): they are the relay's nonisolated
        // methods, not closures written here, which would be main-actor isolated and trap.
        let relay = WatchReplyRelay(reply: reply)
        session.sendMessage(command.message, replyHandler: relay.replied, errorHandler: relay.failed)
    }

    func requestStatus(reply: @escaping @MainActor (WatchStatus?) -> Void) {
        guard let session, isReachable else {
            reply(nil)
            return
        }
        let relay = WatchStatusRelay(reply: reply)
        session.sendMessage(WatchStatusRequest.message, replyHandler: relay.replied, errorHandler: relay.failed)
    }

    fileprivate func receivedContext(_ status: WatchStatus) {
        model.received(status)
    }

    fileprivate func reachabilityChanged() {
        model.reachabilityChanged()
    }
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
