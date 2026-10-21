import Foundation
import MixerLink
@testable import Recording
import Testing

/// What the paywall offers with mixer packs (#705, ADR 0004): the Armed family's pack first with Pro beside it, Pro
/// alone for a generic input, and only the upgrade for someone who already has a pack (a second pack is hidden, Eric).
@Suite("Pack offer")
struct PackOfferTests {
    @Test("An X Air or X32 as the Armed input: its pack first, then Pro (#705)")
    func packFirst() {
        #expect(PackOffer.items(ownsPro: false, armedFamily: .xAir, ownedPacks: [], boughtPacks: [], packsOffered: true) == [.pack(.xAir), .pro])
        #expect(PackOffer.items(ownsPro: false, armedFamily: .x32, ownedPacks: [], boughtPacks: [], packsOffered: true) == [.pack(.x32), .pro])
    }

    @Test("The Demo signal, where it counts as an X Air, is offered the X Air pack first (#705)")
    func demoGetsXAirPack() {
        let family = MixerFamily.armed(interfaceName: "Demo signal", isDemo: true, demoCounts: true)
        #expect(PackOffer.items(ownsPro: false, armedFamily: family, ownedPacks: [], boughtPacks: [], packsOffered: true) == [.pack(.xAir), .pro])
    }

    @Test("A generic input (no mixer family) is offered Pro only: there is no pack for it (#705)")
    func genericGetsPro() {
        #expect(PackOffer.items(ownsPro: false, armedFamily: nil, ownedPacks: [], boughtPacks: [], packsOffered: true) == [.pro])
    }

    @Test("Someone with a pack is offered only the upgrade to Pro, whatever is Armed: a second pack is hidden (Eric, #705)")
    func packOwnerGetsUpgrade() {
        #expect(PackOffer.items(ownsPro: false, armedFamily: .xAir, ownedPacks: [.x32], boughtPacks: [.x32], packsOffered: true) == [.upgrade])
        #expect(PackOffer.items(ownsPro: false, armedFamily: .x32, ownedPacks: [.x32], boughtPacks: [.x32], packsOffered: true) == [.upgrade])
        #expect(PackOffer.items(ownsPro: false, armedFamily: nil, ownedPacks: [.xAir], boughtPacks: [.xAir], packsOffered: true) == [.upgrade])
    }

    @Test("A pack shared through Family Sharing doesn't earn the upgrade: that person is offered full Pro (Eric, #705)")
    func sharedPackGetsPro() {
        #expect(PackOffer.items(ownsPro: false, armedFamily: .x32, ownedPacks: [.xAir], boughtPacks: [], packsOffered: true) == [.pro])
    }

    @Test("\"Launch price\" shows only while Pro's live price is its launch price in that currency (Eric, #908)")
    func launchPrice() {
        #expect(PriceStage.label(proPrice: Decimal(string: "4.99"), currencyCode: "USD") == "Launch price")
        #expect(PriceStage.label(proPrice: Decimal(string: "5.99"), currencyCode: "EUR") == "Launch price")
        #expect(PriceStage.label(proPrice: Decimal(string: "800"), currencyCode: "JPY") == "Launch price")
        #expect(PriceStage.label(proPrice: Decimal(string: "9.99"), currencyCode: "USD") == nil)
        #expect(PriceStage.label(proPrice: Decimal(string: "19.99"), currencyCode: "USD") == nil)
    }

    @Test("A StoreKit price with float residue or trailing zeros still matches its launch price (#908)")
    func launchPriceRounding() {
        #expect(PriceStage.label(proPrice: Decimal(4.99), currencyCode: "USD") == "Launch price")
        #expect(PriceStage.label(proPrice: Decimal(string: "29.90"), currencyCode: "BRL") == "Launch price")
        #expect(PriceStage.label(proPrice: Decimal(4), currencyCode: "CHF") == "Launch price")
    }

    @Test("No label while Pro's price is loading, or in a currency without a known launch price (#908)")
    func launchPriceUnknown() {
        #expect(PriceStage.label(proPrice: nil, currencyCode: "USD") == nil)
        #expect(PriceStage.label(proPrice: Decimal(string: "4.99"), currencyCode: nil) == nil)
        #expect(PriceStage.label(proPrice: Decimal(string: "4.99"), currencyCode: "XXX") == nil)
    }

    @Test("The paywall headline: a running Trial's line wins, with the pack or upgrade offered below; else the pack, the upgrade, then the moment (Eric, #705)")
    func paywallHeadline() {
        let trial = Paywall(moment: .trialEndingSoon(daysLeft: 2), proPrice: nil)
        #expect(PackOffer.paywallHeadline(items: [.upgrade], mixerModel: nil, moment: .trialEndingSoon(daysLeft: 2), paywall: trial)
            == "Your 14-day Trial ends in 2 days", "a pack owner in the Trial")
        #expect(PackOffer.paywallHeadline(items: [.pack(.xAir), .pro], mixerModel: "XR18", moment: .trialEndingSoon(daysLeft: 2), paywall: trial)
            == "Your 14-day Trial ends in 2 days")
        let plain = Paywall(moment: nil, proPrice: nil)
        #expect(PackOffer.paywallHeadline(items: [.upgrade], mixerModel: nil, moment: nil, paywall: plain) == "Pro on every audio interface")
        #expect(PackOffer.paywallHeadline(items: [.pack(.xAir), .pro], mixerModel: "XR18", moment: nil, paywall: plain) == "Pro for your XR18")
        let names = Paywall(moment: .genericNames, proPrice: nil)
        #expect(PackOffer.paywallHeadline(items: [.upgrade], mixerModel: nil, moment: .genericNames, paywall: names)
            == "Pro on every audio interface", "only the Trial's line wins over the offer")
        #expect(PackOffer.paywallHeadline(items: [.pro], mixerModel: nil, moment: .genericNames, paywall: names) == names.headline)
    }

    @Test("Pro owned: nothing to offer (#705)")
    func proOwned() {
        #expect(PackOffer.items(ownsPro: true, armedFamily: .xAir, ownedPacks: [.xAir], boughtPacks: [.xAir], packsOffered: true).isEmpty)
    }

    @Test("Where packs aren't offered yet, the paywall is Pro only, as before (#705)")
    func packsNotOffered() {
        #expect(PackOffer.items(ownsPro: false, armedFamily: .xAir, ownedPacks: [], boughtPacks: [], packsOffered: false) == [.pro])
    }

    @Test("The pack headline names the Mixer: its model when linked, else the family (#705)")
    func headline() {
        #expect(PackOffer.headline(family: .xAir, mixerModel: "XR18") == "Pro for your XR18")
        #expect(PackOffer.headline(family: .x32, mixerModel: nil) == "Pro for your X32")
        #expect(PackOffer.headline(family: .xAir, mixerModel: " ") == "Pro for your X Air")
        #expect(PackOffer.headline(family: .xAir, mixerModel: "XR18\n") == "Pro for your XR18")
    }

    @Test("Packs are offered in Debug builds only for now: never TestFlight or the App Store (#705)")
    func availability() {
        #expect(PackAvailability.isAvailable(isDebugBuild: true))
        #expect(!PackAvailability.isAvailable(isDebugBuild: false))
    }

    @Test("The license honors a pack on the Armed family: Pro on an X Air with the X Air pack, Free on an X32 (#705)")
    func licenseWithFamily() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let pack = OwnedPurchase(productID: ProPurchases.packProductIDs[.xAir]!, purchaseDate: now)
        var status = ProStatus(lastKnown: nil)
        _ = status.appStoreAnswered([pack], now: now)
        #expect(status.license(proOffered: true, armedFamily: .xAir, now: now).tier == .pro)
        #expect(status.license(proOffered: true, armedFamily: .x32, now: now).tier == .free)
        #expect(status.license(proOffered: true, now: now).tier == .free, "no family: as before")
    }

    @Test("Settings names a pack owner's plan after the pack, unless Pro or a running Trial says more (#705)")
    func planTitle() {
        #expect(PackOffer.planTitle(tier: .free, ownsPro: false, ownedPacks: [.xAir]) == "X Air pack")
        #expect(PackOffer.planTitle(tier: .pro, ownsPro: false, ownedPacks: [.x32]) == "X32 pack", "Pro on its own family, still a pack")
        #expect(PackOffer.planTitle(tier: .pro, ownsPro: true, ownedPacks: [.xAir]) == "Pro")
        #expect(PackOffer.planTitle(tier: .trial(daysLeft: 3), ownsPro: false, ownedPacks: [.xAir]) == "14-day Trial, 3 days left")
        #expect(PackOffer.planTitle(tier: .free, ownsPro: false, ownedPacks: []) == "Free")
        #expect(PackOffer.planTitle(tier: nil, ownsPro: false, ownedPacks: []) == "Checking with the App Store…")
    }

    @Test("Restore says what came back: Pro, a pack, or nothing (Eric, #705)")
    func restoreNote() {
        #expect(PackOffer.restoreNote(ownsPro: true, ownedPacks: [.xAir]) == nil)
        #expect(PackOffer.restoreNote(ownsPro: false, ownedPacks: [.xAir]) == "Restored: X Air pack")
        #expect(PackOffer.restoreNote(ownsPro: false, ownedPacks: []) == "No purchase found for this Apple Account.")
    }

    @Test("The pack offer says it covers one family, naming the family's models (#705)")
    func packFootnote() {
        #expect(MixerFamily.xAir.models == ["XR18", "MR18"])
        #expect(MixerFamily.x32.models == ["X32", "M32"])
        #expect(PackOffer.packFootnote(family: .xAir) == "The X Air pack is Pro while an XR18 or MR18 is the audio interface. Pro covers every one.")
        #expect(PackOffer.packFootnote(family: .x32) == "The X32 pack is Pro while an X32 or M32 is the audio interface. Pro covers every one.")
    }

    @Test("A pack owner's Settings footer is about their pack, not Free; only a bought pack is offered the upgrade (#705)")
    func ownerFooter() {
        #expect(PackOffer.ownerFooter(ownedPacks: [], boughtPacks: []) == nil)
        #expect(PackOffer.ownerFooter(ownedPacks: [.xAir], boughtPacks: [.xAir]) == "Your X Air pack is Pro while an XR18 or MR18 is the audio interface. Upgrade to Pro for every one.")
        #expect(PackOffer.ownerFooter(ownedPacks: [.xAir], boughtPacks: []) == "Your X Air pack is Pro while an XR18 or MR18 is the audio interface. Pro covers every one.")
        #expect(PackOffer.ownerFooter(ownedPacks: [.xAir, .x32], boughtPacks: [.x32]) == "Your X32 pack is Pro while an X32 or M32 is the audio interface. Upgrade to Pro for every one.",
                "a bought pack is named before a shared one: it's the one the upgrade rests on")
    }

    @Test("The upgrade-only paywall has its own headline (#705)")
    func upgradeHeadline() {
        #expect(PackOffer.upgradeHeadline(items: [.upgrade]) == "Pro on every audio interface")
        #expect(PackOffer.upgradeHeadline(items: [.pro]) == nil)
        #expect(PackOffer.upgradeHeadline(items: [.pack(.xAir), .pro]) == nil)
    }
}
