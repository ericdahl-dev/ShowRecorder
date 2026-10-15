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
            let allowance = Entitlement.allowance(for: tier, channelCount: 18)
            #expect(allowance.recordedChannels == Set(1...18))
            #expect(allowance.showReport && allowance.reaperExport && allowance.namingByHand)
        }
    }

    @Test("Free records every USB Channel, but no extras (Eric, 2026-10-15, #705)")
    func freeAllowance() {
        let allowance = Entitlement.allowance(for: .free, channelCount: 18)
        #expect(allowance.recordedChannels == Set(1...18))
        #expect(!allowance.showReport && !allowance.reaperExport && !allowance.namingByHand)
        #expect(Entitlement.allowance(for: .free, channelCount: 0).recordedChannels.isEmpty)
    }

    @Test("Free gets no Drive Copy, 3 Markers per Take, generic names (no Mixer Link names or colors), no auto-gain and no clip protection; Pro and the Trial get all of them (Eric, 2026-10-15, #705)")
    func paidGates() {
        let free = Entitlement.allowance(for: .free, channelCount: 18)
        #expect(!free.driveCopy)
        #expect(free.markerLimit == 3)
        #expect(!free.mixerLinkNames)
        #expect(!free.autoGain)
        #expect(!free.clipProtection)
        for tier in [Tier.pro, .trial(daysLeft: 3)] {
            let full = Entitlement.allowance(for: tier, channelCount: 18)
            #expect(full.driveCopy && full.mixerLinkNames && full.autoGain && full.clipProtection)
            #expect(full.markerLimit == nil)
        }
    }

    @Test("Settings names the tier in the glossary's words: Free, 14-day Trial with the days left, Pro")
    func titles() {
        #expect(Tier.free.title == "Free")
        #expect(Tier.trial(daysLeft: 9).title == "14-day Trial, 9 days left")
        #expect(Tier.trial(daysLeft: 1).title == "14-day Trial, 1 day left")
        #expect(Tier.pro.title == "Pro")
    }

    @Test("At record press: while Pro isn't offered nothing is limited (TestFlight records every USB Channel); once offered, the tier decides (#60)")
    func atPress() throws {
        #expect(License(proOffered: false, tier: .free, trialStarted: false).allowance(channelCount: 18) == nil)
        let free = try #require(License(proOffered: true, tier: .free, trialStarted: false).allowance(channelCount: 18))
        #expect(free.recordedChannels == Set(1...18))
        let trial = try #require(License(proOffered: true, tier: .trial(daysLeft: 3), trialStarted: true).allowance(channelCount: 18))
        #expect(trial.recordedChannels.count == 18)
    }
}
