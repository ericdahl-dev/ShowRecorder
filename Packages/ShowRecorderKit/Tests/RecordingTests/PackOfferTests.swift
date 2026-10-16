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

    @Test("At the Launch stage the paywall says \"Launch price\"; at full price it says nothing (Eric, #705)")
    func launchPrice() {
        #expect(PriceStage.current == .launch)
        #expect(PriceStage.launch.label == "Launch price")
        #expect(PriceStage.step2.label == nil)
        #expect(PriceStage.full.label == nil)
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
        #expect(PackOffer.restoreNote(ownsPro: false, ownedPacks: []) == "No Pro purchase found for this Apple Account.")
    }
}
