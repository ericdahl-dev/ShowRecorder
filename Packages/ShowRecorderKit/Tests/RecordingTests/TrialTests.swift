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
    func expiresMidTake() async throws {
        let purchases = ProPurchases(owned: [OwnedPurchase(productID: ProPurchases.trialProductID, purchaseDate: started)])
        var clock = day(13.99)
        let recorder = Recorder(deviceFolder: root, now: { clock })
        let audio = FakeAudioDevice(inputChannelCount: 4)
        try recorder.arm(audio)

        // Record is pressed a few minutes before the Trial runs out.
        let allowance = Entitlement.allowance(for: purchases.tier(now: clock), channelCount: 4)
        try recorder.startTake(allowance: allowance)
        audio.deliver((0..<4).map { _ in Array(repeating: 0.2, count: 480) })
        clock = day(14.5)
        #expect(purchases.tier(now: clock) == .free)
        audio.deliver((0..<4).map { _ in Array(repeating: 0.2, count: 480) })
        try await recorder.stopTake()

        let take = try #require(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .first { !$0.lastPathComponent.hasPrefix(".") }?.appending(path: "Take 01"))
        let stems = try FileManager.default.contentsOfDirectory(atPath: take.path).filter { $0.hasSuffix(".wav") }.sorted()
        #expect(stems == ["01 USB 01.wav", "02 USB 02.wav", "03 USB 03.wav", "04 USB 04.wav"])
        for stem in stems {
            #expect(try ParsedStem(contentsOf: take.appending(path: stem)).samples.count == 960)
        }
    }

    @Test("Before it starts, the Trial says how long it lasts, what Free keeps afterward and what Pro costs (Guideline 3.1.1)")
    func disclosure() {
        let disclosure = TrialDisclosure(proPrice: "$19.99")
        let text = ([disclosure.title] + disclosure.lines).joined(separator: "\n")
        #expect(disclosure.title == "14-day Trial")
        #expect(text.contains("14 days"))
        #expect(text.contains("at no cost"))
        #expect(text.contains("Free still records every USB Channel"), "what Free keeps (#705)")
        #expect(!text.contains("2 USB Channels"))
        #expect(text.contains("a Drive"))
        #expect(text.contains("Show report"))
        #expect(text.contains("$19.99"))
        #expect(text.contains("one-time"))
        #expect(text.contains("never stops"))
    }

    @Test("The Trial names everything Pro adds, as the paywall does (ADR 0004 launch scope)")
    func disclosureNamesEveryProFeature() {
        let first = TrialDisclosure(proPrice: "$19.99").lines[0]
        for feature in ["names and colors from the Mixer", "channel names you type", "a second Copy on a Drive, with Repair", "unlimited Markers",
                        "the Show report", "Reaper project", "96 kHz", "Templates"] {
            #expect(first.contains(feature), "\(feature)")
        }
    }

    @Test("Tapping the Trial chip explains it: what it includes, when it ends, what Free keeps after, and the Pro price (#743)")
    func statusNotice() {
        let notice = TrialStatusNotice(daysLeft: 12, endsOn: "October 27", proPrice: "$19.99")
        let text = notice.lines.joined(separator: "\n")
        #expect(notice.title == "14-day Trial")
        #expect(text.contains("Everything Pro does"), "what it includes")
        #expect(text.contains("Show report") && text.contains("a Drive"))
        #expect(text.contains("Ends October 27, in 12 days."), "when it ends")
        #expect(text.contains("Free still records every USB Channel"), "what Free keeps (#705)")
        #expect(text.contains("up to 3 Markers per Take"))
        #expect(text.contains("never stops"))
        #expect(text.contains("$19.99") && text.contains("one-time"))
        #expect(notice.lines.contains { $0.hasPrefix("Pro is a one-time purchase of $19.99") }, "full Pro without a pack (#968)")
        #expect(!text.contains("—"))
    }

    @Test("The Trial's end is 14 days after it started, and the tier agrees on the last day (#743)")
    func trialEnd() {
        let end = Entitlement.trialEnd(startedAt: started)
        #expect(end == day(14))
        #expect(Entitlement.tier(ownsPro: false, trialStartedAt: started, now: end.addingTimeInterval(-1)) == .trial(daysLeft: 1))
        #expect(Entitlement.tier(ownsPro: false, trialStartedAt: started, now: end) == .free)
    }

    @Test("A pack owner's notice names the upgrade and its price, not full Pro's (#968)")
    func statusNoticeForAPackOwner() {
        let lines = TrialStatusNotice(daysLeft: 5, endsOn: "October 31", proPrice: "$12.00", upgrade: true).lines
        #expect(lines.contains { $0.hasPrefix("The upgrade to Pro is a one-time purchase of $12.00") })
        #expect(!lines.contains { $0.hasPrefix("Pro is") }, "no full Pro price line")
    }

    @Test("A pack owner's disclosure before the Trial names the upgrade and its price, not full Pro's (#972)")
    func disclosureForAPackOwner() {
        let lines = TrialDisclosure(proPrice: "$12.00", upgrade: true).lines
        #expect(lines.contains { $0.hasPrefix("The upgrade to Pro is a one-time purchase of $12.00, shared with your family. Nothing is charged when the Trial ends.") })
        #expect(!lines.contains { $0.hasPrefix("Pro is") }, "no full Pro price line")
    }

    @Test("Without a pack the disclosure is word for word as before, and the other lines are the same for a pack owner (#972)")
    func disclosureWithoutAPack() {
        let plain = TrialDisclosure(proPrice: "$19.99").lines
        #expect(plain[2] == "Pro is a one-time purchase of $19.99, shared with your family. Nothing is charged when the Trial ends.")
        let owner = TrialDisclosure(proPrice: "$12.00", upgrade: true).lines
        #expect(owner.count == plain.count)
        #expect(owner[0] == plain[0] && owner[1] == plain[1] && owner[3] == plain[3])
    }

    @Test("The Free Marker limit in the notice is the real one")
    func markerLimitFollowsEntitlement() {
        let text = TrialStatusNotice(daysLeft: 3, endsOn: "October 18", proPrice: nil).lines.joined(separator: "\n")
        #expect(text.contains("up to \(Entitlement.freeMarkerLimit) Markers per Take"))
    }

    @Test("The notice says 1 day, and leaves the price out until the App Store has it")
    func statusNoticeEdges() {
        let notice = TrialStatusNotice(daysLeft: 1, endsOn: "October 16", proPrice: nil)
        let text = notice.lines.joined(separator: "\n")
        #expect(text.contains("Ends October 16, in 1 day."))
        #expect(!text.contains("$"))
    }

    @Test("The record screen shows the Trial's days left in a quiet chip, and nothing on Free or Pro")
    func daysLeftChip() {
        let chip = Tier.trial(daysLeft: 11).chip
        #expect(chip?.text == "14-day Trial, 11 days left")
        #expect(chip?.shortText == "Trial · 11 days", "the chip names what the days are (#743)")
        #expect(chip?.state == .neutral)
        #expect(chip?.id == "trial", "so the record screen can open the Trial sheet from it")
        #expect(Tier.trial(daysLeft: 1).chip?.shortText == "Trial · 1 day")
        #expect(Tier.free.chip == nil)
        #expect(Tier.pro.chip == nil)
    }
}
