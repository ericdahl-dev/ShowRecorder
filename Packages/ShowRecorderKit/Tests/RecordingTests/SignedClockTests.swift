import Foundation
@testable import Recording
import Testing

/// Judging the Trial against the newest date the App Store signed, not only the iPhone's clock (#936).
@Suite("Signed clock")
struct SignedClockTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }
    func trial(_ clock: SignedClock, heldAt held: Date) -> Tier {
        Entitlement.tier(ownsPro: false, trialStartedAt: start, now: clock.now(clock: held))
    }

    @Test("A clock held at day 2 after the App Store signed day 20: the Trial has ended")
    func heldClockEnds() {
        var clock = SignedClock()
        clock.observe(day(20))
        #expect(trial(clock, heldAt: day(2)) == .free)
    }

    @Test("No signed date seen: the iPhone's clock decides, as before")
    func noSignedDate() {
        let clock = SignedClock()
        #expect(clock.now(clock: day(2)) == day(2))
        #expect(trial(clock, heldAt: day(2)) == .trial(daysLeft: 12))
    }

    @Test("A clock ahead of the newest signed date is the later one")
    func clockAhead() {
        var clock = SignedClock()
        clock.observe(day(1))
        #expect(clock.now(clock: day(2)) == day(2))
    }

    @Test("An older signed date never replaces a newer one")
    func olderNeverReplaces() {
        var clock = SignedClock()
        clock.observe(day(20))
        clock.observe(day(5))
        #expect(clock.newest == day(20))
    }

    @Test("The newest signed date survives a relaunch")
    func survivesRelaunch() throws {
        let suite = "SignedClockTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SignedClock.lastKnown(from: defaults).newest == nil)
        var clock = SignedClock()
        clock.observe(day(20))
        clock.save(to: defaults)
        #expect(SignedClock.lastKnown(from: defaults).newest == day(20))
    }
}
