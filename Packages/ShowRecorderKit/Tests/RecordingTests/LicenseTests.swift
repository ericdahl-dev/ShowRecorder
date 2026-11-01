import Foundation
@testable import Recording
import Testing

/// The License answers every Pro, Free and Trial question in one place (#439, ADR 0004).
@Suite("License")
struct LicenseTests {
    static let free = License(proOffered: true, tier: .free, trialStarted: true)
    static let trial = License(proOffered: true, tier: .trial(daysLeft: 3), trialStarted: true)
    static let pro = License(proOffered: true, tier: .pro, trialStarted: false)
    static let unknown = License(proOffered: true, tier: nil, trialStarted: false)
    static let notOffered = License(proOffered: false, tier: .free, trialStarted: false)

    @Test("Free limits: every USB Channel but no extras, 48 kHz at most, Templates listed but not usable (#705)")
    func freeLimits() throws {
        let license = Self.free
        #expect(license.limits)
        let allowance = try #require(license.allowance(channelCount: 18))
        #expect(allowance.recordedChannels == Set(1...18))
        #expect(!allowance.showReport && !allowance.reaperExport && !allowance.namingByHand)
        #expect(license.capsAt48k)
        #expect(license.templateAccess(isRecording: false) == .proOnly)
        #expect(!license.allowsProExtras)
    }

    @Test("The Trial and Pro limit nothing")
    func trialAndProLimitNothing() throws {
        for license in [Self.trial, Self.pro] {
            #expect(!license.limits)
            #expect(try #require(license.allowance(channelCount: 18)).recordedChannels.count == 18)
            #expect(!license.capsAt48k)
            #expect(license.templateAccess(isRecording: false) == .usable)
            #expect(license.allowsProExtras)
        }
    }

    @Test("Before the App Store answers, and while Pro isn't offered, nothing is limited (#316, #60)")
    func unknownAndNotOfferedLimitNothing() {
        for license in [Self.unknown, Self.notOffered] {
            #expect(!license.limits)
            #expect(license.allowance(channelCount: 18) == nil)
            #expect(!license.capsAt48k)
            #expect(license.templateAccess(isRecording: false) == .usable)
            #expect(license.allowsProExtras)
        }
    }

    @Test("A Template is never used during a Take, whatever the tier")
    func noTemplateDuringTake() {
        #expect(Self.pro.templateAccess(isRecording: true) == .takeRunning)
        #expect(Self.free.templateAccess(isRecording: true) == .takeRunning)
    }

    @Test("Settings names the plan, and says it's checking until the App Store answers")
    func planTitle() {
        #expect(Self.free.planTitle == "Free")
        #expect(Self.pro.planTitle == "Pro")
        #expect(Self.trial.planTitle == "14-day Trial, 3 days left")
        #expect(Self.unknown.planTitle == "Checking with the App Store…")
    }

    @Test("The days-left chip shows only in a known Trial, and only once Pro is offered")
    func chip() {
        #expect(Self.trial.chip?.shortText == "Trial · 3 days")
        #expect(Self.free.chip == nil && Self.pro.chip == nil && Self.unknown.chip == nil)
        #expect(License(proOffered: false, tier: .trial(daysLeft: 3), trialStarted: true).chip == nil)
    }

    @Test("The Trial is offered once, on Free before any Trial, with Pro's price known, never during a Take or over another sheet")
    func trialOffer() {
        let fresh = License(proOffered: true, tier: .free, trialStarted: false)
        #expect(fresh.offersTrial(alreadyOffered: false, recording: false, proPrice: "$19.99", anotherSheetOpen: false))
        #expect(!fresh.offersTrial(alreadyOffered: true, recording: false, proPrice: "$19.99", anotherSheetOpen: false))
        #expect(!fresh.offersTrial(alreadyOffered: false, recording: true, proPrice: "$19.99", anotherSheetOpen: false))
        #expect(!fresh.offersTrial(alreadyOffered: false, recording: false, proPrice: nil, anotherSheetOpen: false))
        #expect(!fresh.offersTrial(alreadyOffered: false, recording: false, proPrice: "$19.99", anotherSheetOpen: true), "#357")
        #expect(!Self.free.offersTrial(alreadyOffered: false, recording: false, proPrice: "$19.99", anotherSheetOpen: false), "the Trial has run")
        #expect(!Self.trial.offersTrial(alreadyOffered: false, recording: false, proPrice: "$19.99", anotherSheetOpen: false))
        #expect(!Self.pro.offersTrial(alreadyOffered: false, recording: false, proPrice: "$19.99", anotherSheetOpen: false))
        #expect(!Self.unknown.offersTrial(alreadyOffered: false, recording: false, proPrice: "$19.99", anotherSheetOpen: false), "wait for the App Store")
        #expect(!License(proOffered: false, tier: .free, trialStarted: false)
            .offersTrial(alreadyOffered: false, recording: false, proPrice: "$19.99", anotherSheetOpen: false))
    }
}

/// What the App Store has said, turned into a License without StoreKit (#439, #316).
@Suite("Pro status")
struct ProStatusTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let pro = OwnedPurchase(productID: ProPurchases.proProductID, purchaseDate: now)
    static let trial = OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: now)

    @Test("A fresh install doesn't know the tier until the App Store answers")
    func freshInstall() {
        var status = ProStatus(lastKnown: nil)
        #expect(status.license(proOffered: true, now: Self.now).tier == nil)
        let changed = status.appStoreAnswered([Self.pro], now: Self.now)
        #expect(changed, "the known tier changed")
        #expect(status.license(proOffered: true, now: Self.now).tier == .pro)
    }

    @Test("A later launch knows the last tier at once, and only a real change is reported")
    func lastKnown() {
        var status = ProStatus(lastKnown: ProPurchases(owned: [Self.trial]))
        #expect(status.license(proOffered: true, now: Self.now).tier == .trial(daysLeft: 14))
        let same = status.appStoreAnswered([Self.trial], now: Self.now)
        #expect(!same, "same tier: nothing to get ready again")
        let changed = status.appStoreAnswered([Self.trial, Self.pro], now: Self.now)
        #expect(changed)
        #expect(status.purchases.ownsPro)
    }

    @Test("A refund takes Pro away")
    func refund() {
        var status = ProStatus(lastKnown: ProPurchases(owned: [Self.pro]))
        let refunded = OwnedPurchase(productID: ProPurchases.proProductID, purchaseDate: Self.now, revocationDate: Self.now)
        let changed = status.appStoreAnswered([refunded], now: Self.now)
        #expect(changed)
        #expect(status.license(proOffered: true, now: Self.now).tier == .free)
    }

    @Test("The License carries whether a Trial was ever started")
    func trialStarted() {
        let status = ProStatus(lastKnown: ProPurchases(owned: [Self.trial]))
        let later = Self.now.addingTimeInterval(30 * 86_400)
        let license = status.license(proOffered: true, now: later)
        #expect(license.tier == .free && license.trialStarted)
    }

    @Test("Auto-gain runs between Takes, so the tier now decides it: not on Free; on Pro, the Trial, with Pro not offered or the tier unknown (#705)")
    func autoGain() {
        func license(_ tier: Tier?, offered: Bool = true) -> License {
            License(proOffered: offered, tier: tier, trialStarted: false)
        }
        #expect(!license(.free).allowsAutoGain)
        #expect(license(.pro).allowsAutoGain)
        #expect(license(.trial(daysLeft: 2)).allowsAutoGain)
        #expect(license(.free, offered: false).allowsAutoGain)
        #expect(license(nil).allowsAutoGain)
    }

    @Test("The Drive is Pro: not on Free; on Pro, the Trial, with Pro not offered or the tier unknown (#705)")
    func drive() {
        func license(_ tier: Tier?, offered: Bool = true) -> License { License(proOffered: offered, tier: tier, trialStarted: false) }
        #expect(!license(.free).allowsDrive)
        #expect(license(.pro).allowsDrive && license(.trial(daysLeft: 2)).allowsDrive)
        #expect(license(.free, offered: false).allowsDrive && license(nil).allowsDrive)
    }
}
