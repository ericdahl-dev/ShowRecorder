@testable import Recording
import Testing

@Suite("Take names")
struct TakeNameTests {
    @Test("A Take's name, which is also its folder's, has its number in two digits or more")
    func name() {
        #expect(TakeMetadata.name(take: 1) == "Take 01")
        #expect(TakeMetadata.name(take: 12) == "Take 12")
        #expect(TakeMetadata.name(take: 100) == "Take 100")
    }
}
