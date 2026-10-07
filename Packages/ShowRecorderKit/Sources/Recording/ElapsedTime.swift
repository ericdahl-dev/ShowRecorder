/// How long a Take has been running, as it's shown on the record screen.
public enum ElapsedTime {
    /// "1:05" under an hour, "1:02:03" from an hour on. A negative time (the clock was set back) is zero.
    public static func format(seconds: Int) -> String {
        let total = max(seconds, 0)
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(m):\(two(s))"
    }

    private static func two(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}
