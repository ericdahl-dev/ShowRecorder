import Synchronization

/// Finds out which Behringer Mixer answers at a host, X-Air or X32, and talks to it with that one's driver (#199).
///
/// `/xinfo` is asked on every candidate port at once (the X-Air listens on 10024, the X32 on 10023), so an X32
/// costs no timeout on the X-Air's port. The model in the reply picks the driver.
public final class DetectingMixerDriver: MixerDriver {
    private let host: String
    private let ports: [UInt16]
    private let timeout: Duration
    /// The driver for the Mixer that answered, once `identify` has found one.
    private let chosen = Mutex<(any MixerDriver)?>(nil)

    public init(host: String, ports: [UInt16], timeout: Duration = .seconds(1.5)) {
        self.host = host
        self.ports = ports
        self.timeout = timeout
    }

    public convenience init(endpoint: MixerEndpoint, timeout: Duration = .seconds(1.5)) {
        self.init(host: endpoint.host, ports: Self.ports(for: endpoint), timeout: timeout)
    }

    /// The X-Air's port and the X32's, the endpoint's first. A port that is neither was typed on purpose (a mixer
    /// behind a forwarded port, say), so only it is asked.
    public static func ports(for endpoint: MixerEndpoint) -> [UInt16] {
        let known: [UInt16] = [10024, 10023]
        guard known.contains(endpoint.port) else { return [endpoint.port] }
        return [endpoint.port] + known.filter { $0 != endpoint.port }
    }

    /// Whether `model` (from `/xinfo`) is an X32 or M32, all of which the X32 driver reads.
    public static func isX32Family(_ model: String) -> Bool {
        let model = model.uppercased()
        return model.hasPrefix("X32") || model.hasPrefix("M32")
    }

    /// Once a Mixer has been found, asks it again on the same connection, as the Link does when it comes back after
    /// the Mixer went quiet. Probes the ports again only when another kind of Mixer now answers there.
    public func identify() async throws(MixerLinkProblem) -> MixerIdentity {
        if let driver = chosen.withLock({ $0 }) {
            let identity = try await driver.identify()
            if Self.isX32Family(identity.model) == (driver is X32Driver) { return identity }
        }
        let found = await withTaskGroup(of: (UInt16, Result<MixerIdentity, MixerLinkProblem>).self) { group in
            for port in ports {
                group.addTask { [host, timeout] in
                    let probe = XAirDriver(endpoint: MixerEndpoint(host: host, port: port), timeout: timeout)
                    do throws(MixerLinkProblem) {
                        return (port, .success(try await probe.identify()))
                    } catch {
                        return (port, .failure(error))
                    }
                }
            }
            var failures: [UInt16: MixerLinkProblem] = [:]
            for await (port, result) in group {
                switch result {
                case .success(let identity):
                    group.cancelAll()
                    return Result<(UInt16, MixerIdentity), MixerLinkProblem>.success((port, identity))
                case .failure(let problem):
                    failures[port] = problem
                }
            }
            // The problem on the first candidate port says most about the address the operator typed.
            return .failure(ports.first.flatMap { failures[$0] } ?? .noReply(host: host))
        }
        let (port, identity) = try found.get()
        let endpoint = MixerEndpoint(host: host, port: port)
        let driver: any MixerDriver = Self.isX32Family(identity.model)
            ? X32Driver(endpoint: endpoint, timeout: timeout)
            : XAirDriver(endpoint: endpoint, timeout: timeout)
        chosen.withLock { $0 = driver }
        return identity
    }

    public func capabilities(for identity: MixerIdentity) -> MixerCapabilities {
        if let driver = chosen.withLock({ $0 }) { return driver.capabilities(for: identity) }
        return Self.isX32Family(identity.model)
            ? X32Driver(endpoint: MixerEndpoint(host: host)).capabilities(for: identity)
            : XAirDriver(endpoint: MixerEndpoint(host: host)).capabilities(for: identity)
    }

    /// The found Mixer's gain control, when its driver has one (the X32 today; the X-Air with #153).
    public var gainControl: (any GainControl)? {
        chosen.withLock { $0 } as? any GainControl
    }

    public func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        try await driver().sources(usbChannelCount: usbChannelCount)
    }

    public func renewLiveUpdates() async throws(MixerLinkProblem) {
        try await driver().renewLiveUpdates()
    }

    public func sourceChanges() -> AsyncStream<SourceChange> {
        chosen.withLock { $0 }?.sourceChanges() ?? AsyncStream { $0.finish() }
    }

    private func driver() throws(MixerLinkProblem) -> any MixerDriver {
        guard let driver = chosen.withLock({ $0 }) else { throw .noReply(host: host) }
        return driver
    }
}
