/// The inputs of an iOS audio route, as far as a running Take cares: which ports, and how many channels each offers.
/// Only a new input may move a Take, because moving restarts the input and costs audio (#233).
public struct InputRoute: Equatable, Sendable {
    public struct Port: Equatable, Sendable {
        public var uid: String
        /// The phone's own microphone.
        public var isBuiltIn: Bool
        public var channelCount: Int

        public init(uid: String, isBuiltIn: Bool, channelCount: Int) {
            self.uid = uid
            self.isBuiltIn = isBuiltIn
            self.channelCount = channelCount
        }
    }

    public var ports: [Port]

    public init(ports: [Port]) {
        self.ports = ports
    }

    /// Whether going from `old` to `new` means a new input, so a running Take moves to it (and a stopped one re-Arms).
    public static func isNewInput(from old: InputRoute, to new: InputRoute) -> Bool {
        old.ports.map(\.uid) != new.ports.map(\.uid)
    }
}
