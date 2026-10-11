/// Where the Marker list, Channel names and Settings open on the record screen. Stop and Marker must stay in
/// reach while one is open during a Take, and the meters never get shorter for it (#250).
public enum LivePanelPlacement: Equatable, Sendable {
    /// iPhone portrait: the panel takes the meters' place; the transport below stays visible.
    case overMeters
    /// iPhone landscape: the panel sits beside the meters, which get narrower, not shorter.
    case besideMeters
    /// iPad and Mac: a sheet, until they get docked panels (#255).
    case sheet

    /// From the screen's size classes: compact height is a landscape iPhone, compact width a portrait one.
    public init(horizontalCompact: Bool, verticalCompact: Bool) {
        if verticalCompact { self = .besideMeters }
        else if horizontalCompact { self = .overMeters }
        else { self = .sheet }
    }
}
