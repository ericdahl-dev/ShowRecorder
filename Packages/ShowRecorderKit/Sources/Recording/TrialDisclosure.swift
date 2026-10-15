import Foundation

/// What the operator reads before starting the 14-day Trial (App Review Guideline 3.1.1): how long it lasts,
/// what Free keeps when it ends, and what Pro costs. The price is the App Store's, so it follows Pro's price changes.
public struct TrialDisclosure: Equatable, Sendable {
    public let title = "14-day Trial"
    public let lines: [String]

    /// - Parameter proPrice: the Pro product's display price, such as "$19.99".
    public init(proPrice: String) {
        lines = [
            Self.includes,
            Self.afterwards,
            "Pro is a one-time purchase of \(proPrice), shared with your family. Nothing is charged when the Trial ends.",
            Self.showSafe,
        ]
    }

    static let includes = "Everything Pro does, at no cost, for 14 days: names and colors from the Mixer, channel names you type, a second Copy on the Drive, unlimited Markers, the Show report, Reaper export, 96 kHz recording and Templates."
    static let afterwards = "When the Trial ends, Free still records every USB Channel, on the Device, with up to \(Entitlement.freeMarkerLimit) Markers per Take. Your Shows and Takes stay yours."
    static let showSafe = "A Take never stops because the Trial ends. It is checked only when you press record."
}

/// What the Trial chip opens during a Trial (#743): what it includes, when it ends, what Free keeps afterward and
/// what Pro costs. The same words as `TrialDisclosure`, with the end date added.
public struct TrialStatusNotice: Equatable, Sendable {
    public let title = "14-day Trial"
    public let lines: [String]

    /// - Parameters:
    ///   - endsOn: the end date, already written for the reader ("October 27").
    ///   - proPrice: the Pro product's display price; nil until the App Store has it, and the price line waits.
    public init(daysLeft: Int, endsOn: String, proPrice: String?) {
        var lines = [
            TrialDisclosure.includes,
            "Ends \(endsOn), in \(daysLeft) \(daysLeft == 1 ? "day" : "days").",
            TrialDisclosure.afterwards,
        ]
        if let proPrice {
            lines.append("Pro is a one-time purchase of \(proPrice), shared with your family. Nothing is charged when the Trial ends.")
        }
        lines.append(TrialDisclosure.showSafe)
        self.lines = lines
    }
}
