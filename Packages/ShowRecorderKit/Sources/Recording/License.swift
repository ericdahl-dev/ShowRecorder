import Foundation

/// What the operator may do right now (ADR 0004, CONTEXT.md): every Pro, Free and Trial question is answered here,
/// from the tier and whether Pro is offered. It is read from what the App Store last said and never waits on it, and
/// the limits it sets apply only when record is pressed (Show-Safe Promise).
public struct License: Equatable, Sendable {
    /// Whether Pro is offered at all. Off, nothing is limited and nothing about Pro is shown (#60).
    public let proOffered: Bool
    /// Free, Trial or Pro; nil while the App Store hasn't said what's owned, which limits nothing (#316).
    public let tier: Tier?
    /// Whether a 14-day Trial was ever started on this Apple Account, running or not.
    public let trialStarted: Bool

    /// The key that remembers the first-launch Trial offer was made.
    public static let trialOfferedKey = "trialOffered"

    public init(proOffered: Bool, tier: Tier?, trialStarted: Bool) {
        self.proOffered = proOffered
        self.tier = tier
        self.trialStarted = trialStarted
    }

    /// The one rule: Free limits, once Pro is offered and the tier is known.
    public var limits: Bool { proOffered && tier == .free }

    /// What a Take gets when record is pressed; nil (nothing limited) while Pro isn't offered or the tier is unknown.
    public func allowance(channelCount: Int) -> TakeAllowance? {
        guard proOffered, let tier else { return nil }
        return Entitlement.allowance(for: tier, channelCount: channelCount)
    }

    /// Whether the input is opened at 48 kHz at most (#195).
    public var capsAt48k: Bool { limits }

    /// Whether Templates can be used right now.
    public func templateAccess(isRecording: Bool) -> TemplateAccess {
        TemplateAccess(limits: limits, isRecording: isRecording)
    }

    /// Whether the Show report and Reaper project may be written for a Show changed now. A rename still rewrites one
    /// that is already there, so it never shows stale names (#438).
    public var allowsProExtras: Bool { !limits }

    /// Whether auto-gain may run now (#705). It runs between Takes, so the tier now decides, from the same table as a
    /// Take's allowance; nothing is limited while Pro isn't offered or the tier is unknown.
    public var allowsAutoGain: Bool { allowance(channelCount: 0)?.autoGain ?? true }

    /// Whether a Take pressed now would also be written to the Drive (#705), for what the screen says before the press.
    public var allowsDrive: Bool { allowance(channelCount: 0)?.driveCopy ?? true }

    /// How Settings names the plan.
    public var planTitle: String { tier?.title ?? "Checking with the App Store…" }

    /// The record screen's quiet days-left chip during a known Trial; nothing otherwise.
    public var chip: PowerStatus.Chip? { proOffered ? tier?.chip : nil }

    /// Whether the app offers the 14-day Trial on its own: once, at launch, on Free before any Trial, never during a
    /// Take, and never before the App Store has answered.
    /// - Parameters:
    ///   - proPrice: Pro's display price, nil until the App Store has it; the offer must name it (Guideline 3.1.1).
    ///   - anotherSheetOpen: Settings, the paywall or another sheet is up. The offer waits: presenting over them closed both (#357).
    public func offersTrial(alreadyOffered: Bool, recording: Bool, proPrice: String?, anotherSheetOpen: Bool) -> Bool {
        proOffered && tier == .free && !trialStarted && !alreadyOffered && !recording && !anotherSheetOpen && proPrice != nil
    }
}

/// What the App Store has said about Pro and the Trial, without StoreKit: the last known purchases on this device
/// until the App Store answers this launch (#316), then its answer.
public struct ProStatus: Equatable, Sendable {
    public private(set) var purchases: ProPurchases
    /// Whether the tier is known: the App Store has answered this launch, or an earlier one did.
    public private(set) var tierKnown: Bool

    /// - Parameter lastKnown: what was owned the last time the App Store was asked; nil on a fresh install.
    public init(lastKnown: ProPurchases?) {
        purchases = lastKnown ?? ProPurchases(owned: [])
        tierKnown = lastKnown != nil
    }

    /// Takes the App Store's answer. Returns whether the known tier or the owned mixer packs changed (#705), so the
    /// recorder can re-Arm between Takes.
    @discardableResult
    public mutating func appStoreAnswered(_ owned: [OwnedPurchase], now: Date) -> Bool {
        let before = knownTier(now: now)
        let packsBefore = purchases.ownedPacks
        purchases = ProPurchases(owned: owned)
        tierKnown = true
        return knownTier(now: now) != before || purchases.ownedPacks != packsBefore
    }

    public func license(proOffered: Bool, now: Date) -> License {
        License(proOffered: proOffered, tier: knownTier(now: now), trialStarted: purchases.trialStartedAt != nil)
    }

    private func knownTier(now: Date) -> Tier? { tierKnown ? purchases.tier(now: now) : nil }
}
