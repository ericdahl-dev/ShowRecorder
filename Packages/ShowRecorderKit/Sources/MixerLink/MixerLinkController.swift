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
    @ObservationIgnored private let renewEvery: Duration
    @ObservationIgnored private let makeDriver: @Sendable (MixerEndpoint, Duration) -> any MixerDriver

    public init(
        timeout: Duration = .seconds(1.5),
        renewEvery: Duration = .seconds(5),
        makeDriver: @escaping @Sendable (MixerEndpoint, Duration) -> any MixerDriver = { XAirDriver(endpoint: $0, timeout: $1) }
    ) {
        self.timeout = timeout
        self.renewEvery = renewEvery
        self.makeDriver = makeDriver
    }

    /// Connects to the Mixer at `address` ("10.0.0.20" or "10.0.0.20:10024") and reads its Sources.
    ///
    /// `usbChannelCount` is what the Armed device sends. With nothing Armed (0), as many Sources
    /// are read as the identified Mixer sends over USB, if its driver knows.
    public func connect(to address: String, usbChannelCount: Int) async {
        liveTasks.forEach { $0.cancel() }
        liveTasks = []
        driver = nil
        capabilities = nil
        pendingUSBChannelCount = nil
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
            sources = try await Self.sources(from: driver, capabilities: capabilities, usbChannelCount: count)
            // A device Armed while connecting asked for its own count; read that instead.
            if let pending = pendingUSBChannelCount, pending != sources.count {
                sources = try await Self.sources(from: driver, capabilities: capabilities, usbChannelCount: pending)
            }
            pendingUSBChannelCount = nil
            self.driver = driver
            self.capabilities = capabilities
            wantedUSBChannelCount = sources.count
            status = .up(identity, path: .wifi)
            startLiveUpdates(driver)
        } catch {
            fail(error)
        }
    }

    /// Re-reads the Sources for a new USB Channel count, such as after a different device is
    /// Armed. While connecting, the count is remembered for when the Mixer answers; while the Link
    /// is down or idle this does nothing.
    public func refreshSources(usbChannelCount: Int) async {
        guard usbChannelCount > 0 else { return }
        if case .connecting = status {
            pendingUSBChannelCount = usbChannelCount
            return
        }
        guard let driver, let capabilities, identity != nil, usbChannelCount != sources.count else { return }
        do {
            sources = try await Self.sources(from: driver, capabilities: capabilities, usbChannelCount: usbChannelCount)
            wantedUSBChannelCount = sources.count
        } catch {
            fail(error)
        }
    }

    @ObservationIgnored private var pendingUSBChannelCount: Int?
    @ObservationIgnored private var liveTasks: [Task<Void, Never>] = []

    /// Keeps the Sources current: renews the Mixer's live updates and applies the changes it pushes.
    private func startLiveUpdates(_ driver: any MixerDriver) {
        liveTasks.forEach { $0.cancel() }
        let changes = driver.sourceChanges()
        liveTasks = [
            Task { [weak self] in
                for await change in changes { self?.apply(change) }
            },
            Task { [weak self, renewEvery] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.renew(driver)
                    try? await Task.sleep(for: renewEvery)
                }
            },
        ]
    }

    /// One renewal. A Mixer that doesn't answer takes the Link down; one that answers while the Link is
    /// down brings it back up, with the Sources read again since renames may have been missed.
    private func renew(_ driver: any MixerDriver) async {
        do {
            try await driver.renewLiveUpdates()
            guard identity == nil else { return }
            let identity = try await driver.identify()
            let capabilities = driver.capabilities(for: identity)
            let sources = try await Self.sources(from: driver, capabilities: capabilities, usbChannelCount: wantedUSBChannelCount)
            guard !Task.isCancelled else { return }
            self.sources = sources
            self.driver = driver
            self.capabilities = capabilities
            status = .up(identity, path: .wifi)
        } catch {
            guard !Task.isCancelled else { return }
            fail(error)
        }
    }

    /// How many Sources to read again when the Link comes back.
    @ObservationIgnored private var wantedUSBChannelCount = 0

    private func apply(_ change: SourceChange) {
        guard sources.indices.contains(change.usbChannel - 1) else { return }
        var source = sources[change.usbChannel - 1]
        if let name = change.name {
            source.name = name.isEmpty ? Source.fallback(usbChannel: change.usbChannel).name : name
            source.hasMixerName = !name.isEmpty
        }
        if let color = change.color { source.color = color }
        sources[change.usbChannel - 1] = source
    }

    /// One Source per USB Channel: named by the driver as far as the Mixer's capabilities allow,
    /// "USB NN" after that.
    private static func sources(
        from driver: any MixerDriver, capabilities: MixerCapabilities, usbChannelCount: Int
    ) async throws(MixerLinkProblem) -> [Source] {
        let named = min(usbChannelCount, capabilities.nameableUSBChannelCount)
        var sources = try await driver.sources(usbChannelCount: named)
        if sources.count < usbChannelCount {
            sources += (sources.count + 1...usbChannelCount).map { Source.fallback(usbChannel: $0) }
        }
        return sources
    }

    private func fail(_ problem: MixerLinkProblem) {
        pendingUSBChannelCount = nil
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
