/// Timing for tests that talk to a fake Mixer over loopback UDP (#462). The fake always answers, so a generous reply
/// timeout costs nothing when the Mac is idle and stops a busy Mac (several sessions building at once) from turning a
/// slow answer into `.noReply`. Production keeps its own 1–1.5 s; tests that wait on silence keep short ones.
enum Loopback {
    static let replyTimeout: Duration = .seconds(10)
    /// For a test that also waits on silence (a silent port, a scan that listens until its timeout): long enough for a
    /// busy Mac's answer, short enough that the silence costs little.
    static let mixedTimeout: Duration = .seconds(3)
}
