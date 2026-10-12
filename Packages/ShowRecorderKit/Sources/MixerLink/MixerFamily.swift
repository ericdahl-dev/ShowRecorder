/// A family of mixers the Mixer Link can talk to, recognized from the audio interface's name (#365). Mixer Link is
/// offered only for one of these; any other input (a built-in mic, the Demo signal, an EVO 4, a DJM) gets none.
/// Mixer packs (#412) unlock by family too.
public enum MixerFamily: Sendable, Equatable, CaseIterable {
    /// XR18, MR18 (and the XR12 and XR16, which send no multichannel USB). Seen on the Mac as "X18/XR18".
    case xAir
    /// X32 and M32 with a USB card. The names are what Behringer and Midas call their cards ("X-USB", "DN32-USB");
    /// not yet seen on a real card.
    case x32

    public init?(audioInterfaceName name: String) {
        let name = name.uppercased()
        if ["XR18", "MR18", "X18"].contains(where: name.contains) {
            self = .xAir
        } else if ["X-USB", "X32", "M32", "DN32"].contains(where: name.contains) {
            self = .x32
        } else {
            return nil
        }
    }
}
