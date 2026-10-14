import MixerLink

/// One gain move or undo on the Mixer at a time, in the order asked (#554): each Mix Hold plan reads the Mixer, ramps
/// and writes, so two at once could both rewrite a setting they both compensate (a keyed threshold) and lose one move.
@MainActor
public final class MixerQueue {
    /// A whole-Mixer job is under way.
    private var whole = false
    /// The lanes with a job under way.
    private var lanes: Set<AnyHashable> = []
    /// Jobs waiting, in the order asked: each in its lane, or nil for a whole-Mixer job.
    private var waiting: [(lane: AnyHashable?, go: CheckedContinuation<Void, Never>)] = []

    public init() {}

    /// Runs `body` once the Mixer is free, and frees it after, even when `body` throws.
    func run<T>(_ body: () async throws(MixerLinkProblem) -> T) async throws(MixerLinkProblem) -> T {
        try await run(in: nil, body)
    }

    /// Runs `body` in `lane`: jobs in one lane go one at a time, in the order asked; jobs in different lanes run at once.
    func run<T>(lane: some Hashable, _ body: () async throws(MixerLinkProblem) -> T) async throws(MixerLinkProblem) -> T {
        try await run(in: AnyHashable(lane), body)
    }

    private func run<T>(in lane: AnyHashable?, _ body: () async throws(MixerLinkProblem) -> T) async throws(MixerLinkProblem) -> T {
        if canStart(lane, behind: waiting[...]) {
            take(lane)
        } else {
            await withCheckedContinuation { waiting.append((lane, $0)) }
        }
        defer { free(lane) }
        return try await body()
    }

    /// Whether a job in `lane` (nil: the whole Mixer) may start now, with `ahead` asked for before it and still waiting.
    private func canStart(_ lane: AnyHashable?, behind ahead: ArraySlice<(lane: AnyHashable?, go: CheckedContinuation<Void, Never>)>) -> Bool {
        guard !whole else { return false }
        // A whole-Mixer job waits for every lane job under way; one waiting holds every job asked for after it.
        guard let lane else { return lanes.isEmpty && ahead.isEmpty }
        return !lanes.contains(lane) && !ahead.contains { $0.lane == nil || $0.lane == lane }
    }

    /// Marks a job in `lane` under way, before it starts, so no other job takes its place meanwhile.
    private func take(_ lane: AnyHashable?) {
        if let lane { lanes.insert(lane) } else { whole = true }
    }

    /// A job in `lane` is done: starts every waiting job that may start now, in the order asked.
    private func free(_ lane: AnyHashable?) {
        if let lane { lanes.remove(lane) } else { whole = false }
        var index = 0
        while index < waiting.count {
            let job = waiting[index]
            if canStart(job.lane, behind: waiting[..<index]) {
                waiting.remove(at: index)
                take(job.lane)
                job.go.resume()
            } else {
                index += 1
            }
        }
    }
}
