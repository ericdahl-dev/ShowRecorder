import Synchronization

/// Finds out which family's Mixer answers at a host and talks to it with that family's driver (#199, #442).
///
/// Every family in the registry (`MixerFamily`) is asked on its own port at once (the X-Air listens on 10024, the X32
/// on 10023), so an X32 costs no timeout on the X-Air's port. The model in the reply picks the driver.
public final class DetectingMixerDriver: MixerDriver {
    /// One family asked on one port.
    public struct Candidate: Equatable, Sendable {
        public var family: MixerFamily
        public var port: UInt16

        public init(family: MixerFamily, port: UInt16) {
            self.family = family
            self.port = port
        }
    }

    private let host: String
    private let candidates: [Candidate]
    private let timeout: Duration
    /// The family and driver of the Mixer that answered, once `identify` has found one.
    private let chosen = Mutex<(family: MixerFamily, driver: any MixerDriver)?>(nil)

    public init(host: String, candidates: [Candidate], timeout: Duration = .seconds(1.5)) {
        self.host = host
        self.candidates = candidates
        self.timeout = timeout
    }

    /// Each port asked as the family that listens there, or the X-Air's way when none does.
    public convenience init(host: String, ports: [UInt16], timeout: Duration = .seconds(1.5)) {
        let candidates = ports.map { port in
            Candidate(family: MixerFamily.allCases.first { $0.probe.port == port } ?? .xAir, port: port)
        }
        self.init(host: host, candidates: candidates, timeout: timeout)
    }

    public convenience init(endpoint: MixerEndpoint, timeout: Duration = .seconds(1.5)) {
        self.init(host: endpoint.host, candidates: Self.candidates(for: endpoint), timeout: timeout)
    }

    /// Every family on its own port, the endpoint's first. A port no family listens on was typed on purpose (a mixer
    /// behind a forwarded port, say), so only it is asked, the X-Air's way.
    public static func candidates(for endpoint: MixerEndpoint) -> [Candidate] {
        let known = MixerFamily.allCases.map { Candidate(family: $0, port: $0.probe.port) }
        guard let given = known.first(where: { $0.port == endpoint.port }) else {
            return [Candidate(family: .xAir, port: endpoint.port)]
        }
        return [given] + known.filter { $0 != given }
    }

    /// The ports `candidates(for:)` asks, in order.
    public static func ports(for endpoint: MixerEndpoint) -> [UInt16] {
        candidates(for: endpoint).map(\.port)
    }

    /// Once a Mixer has been found, asks it again on the same connection, as the Link does when it comes back after
    /// the Mixer went quiet. Probes the ports again only when another kind of Mixer now answers there.
    public func identify() async throws(MixerLinkProblem) -> MixerIdentity {
        if let (family, driver) = chosen.withLock({ $0 }) {
            let identity = try await driver.identify()
            if MixerFamily.reading(model: identity.model) == family { return identity }
        }
        let found = await withTaskGroup(of: (Candidate, Result<MixerIdentity, MixerLinkProblem>).self) { group in
            for candidate in candidates {
                group.addTask { [host, timeout] in
                    let probe = candidate.family.makeDriver(endpoint: MixerEndpoint(host: host, port: candidate.port), timeout: timeout)
                    do throws(MixerLinkProblem) {
                        return (candidate, .success(try await probe.identify()))
                    } catch {
                        return (candidate, .failure(error))
                    }
                }
            }
            var failures: [UInt16: MixerLinkProblem] = [:]
            for await (candidate, result) in group {
                switch result {
                case .success(let identity):
                    group.cancelAll()
                    return Result<(UInt16, MixerIdentity), MixerLinkProblem>.success((candidate.port, identity))
                case .failure(let problem):
                    failures[candidate.port] = problem
                }
            }
            // The problem on the first candidate port says most about the address the operator typed.
            return .failure(candidates.first.flatMap { failures[$0.port] } ?? .noReply(host: host))
        }
        let (port, identity) = try found.get()
        let family = MixerFamily.reading(model: identity.model)
        let driver = family.makeDriver(endpoint: MixerEndpoint(host: host, port: port), timeout: timeout)
        chosen.withLock { $0 = (family, driver) }
        return identity
    }

    public func capabilities(for identity: MixerIdentity) -> MixerCapabilities {
        if let driver = chosen.withLock({ $0?.driver }) { return driver.capabilities(for: identity) }
        return MixerFamily.reading(model: identity.model).makeDriver(endpoint: MixerEndpoint(host: host), timeout: timeout)
            .capabilities(for: identity)
    }

    /// The found Mixer's gain control, when its driver has one.
    public var gainControl: (any GainControl)? {
        chosen.withLock { $0?.driver }?.gainControl
    }

    public func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        try await driver().sources(usbChannelCount: usbChannelCount)
    }

    public func renewLiveUpdates() async throws(MixerLinkProblem) {
        try await driver().renewLiveUpdates()
    }

    public func sourceChanges() -> AsyncStream<SourceChange> {
        chosen.withLock { $0?.driver }?.sourceChanges() ?? AsyncStream { $0.finish() }
    }

    private func driver() throws(MixerLinkProblem) -> any MixerDriver {
        guard let driver = chosen.withLock({ $0?.driver }) else { throw .noReply(host: host) }
        return driver
    }
}
