import Foundation

/// What the operator reads before starting the 14-day Trial (App Review Guideline 3.1.1): how long it lasts,
/// what Free keeps when it ends, and what Pro costs. The price is the App Store's, so it follows Pro's price changes.
public struct TrialDisclosure: Equatable, Sendable {
    public let title = "14-day Trial"
    public let lines: [String]

    /// - Parameter proPrice: the Pro product's display price, such as "$19.99".
    public init(proPrice: String) {
        lines = [
            "Everything Pro does, at no cost, for 14 days: names and colors from the Mixer, channel names you type, a second Copy on the Drive, unlimited Markers, the Show report, Reaper export, 96 kHz recording and Templates.",
            "When the Trial ends, Free still records every USB Channel, on the Device, with up to 3 Markers per Take. Your Shows and Takes stay yours.",
            "Pro is a one-time purchase of \(proPrice), shared with your family. Nothing is charged when the Trial ends.",
            "A Take never stops because the Trial ends. It is checked only when you press record.",
        ]
    }
}
