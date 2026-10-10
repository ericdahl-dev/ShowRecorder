/// Layout numbers for the Record or Stop button and the Marker button, in points.
public enum TransportLayout {
    /// The gap between the two round buttons: 72, so a press on Marker (done often) can't land on Stop (which
    /// ends the Take). It shrinks only when the space is too narrow for both buttons, and never below 40.
    public static func gap(availableWidth: Double, buttonSize: Double) -> Double {
        max(40, min(availableWidth - 2 * buttonSize, 72))
    }
}
