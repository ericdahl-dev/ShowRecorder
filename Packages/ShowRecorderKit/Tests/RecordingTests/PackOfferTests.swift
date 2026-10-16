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
}
