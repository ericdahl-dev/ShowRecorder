import Foundation

/// Clip protection on the record screen (#448): only during a Take (Eric, 2026-10-13), so it never moves the same
/// preamps as auto-gain, which runs only between Takes; and only when switched on (off by default).
/// It follows Takes (`TakeSequencer.events`) and takes every meter read the screen takes.
@MainActor
public final class ClipGuard {
    /// Whether clip protection is switched on, read when each Take starts.
    public var isOn: () -> Bool = { ClipProtectionSetting.isOffered() && ClipProtectionSetting.isOn() }
    /// Clip protection on the linked Mixer, or nil when it can't set gain.
    public var makeProtection: () -> ClipProtection? = { nil }
    /// Whether the recorder is recording now: a window read after it stopped, before the Take's end arrives, is
    /// left alone.
    public var isRecording: () -> Bool = { true }
    /// Protecting the running Take; nil between Takes.
    public private(set) var active: ClipProtection?

    public init() {}

    /// A Take that starts turns protection on (when switched on); one that ends turns it off.
    public func handle(_ event: TakeEvent) {
        switch event {
        case .takeStarted:
            active = isOn() ? makeProtection() : nil
            active?.takeStarted()
        case .takeEnded:
            active?.stop()
            active = nil
        default:
            break
        }
    }

    /// Switched off in Settings: stops at once, mid-Take too, so the operator can always stop it.
    public func switchedOff() {
        active?.stop()
        active = nil
    }

    /// One meter read, every USB Channel's window (USB Channel 1 first), waiting for any turn-down it starts. Nothing
    /// between Takes. Only tests use it; the record screen calls `meters(_:)`.
    public func observe(_ levels: [ChannelLevel]) async {
        guard isRecording() else { return }
        await active?.observe(levels)
    }

    /// The same, at once (#554): a turn-down it starts runs on its own, so the meters never wait on the Mixer.
    @discardableResult
    public func meters(_ levels: [ChannelLevel]) -> Task<Void, Never>? {
        guard let active, isRecording() else { return nil }
        return active.meters(levels)
    }
}
