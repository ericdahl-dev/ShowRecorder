import AudioIO
import Destinations
import Foundation
@testable import Recording
import Testing

/// The 14-day Trial (ADR 0004): everything Pro does, judged when record is pressed (Show-Safe Promise).
@MainActor
@Suite("Trial")
struct TrialTests {
    let root: URL
    let started = Date(timeIntervalSince1970: 1_800_000_000)
    func day(_ n: Double) -> Date { started.addingTimeInterval(n * 86_400) }

    init() {
        root = FileManager.default.temporaryDirectory.appending(path: "TrialTests-\(UUID().uuidString)")
    }

    @Test("A Trial that runs out during a Take records to the end: every USB Channel, the whole Take")
    func expiresMidTake() throws {
        let purchases = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: started)])
        var clock = day(13.99)
        let recorder = Recorder(deviceFolder: root, now: { clock })
        let audio = FakeAudioDevice(inputChannelCount: 4)
        try recorder.arm(audio)

        // Record is pressed a few minutes before the Trial runs out.
        let allowance = Entitlement.allowance(for: purchases.tier(now: clock), channelCount: 4, freeChoice: [1, 2])
        try recorder.startTake(allowance: allowance)
        audio.deliver((0..<4).map { _ in Array(repeating: 0.2, count: 480) })
        clock = day(14.5)
        #expect(purchases.tier(now: clock) == .free)
        audio.deliver((0..<4).map { _ in Array(repeating: 0.2, count: 480) })
        try recorder.stopTake()

        let take = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .first { !$0.lastPathComponent.hasPrefix(".") }?.appending(path: "Take 01"))
        let stems = try FileManager.default.contentsOfDirectory(atPath: take.path).filter { $0.hasSuffix(".wav") }.sorted()
        #expect(stems == ["01 USB 01.wav", "02 USB 02.wav", "03 USB 03.wav", "04 USB 04.wav"])
        for stem in stems {
            #expect(try StemFile(contentsOf: take.appending(path: stem)).samples.count == 960)
        }
    }

    @Test("Before it starts, the Trial says how long it lasts, what Free keeps afterward and what Pro costs (Guideline 3.1.1)")
    func disclosure() {
        let disclosure = TrialDisclosure(proPrice: "$19.99")
        let text = ([disclosure.title] + disclosure.lines).joined(separator: "\n")
        #expect(disclosure.title == "14-day Trial")
        #expect(text.contains("14 days"))
        #expect(text.contains("at no cost"))
        #expect(text.contains("2 USB Channels"))
        #expect(text.contains("Show report"))
        #expect(text.contains("$19.99"))
        #expect(text.contains("one-time"))
        #expect(text.contains("never stops"))
    }

    @Test("The Trial is offered once, at launch: not again, not during a Take, not once a Trial or Pro is owned, not without a price")
    func offer() {
        let none = ProPurchases(owned: [])
        let trial = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: started)])
        let pro = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.proProductID, purchaseDate: started)])
        #expect(TrialOffer.shouldOffer(purchases: none, alreadyOffered: false, recording: false, proPrice: "$19.99"))
        #expect(!TrialOffer.shouldOffer(purchases: none, alreadyOffered: true, recording: false, proPrice: "$19.99"))
        #expect(!TrialOffer.shouldOffer(purchases: none, alreadyOffered: false, recording: true, proPrice: "$19.99"))
        #expect(!TrialOffer.shouldOffer(purchases: trial, alreadyOffered: false, recording: false, proPrice: "$19.99"))
        #expect(!TrialOffer.shouldOffer(purchases: pro, alreadyOffered: false, recording: false, proPrice: "$19.99"))
        #expect(!TrialOffer.shouldOffer(purchases: none, alreadyOffered: false, recording: false, proPrice: nil))
        #expect(!TrialOffer.shouldOffer(purchases: none, alreadyOffered: false, recording: false, proPrice: "$19.99", anotherSheetOpen: true),
                "never over Settings or the paywall: presenting over them closed both (#357)")
    }

    @Test("The record screen shows the Trial's days left in a quiet chip, and nothing on Free or Pro")
    func daysLeftChip() {
        let chip = Tier.trial(daysLeft: 11).chip
        #expect(chip?.text == "14-day Trial, 11 days left")
        #expect(chip?.shortText == "11 days")
        #expect(chip?.state == .neutral)
        #expect(Tier.trial(daysLeft: 1).chip?.shortText == "1 day")
        #expect(Tier.free.chip == nil)
        #expect(Tier.pro.chip == nil)
    }
}
