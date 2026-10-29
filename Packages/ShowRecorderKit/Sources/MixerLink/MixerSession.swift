import AutoGain
import Foundation
import Observation

/// The Mixer Link as the record screen and the Soundcheck read it (#556), from `MixerSession.state`.
public enum MixerLinkState: Equatable, Sendable {
    /// No Link: the Link is idle.
    case notLinked
    /// Connecting to the Mixer at `host`.
    case connecting(host: String)
    /// Down, with the problem the operator reads (the Soundcheck shows its message).
    case down(MixerLinkProblem)
    /// Up, on the Ready Mixer's family.
    case linked(MixerIdentity, path: MixerLinkPath)
    /// Up, on another Mixer family than the Ready one (#647).
    case otherMixer(MixerIdentity)
}

/// The Mixer Link as the app uses it (#556): whether it is offered for the Ready input, and when it connects, decided
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

    /// The Mixer family of the Ready input; nil when it isn't a Mixer ShowRecorder links to, or nothing is Ready.
    public private(set) var family: MixerFamily?

    /// Whether Mixer Link is offered: only while an X Air or X32 is the Ready input. Everything below is nil or empty
    /// while it isn't, though the Link itself may still be up.
    public var isOffered: Bool { family != nil }

    /// The Link's status, while Mixer Link is offered, whichever Mixer it's to: Settings shows where the Link is and
    /// lets the operator connect to the Ready Mixer instead (#589).
    public var status: MixerLinkStatus? { isOffered ? link.status : nil }

    /// Whether Mixer Link is offered and the linked Mixer is the Ready input's family (#589): an XR18's Link says
    /// nothing about a Ready X32.
    private var linkedMixerIsReady: Bool {
        isOffered && link.identity.map { MixerFamily.reading(model: $0.model) } == family
    }

    /// One Source per USB Channel while the Link is up, offered and to the Ready Mixer's family (#589).
    public var sources: [Source] { linkedMixerIsReady ? link.sources : [] }

    /// The linked Mixer's gain control, while Mixer Link is offered and the linked Mixer is the Ready family, read
    /// fresh each time (#508). Never a stale Link's: with another input Ready, or another Mixer family (#589), nothing
    /// moves a Mixer's gain.
    public var gainControl: (any GainControl)? { linkedMixerIsReady ? link.gainControl : nil }

    /// The linked Mixer's identity, while Mixer Link is offered and the linked Mixer is the Ready family (#556, #589).
    public var identity: MixerIdentity? { linkedMixerIsReady ? link.identity : nil }

    /// The linked Mixer's identity when Mixer Link is offered but the Link is to another Mixer family than the Ready
    /// input's (#647), so the Soundcheck, auto-gain and the status chip say the Link is on another Mixer; nil otherwise.
    public var otherMixerLinked: MixerIdentity? { isOffered && !linkedMixerIsReady ? link.identity : nil }

    /// The Mixer Link as the record screen's chip and the Soundcheck read it, while Mixer Link is offered (#556): the
    /// Link's status, or the other Mixer it's on when that isn't the Ready Mixer's family (#647). Nil while not offered.
    public var state: MixerLinkState? {
        guard isOffered else { return nil }
        if let otherMixerLinked { return .otherMixer(otherMixerLinked) }
        switch link.status {
        case .idle: return .notLinked
        case .connecting(let host): return .connecting(host: host)
        case .down(let problem): return .down(problem)
        case .up(let identity, let path): return .linked(identity, path: path)
        }
    }

    /// The linked Mixer's network name, kept for saving a Template even while Mixer Link isn't offered (nothing Ready,
    /// another input), so a Template keeps finding its Mixer by name (#33, #556). Read only: nothing is sent to the Mixer.
    public var networkNameForTemplates: String? { link.identity?.networkName }

    /// What the linked Mixer sends over USB, while Mixer Link is offered and the linked Mixer is the Ready family
    /// (#556, #589).
    public var capabilities: MixerCapabilities? { linkedMixerIsReady ? link.capabilities : nil }

    /// The Ready input changed: its name as the system gives it, and how many USB Channels it sends. Callers pass nil
    /// when nothing is Ready, or the Ready input has no Mixer family (the App's rule: `recorder.isReady &&
    /// readyFamily != nil`, #556).
    public func ready(interfaceName: String?, usbChannelCount: Int) async {
        family = interfaceName.flatMap { MixerFamily(audioInterfaceName: $0) }
        let countChanged = usbChannelCount != self.usbChannelCount
        self.usbChannelCount = usbChannelCount
        // A new USB Channel count re-reads the Sources, as the App always has (#556): over the Link that's up, or once
        // a connecting Link is up. An idle Link ignores it.
        if countChanged {
            await link.refreshSources(usbChannelCount: usbChannelCount)
        }
        // A remembered Mixer links when an X Air or X32 is Ready (#365), at launch or later; never over a Link that's
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

    /// What the Ready input sends, from the last `ready`.
    @ObservationIgnored private var usbChannelCount = 0

    /// The Mixer's address, remembered between launches; observed, so Settings shows it (#556).
    public var address: String {
        didSet { store.set(address, forKey: Self.addressKey) }
    }

    /// Where the address has always been kept, so an update finds the Mixer the operator set before.
    static let addressKey = "mixerAddress"
}
