import AutoGain
import MixerLink

/// The Mixer's gain control as long as it is the same Mixer (#508, #554): after the Mixer Link reconnects, the new
/// driver, asked for at every step; while the Link is down, on another Mixer, or the Ready input isn't the linked
/// Mixer, a stand-in that refuses, so nothing meant for the first Mixer is ever written to another one.
struct SameMixerControl {
    /// The Mixer's gain control now; nil while the Link is down or the Ready input isn't the linked Mixer.
    let currentControl: () -> (any GainControl)?
    /// Which Mixer is linked now ("FOH · XR18": its network name and model); nil while the Link is down or isn't offered.
    let mixer: () -> String?
    /// The Mixer the moves are made on: the one linked when this was made.
    let madeOn: String?

    init(currentControl: @escaping () -> (any GainControl)?, mixer: @escaping () -> String?) {
        self.currentControl = currentControl
        self.mixer = mixer
        madeOn = mixer()
    }

    /// The linked Mixer's control, or a stand-in that refuses while the Link is down, on another Mixer, or the Ready
    /// input isn't the linked Mixer.
    var control: any GainControl {
        if let madeOn, let now = mixer(), now != madeOn { return NoMixerLink(problem: NoMixerLink.anotherMixer) }
        return currentControl() ?? NoMixerLink()
    }

    /// Whether moves are refused now: the Link is down, on another Mixer, or the Ready input isn't the linked Mixer.
    var isRefusing: Bool { control is NoMixerLink }
}

/// Stands in while the Mixer Link is down or the Ready input isn't the linked Mixer: nothing can move a preamp, and
/// Undo says why and stays offered.
struct NoMixerLink: GainControl {
    static let linkDown = MixerLinkProblem.other("The Mixer Link isn't connected to the Mixer you're recording from, so nothing more was written.")
    static let anotherMixer = MixerLinkProblem.other("The Mixer Link is on another Mixer now, so nothing more was written.")
    var problem = Self.linkDown
    func channel(forUSBChannel usbChannel: Int) -> Int? { nil }
    func preamp(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? { throw problem }
    func lane(ofChannel channel: Int) async throws(MixerLinkProblem) -> Int? { nil }
    func applyMixHold(channel: Int, gainChangeDb: Double, scopes: MixHold.Scopes, live: Set<MixHold.Setting>) async throws(MixerLinkProblem) -> GainStep {
        throw problem
    }
    func undo(_ step: GainStep) async throws(MixerLinkProblem) { throw problem }
}
