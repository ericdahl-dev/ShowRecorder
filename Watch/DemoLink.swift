import Foundation
import WatchRemote

/// `-watchDemo`: a pretend iPhone for screenshots and layout checks in the Simulator. It is always reachable,
/// sends a Recording status with a problem, and says done to every command. Never used otherwise.
@MainActor
final class DemoLink: WatchLinkTransport {
    static var isOn: Bool { ProcessInfo.processInfo.arguments.contains("-watchDemo") }

    let isReachable = true
    private(set) var model: WatchRemoteModel!

    init() {
        model = WatchRemoteModel(link: self)
        model.received(WatchStatus(
            state: .recording(startedAt: .now.addingTimeInterval(-754), takeTitle: "Take 03", markerCount: 2),
            problems: [.driveLowSpace]))
    }

    func send(_ command: WatchCommand, reply: @escaping @MainActor (WatchReply?) -> Void) {
        reply(.done)
    }
}
