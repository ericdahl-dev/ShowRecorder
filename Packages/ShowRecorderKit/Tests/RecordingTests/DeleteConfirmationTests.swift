import Testing

@testable import Recording

/// Which confirmation each delete needs: the Show's name typed for a whole Show, a plain confirmation for one Take or one file.
@Suite("Delete confirmation")
struct DeleteConfirmationTests {
    @Test("A whole Show needs its name typed")
    func wholeShow() {
        #expect(DeleteConfirmation.needed(take: nil, channel: nil) == .typedName)
    }

    @Test("One Take needs a plain confirmation")
    func oneTake() {
        #expect(DeleteConfirmation.needed(take: 2, channel: nil) == .plain)
    }

    @Test("One channel file needs a plain confirmation")
    func oneFile() {
        #expect(DeleteConfirmation.needed(take: 2, channel: 5) == .plain)
    }
}
