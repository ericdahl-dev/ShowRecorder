import MixerLink

/// One gain move or undo on the Mixer at a time, in the order asked (#554): each Mix Hold plan reads the Mixer, ramps
/// and writes, so two at once could both rewrite a setting they both compensate (a keyed threshold) and lose one move.
@MainActor
final class MixerQueue {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    /// Runs `body` once the Mixer is free, and frees it after, even when `body` throws.
    func run<T>(_ body: () async throws(MixerLinkProblem) -> T) async throws(MixerLinkProblem) -> T {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
        defer {
            if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
        }
        return try await body()
    }
}
