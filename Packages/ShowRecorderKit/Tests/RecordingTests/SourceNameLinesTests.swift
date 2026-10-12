import Testing

@testable import Recording

/// A Source's name under its meter is laid out in whole words, so a word never splits across lines (#378).
@Suite("Source name lines")
struct SourceNameLinesTests {
    @Test("One word stays on one line, to be shrunk rather than broken (\"Sna / re\")")
    func oneWord() {
        #expect(SourceNameLines.split("Snare") == ["Snare"])
    }

    @Test("Two words go on two lines, a word each")
    func twoWords() {
        #expect(SourceNameLines.split("Overhead 1") == ["Overhead", "1"])
    }

    @Test("More words break where the longer line is shortest")
    func balanced() {
        #expect(SourceNameLines.split("Acoustic Gtr DI") == ["Acoustic", "Gtr DI"])
        #expect(SourceNameLines.split("Lead Vox Left Mic") == ["Lead Vox", "Left Mic"])
    }

    @Test("Extra spaces don't make empty words")
    func spaces() {
        #expect(SourceNameLines.split("  Keys   1 ") == ["Keys", "1"])
    }
}
