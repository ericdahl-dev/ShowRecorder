import Foundation

/// The newest date the App Store has signed, kept so a clock held still or set back can't keep a Trial alive (#936).
public struct SignedClock: Equatable, Sendable {
    public private(set) var newest: Date?

    private static let key = "signedClock.newest"

    public init(newest: Date? = nil) {
        self.newest = newest
    }

    /// Keeps `signed` if it is later than any seen: an older date never replaces a newer one.
    public mutating func observe(_ signed: Date) {
        if newest.map({ signed > $0 }) ?? true { newest = signed }
    }

    /// The date to judge the Trial against: the iPhone's clock, or the newest signed date if that is later.
    public func now(clock: Date) -> Date {
        newest.map { max(clock, $0) } ?? clock
    }

    public static func lastKnown(from defaults: UserDefaults = .standard) -> SignedClock {
        SignedClock(newest: defaults.object(forKey: key) as? Date)
    }

    public func save(to defaults: UserDefaults = .standard) {
        defaults.set(newest, forKey: Self.key)
    }
}
