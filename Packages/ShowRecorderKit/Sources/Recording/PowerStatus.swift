import Foundation

/// What the device's battery and heat mean for the record screen: a chip for each worth showing, and the
/// warnings to raise. Plain rules with no platform code; the app reads the system and passes the numbers in.
///
/// - Battery: shown as a percentage, with "charging" or "charged" in words as well as a symbol. At 20% or
///   less and not charging it warns; at 10% or less it is urgent. Charging, full and "can't tell" never
///   warn. A device with no battery (a desktop Mac) has no battery status at all.
/// - Heat: nominal shows nothing, fair shows a quiet chip, serious warns and critical is urgent.
public struct PowerStatus: Equatable, Sendable {
    public enum Charging: Sendable {
        case charging, full, unplugged
        /// The system couldn't say.
        case unknown
    }

    /// The system's thermal state (`ProcessInfo.ThermalState`), without the platform import.
    public enum Thermal: Sendable {
        case nominal, fair, serious, critical
    }

    /// One chip's content. `state` is how loudly it draws the eye, as for the Destination chips.
    public struct Chip: Equatable, Sendable {
        public var text: String
        /// A shorter text for a crowded strip: the symbol already says what the dropped words did.
        public var shortText: String
        /// An SF Symbol name.
        public var symbol: String
        public var state: StatusChip.State

        public init(text: String, shortText: String? = nil, symbol: String, state: StatusChip.State) {
            self.text = text
            self.shortText = shortText ?? text
            self.symbol = symbol
            self.state = state
        }
    }

    public struct Warning: Equatable, Identifiable, Sendable {
        /// "battery" or "thermal".
        public var id: String
        public var tone: ScreenAlert.Tone
        public var text: String
    }

    /// Nil when the device has no battery.
    public var battery: Chip?
    /// Nil when the heat is nominal.
    public var thermal: Chip?
    /// Most urgent first; heat before battery when they tie.
    public var warnings: [Warning]

    /// The chips to add to the status strip: battery, then heat, those that exist.
    public var chips: [Chip] { [battery, thermal].compactMap { $0 } }

    /// The warnings as record-screen alerts, most urgent first. They have no button: they stay while the
    /// condition holds.
    public var alerts: [ScreenAlert] {
        warnings.map { ScreenAlert(id: $0.id, priority: .power, tone: $0.tone, text: $0.text) }
    }

    /// Percent at or below which an unplugged device warns, and the lower one at which it is urgent.
    public static let warnPercent = 20
    public static let urgentPercent = 10

    /// - Parameter batteryLevel: 0...1, or nil when the device has no battery.
    public init(batteryLevel: Double?, charging: Charging, thermal: Thermal) {
        var warnings: [Warning] = []

        if let batteryLevel {
            let percent = Int((min(max(batteryLevel, 0), 1) * 100).rounded())
            let onBattery = charging == .unplugged
            let urgent = onBattery && percent <= Self.urgentPercent
            let low = onBattery && percent <= Self.warnPercent
            let text: String
            switch charging {
            case .charging: text = "\(percent)% charging"
            case .full: text = "\(percent)% charged"
            case .unplugged, .unknown: text = "\(percent)%"
            }
            battery = Chip(
                text: text,
                shortText: "\(percent)%",
                symbol: Self.batterySymbol(percent: percent, charging: charging == .charging),
                state: urgent ? .failed : low ? .attention : .ok)
            if urgent {
                warnings.append(Warning(
                    id: "battery", tone: .critical,
                    text: "Battery at \(percent)% and not charging. Plug in now or the recording will stop when it runs out."))
            } else if low {
                warnings.append(Warning(
                    id: "battery", tone: .warning,
                    text: "Battery at \(percent)% and not charging. Plug in soon."))
            }
        } else {
            battery = nil
        }

        switch thermal {
        case .nominal:
            self.thermal = nil
        case .fair:
            self.thermal = Chip(text: "Warm", symbol: "thermometer.medium", state: .neutral)
        case .serious:
            self.thermal = Chip(text: "Hot", symbol: "thermometer.high", state: .attention)
            warnings.append(Warning(
                id: "thermal", tone: .warning,
                text: "The device is running hot and may slow down. Move it into the shade and let air reach it."))
        case .critical:
            self.thermal = Chip(text: "Very hot", symbol: "thermometer.high", state: .failed)
            warnings.append(Warning(
                id: "thermal", tone: .critical,
                text: "The device is very hot and may slow down or shut down. Cool it now: shade, airflow, take it out of any case."))
        }

        // Critical before warning; heat before battery when they tie. Stable on the order built above.
        self.warnings = warnings.sorted { lhs, rhs in
            if lhs.tone != rhs.tone { return lhs.tone == .critical }
            return lhs.id == "thermal" && rhs.id != "thermal"
        }
    }

    private static func batterySymbol(percent: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
