import AutoGain
import MixerLink
import Synchronization

/// An in-memory Mixer driver for `MixerLinkController` tests (#442): no sockets. Its Mixer answers until told not to,
/// pushes Source changes on demand and counts renewals.
final class FakeMixerDriver: MixerDriver {
    struct State: Sendable {
        var identity = MixerIdentity(networkName: "FOH", model: "XR18", firmware: "1.22")
        var capabilities = MixerCapabilities(usbChannelCount: 18, nameableUSBChannelCount: 16)
        /// Nil when the Mixer answers; otherwise what every call throws.
        var problem: MixerLinkProblem?
        var names: [Int: String] = [:]
        var renewals = 0
        /// Every count `sources(usbChannelCount:)` was asked for.
        var sourceReads: [Int] = []
        /// When set, `identify()` waits for `releaseIdentify()`, as a Mixer slow to answer does.
        var holdsIdentify = false
    }

    let state: Mutex<State>
    let control: (any GainControl)?
    private let changes = AsyncStream<SourceChange>.makeStream()
    private let identifyReleases = AsyncStream<Void>.makeStream()

    init(_ state: State = State(), gainControl: (any GainControl)? = nil) {
        self.state = Mutex(state)
        control = gainControl
    }

    var gainControl: (any GainControl)? { control }

    func identify() async throws(MixerLinkProblem) -> MixerIdentity {
        if state.withLock({ $0.holdsIdentify }) {
            for await _ in identifyReleases.stream { break }
        }
        let (identity, problem) = state.withLock { ($0.identity, $0.problem) }
        if let problem { throw problem }
        return identity
    }

    func capabilities(for identity: MixerIdentity) -> MixerCapabilities {
        state.withLock { $0.capabilities }
    }

    func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        let (names, problem) = state.withLock { state in
            state.sourceReads.append(usbChannelCount)
            return (state.names, state.problem)
        }
        if let problem { throw problem }
        return (1...max(1, usbChannelCount)).prefix(usbChannelCount).map { channel in
            names[channel].map { Source(name: $0, color: .off) } ?? Source.fallback(usbChannel: channel)
        }
    }

    func renewLiveUpdates() async throws(MixerLinkProblem) {
        let problem = state.withLock { state in
            state.renewals += 1
            return state.problem
        }
        if let problem { throw problem }
    }

    func sourceChanges() -> AsyncStream<SourceChange> { changes.stream }

    /// The held `identify()` answers (see `State.holdsIdentify`).
    func releaseIdentify() {
        state.withLock { $0.holdsIdentify = false }
        identifyReleases.continuation.yield()
    }

    /// The Mixer pushes `change`, as it does when a name or color changes on the desk.
    func push(_ change: SourceChange) {
        changes.continuation.yield(change)
    }
}

/// A gain control that only maps USB Channels to input channels one to one and moves nothing.
struct StubGainControl: GainControl {
    func channel(forUSBChannel usbChannel: Int) -> Int? { usbChannel }
    func preamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? { channel }
    func lane(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? { nil }
    func applyMixHold(channel: Int, gainChangeDb: Double, scopes: MixHold.Scopes) async throws(MixerLinkProblem) -> GainStep {
        GainStep(channel: channel, headamp: channel, fromGainDb: 0, toGainDb: gainChangeDb, held: [:], limitedBy: nil, restore: [:])
    }
    func undo(_ step: GainStep) async throws(MixerLinkProblem) {}
}
