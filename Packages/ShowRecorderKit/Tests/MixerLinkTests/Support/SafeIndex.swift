extension Array {
    /// The element at `index`, or nil when there is none. Tests read Sources this way: a Link that drops under
    /// load empties its Sources, and a plain subscript would crash the whole test run instead of failing one check.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
