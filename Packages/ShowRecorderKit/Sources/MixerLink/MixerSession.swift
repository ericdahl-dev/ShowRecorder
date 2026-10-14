import AutoGain
import Foundation
import Observation

/// The Mixer Link as the app uses it (#556): whether it is offered for the Armed input, and when it connects, decided
/// here instead of across the app. The Link itself is `MixerLinkController`.
@MainActor
@Observable
public final class MixerSession {
    @ObservationIgnored private let link: MixerLinkController
    @ObservationIgnored private let store: UserDefaults
    @ObservationIgnored private let network: () -> ScanRange?
    @ObservationIgnored private let scan: @Sendable ([String]) async -> [FoundMixer]

    /// - Parameters:
    ///   - store: where the Mixer's address is remembered.
    ///   - network: the device's network, to look for a Template's Mixer by name; nil when there's none to scan.
    ///   - scan: asks those addresses who they are (Find Mixers).
    public init(
        link: MixerLinkController = MixerLinkController(), store: UserDefaults = .standard,
        network: @escaping () -> ScanRange? = { ScanRange.currentNetwork() },
        scan: @escaping @Sendable ([String]) async -> [FoundMixer] = { await MixerScanner.scan(hosts: $0) }
    ) {
        self.link = link
        self.store = store
        self.network = network
        self.scan = scan
        address = store.string(forKey: Self.addressKey) ?? ""
    }

    /// The Mixer family of the Armed input; nil when it isn't a Mixer ShowRecorder links to, or nothing is Armed.
    public private(set) var family: MixerFamily?

    /// Whether Mixer Link is offered: only while an X Air or X32 is the Armed input. Everything below is nil or empty
    /// while it isn't, though the Link itself may still be up.
    public var isOffered: Bool { family != nil }

    /// The Link's status, while Mixer Link is offered.
    public var status: MixerLinkStatus? { isOffered ? link.status : nil }

    /// One Source per USB Channel while the Link is up and offered.
    public var sources: [Source] { isOffered ? link.sources : [] }

    /// The linked Mixer's gain control, while Mixer Link is offered, read fresh each time (#508). Never a stale Link's:
    /// with another input Armed, nothing moves a Mixer's gain.
    public var gainControl: (any GainControl)? { isOffered ? link.gainControl : nil }

    /// The linked Mixer's identity, while Mixer Link is offered (#556).
    public var identity: MixerIdentity? { isOffered ? link.identity : nil }

    /// What the linked Mixer sends over USB, while Mixer Link is offered (#556).
    public var capabilities: MixerCapabilities? { isOffered ? link.capabilities : nil }

    /// The Armed input changed: its name as the system gives it, and how many USB Channels it sends. Callers pass nil
    /// when nothing is Armed, or the Armed input has no Mixer family (the App's rule: `recorder.isArmed &&
    /// armedFamily != nil`, #556).
    public func armed(interfaceName: String?, usbChannelCount: Int) async {
        family = interfaceName.flatMap { MixerFamily(audioInterfaceName: $0) }
        let countChanged = usbChannelCount != self.usbChannelCount
        self.usbChannelCount = usbChannelCount
        // A new USB Channel count re-reads the Sources, as the App always has (#556): over the Link that's up, or once
        // a connecting Link is up. An idle Link ignores it.
        if countChanged {
            await link.refreshSources(usbChannelCount: usbChannelCount)
        }
        // A remembered Mixer links when an X Air or X32 is Armed (#365), at launch or later; never over a Link that's
        // already up, connecting or down.
        if isOffered, !address.isEmpty, link.status == .idle {
            await link.connect(to: address, usbChannelCount: usbChannelCount)
        }
    }

    /// Connects to the Mixer at `address`, whatever the Link is doing: the operator asked (Settings, Find Mixers).
    /// An empty address still tries, and the Link says it's invalid, as Settings always has (#556).
    public func connect() async {
        await link.connect(to: address, usbChannelCount: usbChannelCount)
    }

    /// Links to a Template's Mixer (#33): at its saved address first, then, if the Mixer there isn't the one named,
    /// wherever a Mixer with that network name answers on this network. Only while Mixer Link is offered (#365); the
    /// Template keeps its Mixer either way.
    public func follow(mixerAt templateAddress: String, named networkName: String?) async {
        guard isOffered else { return }
        if !templateAddress.isEmpty {
            address = templateAddress
            await link.connect(to: address, usbChannelCount: usbChannelCount)
        }
        guard let networkName, link.identity?.networkName != networkName, let range = network() else { return }
        let found = await scan(range.hosts).first { $0.identity.networkName == networkName }?.host ?? templateAddress
        guard found != address || link.identity == nil, !found.isEmpty else { return }
        address = found
        await link.connect(to: found, usbChannelCount: usbChannelCount)
    }

    /// Tries a Link that is down again (during a Take, say). A Link that's up, connecting or idle is left alone.
    public func retry() async {
        guard case .down = link.status, !address.isEmpty else { return }
        await link.connect(to: address, usbChannelCount: usbChannelCount)
    }

    /// What the Armed input sends, from the last `armed`.
    @ObservationIgnored private var usbChannelCount = 0

    /// The Mixer's address, remembered between launches; observed, so Settings shows it (#556).
    public var address: String {
        didSet { store.set(address, forKey: Self.addressKey) }
    }

    /// Where the address has always been kept, so an update finds the Mixer the operator set before.
    static let addressKey = "mixerAddress"
}
