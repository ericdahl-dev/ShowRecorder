import Testing

@testable import Recording

/// Which confirmation each delete needs: the Show's name typed for a whole Show, a plain confirmation for one Take, one file, or a Show with no Takes left.
@Suite("Delete confirmation")
struct DeleteConfirmationTests {
    @Test("A whole Show needs its name typed")
    func wholeShow() {
        #expect(DeleteConfirmation.needed(take: nil, channel: nil, takeCount: 3) == .typedName)
    }

    @Test("A whole Show with no Takes left (its files removed in Files) needs only a plain confirmation: nothing recorded is lost")
    func emptyShow() {
        #expect(DeleteConfirmation.needed(take: nil, channel: nil, takeCount: 0) == .plain)
    }

    @Test("One Take needs a plain confirmation")
    func oneTake() {
        #expect(DeleteConfirmation.needed(take: 2, channel: nil, takeCount: 3) == .plain)
    }

    @Test("One channel file needs a plain confirmation")
    func oneFile() {
        #expect(DeleteConfirmation.needed(take: 2, channel: 5, takeCount: 3) == .plain)
    }
}
