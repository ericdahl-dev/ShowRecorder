import Destinations
import Foundation

/// When the app asks the operator for an App Store rating: only after a clean Take, from the second clean Take on, once
/// the Take has stopped and the screen is idle; at most once per app version and never more than `mostAsks` times.
///
/// A clean Take was stopped (by the operator, a Mixer Trigger or the app, not by the recorder), had no Dropouts, and
/// every Copy it was meant to have was written whole: no Gaps (even Repaired ones), no Drive only Stand-in. The app feeds
/// it the sequencer's Take-ended events, off the real-time audio path (ADR 0002), and keeps it in UserDefaults.
public struct RatingPromptPolicy: Codable, Equatable, Sendable {
    /// Asks never come before this many clean Takes.
    public static let cleanTakesBeforeAsking = 2
    /// The most times the app asks, ever. Apple also shows the prompt at most three times a year.
    public static let mostAsks = 3

    /// How many Takes have ended cleanly.
    public private(set) var cleanTakes = 0
    /// Whether the last Take to end was clean and hasn't been asked about, so the next idle moment may ask.
    public private(set) var lastTakeClean = false
    /// The app version last asked in; nil until the first ask.
    public private(set) var lastAskedVersion: String?
    /// How many times the app has asked.
    public private(set) var timesAsked = 0

    public init() {}

    /// A Take ended: `dropouts` and `copies` are the recorder's for that Take, read when the sequencer says it ended.
    public mutating func takeEnded(_ end: TakeEnd, dropouts: Int, copies: TakeCopies) {
        // Every Copy written whole: complete, or never meant (no Drive at record, or Record to the Device).
        let copiesWhole = DestinationKind.allCases.allSatisfy { [.complete, .missing].contains(copies[$0]) }
        lastTakeClean = end.reason == .stopped && dropouts == 0 && copiesWhole
        if lastTakeClean { cleanTakes += 1 }
    }

    /// Whether to ask now, in `appVersion` (CFBundleShortVersionString). `isRecording`: a Take is running or finishing.
    public func shouldAsk(appVersion: String, isRecording: Bool) -> Bool {
        !isRecording && lastTakeClean && cleanTakes >= Self.cleanTakesBeforeAsking && lastAskedVersion != appVersion
            && timesAsked < Self.mostAsks
    }

    /// The app asked in `appVersion`. The next ask needs another clean Take.
    public mutating func asked(appVersion: String) {
        lastAskedVersion = appVersion
        lastTakeClean = false
        timesAsked += 1
    }

    static let defaultsKey = "ratingPrompt"

    /// What was saved, or a fresh policy when nothing (or nothing readable) was.
    public static func load(from defaults: UserDefaults = .standard) -> RatingPromptPolicy {
        guard let data = defaults.data(forKey: defaultsKey) else { return RatingPromptPolicy() }
        return (try? JSONDecoder().decode(RatingPromptPolicy.self, from: data)) ?? RatingPromptPolicy()
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
