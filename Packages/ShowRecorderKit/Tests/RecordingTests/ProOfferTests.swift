import AudioIO
import Foundation
@testable import Recording
import Testing

/// When the app offers Pro (#62, ADR 0004): never during a Take, at most once per Show.
@MainActor
@Suite("Pro offer")
struct ProOfferTests {
    @Test("After a Take the Recorder says how many USB Channels were recorded and how many carried signal, recorded or not")
    func takeSignal() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ProOfferTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 4)
        try recorder.arm(audio)
        try recorder.startTake(allowance: TakeAllowance(recordedChannels: [1, 2], showReport: false, reaperExport: false, namingByHand: false))
        // Channels 1, 2 and 4 carry signal; 3 is silent (below -50 dBFS).
        audio.deliver([Array(repeating: 0.3, count: 480), Array(repeating: 0.2, count: 480), Array(repeating: 0.0001, count: 480), Array(repeating: 0.25, count: 480)])
        _ = recorder.takeChannelLevels()
        try recorder.stopTake()
        #expect(recorder.lastTakeSignal?.recorded == 2)
        #expect(recorder.lastTakeSignal?.withSignal == 3)
    }

    @Test("After a Take the Recorder says which USB Channel peaked loudest, and how loud, even below the signal threshold")
    func loudestChannel() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ProOfferTests-\(UUID().uuidString)")
        let recorder = Recorder(deviceFolder: root, now: { RecordingTakeTests.showDay })
        let audio = FakeAudioDevice(inputChannelCount: 3)
        try recorder.arm(audio)
        try recorder.startTake()
        // -60, -54 and silent: none carries signal, but USB 2 was the loudest.
        audio.deliver([Array(repeating: 0.001, count: 480), Array(repeating: 0.002, count: 480), Array(repeating: 0, count: 480)])
        try recorder.stopTake()
        let signal = try #require(recorder.lastTakeSignal)
        #expect(signal.withSignal == 0)
        #expect(signal.loudest?.usbChannel == 2)
        #expect(abs((signal.loudest?.peakDbfs ?? 0) + 53.98) < 0.1)
    }

    func offers() -> ProOffers { ProOffers(defaults: UserDefaults(suiteName: "ProOfferTests-\(UUID().uuidString)")!) }
    let limited = TakeSignal(recorded: 2, withSignal: 5)

    @Test("Nothing is offered while Pro isn't offered, on Pro, or during a Take")
    func never() {
        var o = offers()
        #expect(o.afterTakeStopped(show: "A", signal: limited, license: License(proOffered: false, tier: .free, trialStarted: false), isRecording: false) == nil)
        #expect(o.afterTakeStopped(show: "A", signal: limited, license: License(proOffered: true, tier: .pro, trialStarted: false), isRecording: false) == nil)
        #expect(o.afterTakeStopped(show: "A", signal: limited, license: License(proOffered: true, tier: .free, trialStarted: false), isRecording: true) == nil)
        #expect(o.afterShowEnded(show: "A", takeCount: 3, license: License(proOffered: true, tier: .pro, trialStarted: false)) == nil)
    }

    @Test("A Free Take that left channels with signal unrecorded offers Pro once that Show; one that didn't, doesn't")
    func limitedTake() {
        var o = offers()
        #expect(o.afterTakeStopped(show: "A", signal: TakeSignal(recorded: 2, withSignal: 2), license: License(proOffered: true, tier: .free, trialStarted: false), isRecording: false) == nil)
        #expect(o.afterTakeStopped(show: "A", signal: limited, license: License(proOffered: true, tier: .free, trialStarted: false), isRecording: false) == .limitedTake(recorded: 2, withSignal: 5))
        #expect(o.afterTakeStopped(show: "A", signal: limited, license: License(proOffered: true, tier: .free, trialStarted: false), isRecording: false) == nil, "once per Show")
        #expect(o.afterTakeStopped(show: "B", signal: limited, license: License(proOffered: true, tier: .free, trialStarted: false), isRecording: false) == .limitedTake(recorded: 2, withSignal: 5))
        #expect(o.afterTakeStopped(show: "C", signal: limited, license: License(proOffered: true, tier: .trial(daysLeft: 5), trialStarted: false), isRecording: false) == nil, "the Trial records everything")
    }

    @Test("The first Show with a Take offers Pro when it ends, once ever, on Free or the Trial; an empty Show doesn't count")
    func firstShow() {
        var o = offers()
        #expect(o.afterShowEnded(show: "A", takeCount: 0, license: License(proOffered: true, tier: .trial(daysLeft: 9), trialStarted: false)) == nil)
        #expect(o.afterShowEnded(show: "B", takeCount: 2, license: License(proOffered: true, tier: .trial(daysLeft: 9), trialStarted: false)) == .firstShowEnded)
        #expect(o.afterShowEnded(show: "C", takeCount: 2, license: License(proOffered: true, tier: .free, trialStarted: false)) == nil, "once ever")
    }

    @Test("The Trial's last 2 days get one calm note between Takes, once")
    func trialEnding() {
        var o = offers()
        #expect(o.betweenTakes(show: "A", license: License(proOffered: true, tier: .trial(daysLeft: 3), trialStarted: false), isRecording: false) == nil)
        #expect(o.betweenTakes(show: "A", license: License(proOffered: true, tier: .trial(daysLeft: 2), trialStarted: false), isRecording: true) == nil)
        #expect(o.betweenTakes(show: "A", license: License(proOffered: true, tier: .trial(daysLeft: 2), trialStarted: false), isRecording: false) == .trialEndingSoon(daysLeft: 2))
        #expect(o.betweenTakes(show: "B", license: License(proOffered: true, tier: .trial(daysLeft: 1), trialStarted: false), isRecording: false) == nil, "once")
    }

    @Test("What was offered is kept across launches")
    func persisted() {
        let defaults = UserDefaults(suiteName: "ProOfferTests-\(UUID().uuidString)")!
        var first = ProOffers(defaults: defaults)
        _ = first.afterShowEnded(show: "A", takeCount: 1, license: License(proOffered: true, tier: .free, trialStarted: false))
        _ = first.afterTakeStopped(show: "B", signal: limited, license: License(proOffered: true, tier: .free, trialStarted: false), isRecording: false)
        var again = ProOffers(defaults: defaults)
        #expect(again.afterShowEnded(show: "C", takeCount: 1, license: License(proOffered: true, tier: .free, trialStarted: false)) == nil)
        #expect(again.afterTakeStopped(show: "B", signal: limited, license: License(proOffered: true, tier: .free, trialStarted: false), isRecording: false) == nil)
    }

    @Test("The paywall says why it's here, what Pro adds, the price and the Show-Safe Promise, with no pressure")
    func paywall() {
        let limitedTake = Paywall(moment: .limitedTake(recorded: 2, withSignal: 18), proPrice: "$19.99")
        #expect(limitedTake.headline == "Only 2 of 18 channels were recorded")
        #expect(Paywall(moment: .firstShowEnded, proPrice: "$19.99").headline == "Your first Show is recorded")
        #expect(Paywall(moment: .trialEndingSoon(daysLeft: 1), proPrice: "$19.99").headline == "Your 14-day Trial ends in 1 day")
        #expect(Paywall(moment: nil, proPrice: "$19.99").headline == "ShowRecorder Pro")
        #expect(limitedTake.features == [
            "Names and colors from the Mixer, on the files",
            "Channel names you type, on the files",
            "A second Copy on the Drive",
            "Unlimited Markers",
            "The Show report and Reaper export",
            "96 kHz recording",
            "Templates for each venue",
        ])
        #expect(limitedTake.buyTitle == "Buy Pro, $19.99")
        #expect(limitedTake.promise.contains("never stops"))
        #expect(limitedTake.footnote.contains("one-time") && limitedTake.footnote.contains("family"))
        let text = ([limitedTake.headline, limitedTake.promise, limitedTake.footnote] + limitedTake.features).joined(separator: " ").lowercased()
        for pressure in ["hurry", "today only", "last chance", "limited time", "don't miss"] { #expect(!text.contains(pressure)) }
        #expect(Paywall(moment: nil, proPrice: nil).buyTitle == "Buy Pro")
    }
}
