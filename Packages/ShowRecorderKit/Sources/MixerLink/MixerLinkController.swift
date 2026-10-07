import Foundation
import Observation

/// How the Mixer Link reaches the Mixer. USB (SysEx-wrapped OSC) comes in #24.
public enum MixerLinkPath: Equatable, Sendable {
    case wifi
}

public enum MixerLinkStatus: Equatable, Sendable {
    case idle
    case connecting(host: String)
    case up(MixerIdentity, path: MixerLinkPath)
    case down(MixerLinkProblem)
}

/// The Mixer Link as the app sees it: connect by typed address, then status and Sources.
@MainActor
@Observable
public final class MixerLinkController {
    public private(set) var status: MixerLinkStatus = .idle
    /// One Source per USB Channel while the Link is up. Empty otherwise.
    public private(set) var sources: [Source] = []
    /// What the identified Mixer sends over USB, while the Link is up. Nil otherwise.
    public private(set) var capabilities: MixerCapabilities?

    /// The identified Mixer, while the Link is up.
    public var identity: MixerIdentity? {
        if case .up(let identity, _) = status { identity } else { nil }
    }

    @ObservationIgnored private var driver: (any MixerDriver)?
    @ObservationIgnored private let timeout: Duration
    @ObservationIgnored private let makeDriver: @Sendable (MixerEndpoint, Duration) -> any MixerDriver

    public init(
        timeout: Duration = .seconds(1.5),
        makeDriver: @escaping @Sendable (MixerEndpoint, Duration) -> any MixerDriver = { XAirDriver(endpoint: $0, timeout: $1) }
    ) {
        self.timeout = timeout
        self.makeDriver = makeDriver
    }

    /// Connects to the Mixer at `address` ("10.0.0.20" or "10.0.0.20:10024") and reads its Sources.
    ///
    /// `usbChannelCount` is what the Armed device sends. With nothing Armed (0), as many Sources
    /// are read as the identified Mixer sends over USB, if its driver knows.
    public func connect(to address: String, usbChannelCount: Int) async {
        driver = nil
        capabilities = nil
        guard let endpoint = MixerEndpoint(parsing: address) else {
            sources = []
            status = .down(.invalidAddress(address))
            return
        }
        status = .connecting(host: endpoint.host)
        sources = []
        let driver = makeDriver(endpoint, timeout)
        do {
            let identity = try await driver.identify()
            let capabilities = driver.capabilities(for: identity)
            let count = usbChannelCount > 0 ? usbChannelCount : capabilities.usbChannelCount ?? 0
            sources = try await driver.sources(usbChannelCount: count)
            self.driver = driver
            self.capabilities = capabilities
            status = .up(identity, path: .wifi)
        } catch {
            fail(error)
        }
    }

    /// Re-reads the Sources for a new USB Channel count, such as after a different device is
    /// Armed. Does nothing unless the Link is up.
    public func refreshSources(usbChannelCount: Int) async {
        guard let driver, identity != nil, usbChannelCount > 0, usbChannelCount != sources.count else { return }
        do {
            sources = try await driver.sources(usbChannelCount: usbChannelCount)
        } catch {
            fail(error)
        }
    }

    private func fail(_ problem: MixerLinkProblem) {
        driver = nil
        capabilities = nil
        sources = []
        status = .down(problem)
    }
}

extension MixerEndpoint {
    /// Parses "host" or "host:port". The host must be an IPv4 address or a host name.
    public init?(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let host = String(parts[0])
        var port: UInt16 = 10024
        if parts.count == 2 {
            guard let parsed = UInt16(parts[1]), parsed > 0 else { return nil }
            port = parsed
        }
        guard Self.isValidHost(host) else { return nil }
        self.init(host: host, port: port)
    }

    private static func isValidHost(_ host: String) -> Bool {
        guard !host.isEmpty else { return false }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            return octets.count == 4 && octets.allSatisfy { UInt8($0) != nil }
        }
        // A host name such as "xr18.local": letters, digits, hyphens and dots.
        return octets.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}
