import Foundation

/// Where a Take is written (#805): the Device, the Drive, or Both. Read at the record press.
public enum RecordTo: String, CaseIterable, Codable, Sendable {
    case device, drive, both

    /// Both, so a Take has two Copies unless the operator picks one Destination.
    public static let standard = RecordTo.both

    /// What a Take pressed now records to. Where it isn't offered (`RecordToAvailability`), every choice records as
    /// before: the Device, and the Drive when there is one and it's allowed. Free records to the Device: the Drive is Pro.
    public func atPress(isOffered: Bool, driveAllowed: Bool) -> RecordTo {
        guard driveAllowed else { return .device }
        return isOffered ? self : .both
    }

    /// What the Settings picker shows as chosen: Free records to the Device whatever is saved, so it shows the Device;
    /// the saved choice applies again with Pro or the Trial (Eric, #805).
    public func shown(driveAllowed: Bool) -> RecordTo {
        driveAllowed ? self : .device
    }

    /// Whether picking this in Settings offers Pro instead of choosing it: on Free the Drive is Pro (Eric, #805).
    public func offersPro(driveAllowed: Bool) -> Bool {
        usesDrive && !driveAllowed
    }

    /// Whether Settings › Storage shows the Drive's warning and its time left: only where Takes go to the Drive. With This
    /// iPhone in effect (chosen, or on Free) they go away and the Drive folder button is dimmed (Eric, #805). Where Record
    /// to isn't offered, Settings is as before.
    public func settingsShowsDrive(isOffered: Bool, driveAllowed: Bool) -> Bool {
        !isOffered || shown(driveAllowed: driveAllowed).usesDrive
    }

    /// Whether a Take is written to the Drive (when there is one).
    public var usesDrive: Bool { self != .device }
    /// Whether the Drive is the Take's only Destination: Drive only (#196, ADR 0006).
    public var isDriveOnly: Bool { self == .drive }

    /// The name in the Settings picker: "This iPhone" (the hardware's word), "Drive" or "Both".
    public func label(deviceWord: String) -> String {
        switch self {
        case .device: "This \(deviceWord)"
        case .drive: "Drive"
        case .both: "Both"
        }
    }
}

/// The "Record to" setting: one place to read and write it.
public enum RecordToSetting {
    /// The key it is stored under.
    public static let key = "recordTo"

    /// The stored choice, or the default when nothing valid is stored.
    public static func load(from defaults: UserDefaults = .standard) -> RecordTo {
        defaults.string(forKey: key).flatMap(RecordTo.init(rawValue:)) ?? .standard
    }

    /// What the Recorder's `recordTo` is set to: the stored choice where Record to is offered, else Both.
    public static func forRecorder(isOffered: Bool, from defaults: UserDefaults = .standard) -> RecordTo {
        isOffered ? load(from: defaults) : .both
    }

    public static func save(_ choice: RecordTo, to defaults: UserDefaults = .standard) {
        defaults.set(choice.rawValue, forKey: key)
    }
}

/// Where "Record to" (#805) is offered: Debug and TestFlight builds, never the App Store build until Eric has tried it
/// on a device. Opening it up is this one rule. Outside it a Take goes to the Device, and the Drive when there is one and it's Pro.
/// The environment is the one `DemoSignalAvailability` resolves from StoreKit.
public enum RecordToAvailability {
    /// Where it is offered; moving it up a level is this one line.
    public static let level: AvailabilityLevel = .debugAndTestFlight

    /// `environment` is nil until StoreKit has answered; only a sandbox (TestFlight) answer offers it in a Release build.
    public static func isAvailable(isDebugBuild: Bool, environment: DistributionEnvironment?) -> Bool {
        level.isOn(isDebugBuild: isDebugBuild, environment: environment)
    }

    /// The answer for the running app, from what `DemoSignalAvailability.resolveEnvironment()` has found so far.
    public static var isAvailableInThisBuild: Bool { level.isOnInThisBuild }
}
