import Foundation
@testable import Recording
import Testing

/// Free, Trial and Pro (ADR 0004), judged when record is pressed.
@Suite("Entitlement")
struct EntitlementTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func day(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    @Test("Owning Pro is Pro, whatever the Trial says")
    func pro() {
        #expect(Entitlement.tier(ownsPro: true, trialStartedAt: nil, now: start) == .pro)
        #expect(Entitlement.tier(ownsPro: true, trialStartedAt: start, now: day(30)) == .pro)
    }

    @Test("A Trial lasts 14 days: 14 days left on day 0, 1 on day 13, Free from the moment 14 days have passed")
    func trial() {
        #expect(Entitlement.tier(ownsPro: false, trialStartedAt: start, now: start) == .trial(daysLeft: 14))
        #expect(Entitlement.tier(ownsPro: false, trialStartedAt: start, now: day(13)) == .trial(daysLeft: 1))
        #expect(Entitlement.tier(ownsPro: false, trialStartedAt: start, now: day(13.9)) == .trial(daysLeft: 1))
        #expect(Entitlement.tier(ownsPro: false, trialStartedAt: start, now: day(14)) == .free)
        #expect(Entitlement.tier(ownsPro: false, trialStartedAt: start, now: day(40)) == .free)
    }

    @Test("No Pro and no Trial is Free")
    func free() {
        #expect(Entitlement.tier(ownsPro: false, trialStartedAt: nil, now: start) == .free)
    }

    @Test("Pro and the Trial record every USB Channel and run every extra")
    func fullAllowance() {
        for tier in [Tier.pro, .trial(daysLeft: 3)] {
            let allowance = Entitlement.allowance(for: tier, channelCount: 18, freeChoice: [])
            #expect(allowance.recordedChannels == Set(1...18))
            #expect(allowance.showReport && allowance.reaperExport && allowance.namingByHand)
        }
    }

    @Test("Free records the 2 USB Channels the operator chose, and no extras")
    func freeAllowance() {
        let allowance = Entitlement.allowance(for: .free, channelCount: 18, freeChoice: [7, 3])
        #expect(allowance.recordedChannels == [3, 7])
        #expect(!allowance.showReport && !allowance.reaperExport && !allowance.namingByHand)
    }

    @Test("Free always records exactly 2 when there are 2: none chosen means the first 2; extra or out-of-range picks are dropped; gaps are filled from the lowest channels")
    func freeChoiceIsCleaned() {
        func recorded(_ choice: [Int], of count: Int = 18) -> Set<Int> {
            Entitlement.allowance(for: .free, channelCount: count, freeChoice: choice).recordedChannels
        }
        #expect(recorded([]) == [1, 2])
        #expect(recorded([5]) == [1, 5])
        #expect(recorded([4, 9, 12]) == [4, 9], "only the first 2 picks")
        #expect(recorded([30, 9]) == [1, 9], "30 doesn't exist on an 18-channel input")
        #expect(recorded([2, 2]) == [1, 2], "a channel counts once")
        #expect(recorded([], of: 1) == [1], "a 1-channel input records its only channel")
        #expect(recorded([], of: 0) == [])
    }
}
