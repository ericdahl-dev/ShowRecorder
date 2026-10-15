import AutoGain
import MixerLink

/// An in-memory Mixer for a `MixerSession` in Recording tests: no sockets. It answers `identify()` at once, or, when
/// `holdsIdentify`, only once `release()` is called, as a Mixer slow to answer does (the Link stays connecting).
final class LinkedMixerDriver: MixerDriver {
    let identity: MixerIdentity
    let control: (any GainControl)?
    private let releases: AsyncStream<Void>?
    private let releaser: AsyncStream<Void>.Continuation?

    init(model: String = "XR18", networkName: String = "FOH", gainControl: (any GainControl)?, holdsIdentify: Bool = false) {
        identity = MixerIdentity(networkName: networkName, model: model, firmware: "1.22")
        control = gainControl
        if holdsIdentify {
            let (stream, continuation) = AsyncStream<Void>.makeStream()
            releases = stream
            releaser = continuation
        } else {
            releases = nil
            releaser = nil
        }
    }

    var gainControl: (any GainControl)? { control }

    func identify() async throws(MixerLinkProblem) -> MixerIdentity {
        if let releases { for await _ in releases { break } }
        return identity
    }

    func capabilities(for identity: MixerIdentity) -> MixerCapabilities {
        MixerCapabilities(usbChannelCount: 18, nameableUSBChannelCount: 16)
    }

    func sources(usbChannelCount: Int) async throws(MixerLinkProblem) -> [Source] {
        (0..<usbChannelCount).map { Source.fallback(usbChannel: $0 + 1) }
    }

    func renewLiveUpdates() async throws(MixerLinkProblem) {}

    func sourceChanges() -> AsyncStream<SourceChange> { AsyncStream { _ in } }

    /// A held `identify()` answers.
    func release() { releaser?.finish() }
}
