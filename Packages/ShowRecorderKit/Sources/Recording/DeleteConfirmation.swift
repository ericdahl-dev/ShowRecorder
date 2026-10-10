/// Which confirmation a delete needs. Losing a whole Show means typing its name; one Take or one Stem
/// is a smaller loss and gets a plain confirmation that names what goes.
public enum DeleteConfirmation: Equatable, Sendable {
    case typedName
    case plain

    public static func needed(take: Int?, channel: Int?) -> DeleteConfirmation {
        take == nil && channel == nil ? .typedName : .plain
    }
}
