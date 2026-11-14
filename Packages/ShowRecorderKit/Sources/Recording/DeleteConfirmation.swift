/// Which confirmation a delete needs. Losing a whole Show means typing its name; one Take or one Stem
/// is a smaller loss and gets a plain confirmation that names what goes.
public enum DeleteConfirmation: Equatable, Sendable {
    case typedName
    case plain

    /// `takeCount` is the Show's Takes as the list read them: a Show with none left, such as one whose files were
    /// removed in Files, holds nothing recorded, so typing its name guards nothing.
    public static func needed(take: Int?, channel: Int?, takeCount: Int) -> DeleteConfirmation {
        take == nil && channel == nil && takeCount > 0 ? .typedName : .plain
    }
}
