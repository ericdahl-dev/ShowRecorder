/// How much the record screen's status strip gives up to fit one row, in the order it gives it up (#744): the quiet
/// extras (healthy battery, Warm, the Trial) lose their words first, then the chips use their short text, then every
/// extra is its icon alone. The Drive and any problem keep their words throughout, except at accessibility text sizes.
public enum StripSqueeze: CaseIterable, Sendable {
    case none, quietExtras, shortChips, allExtras

    /// Whether an extra (battery, heat, Dropouts, the Trial) is its icon alone at this step.
    public func extraIsIconOnly(quiet: Bool) -> Bool {
        self == .allExtras || (self != .none && quiet)
    }

    /// Whether the Device, Drive and Mixer chips use their short text.
    public var chipsUseShortText: Bool { self == .shortChips || self == .allExtras }
}
