import Recording
import Testing

@Suite("Show sheet")
struct ShowSheetTests {
    @Test("The sheet is titled Show, whatever is open")
    func title() {
        #expect(ShowSheet(openShowName: nil, isRecording: false).title == "Show")
        #expect(ShowSheet(openShowName: "Gig", isRecording: true).title == "Show")
    }

    @Test("With no Show open there is no End Show, and starting a Show is the only offer")
    func noShowOpen() {
        let sheet = ShowSheet(openShowName: nil, isRecording: false)
        #expect(!sheet.offersEndShow)
        #expect(!sheet.endShowFirst)
        #expect(sheet.canStartShow)
    }

    @Test("With a Show open, End Show comes first and is enabled")
    func showOpen() {
        let sheet = ShowSheet(openShowName: "2026-10-06 Show", isRecording: false)
        #expect(sheet.offersEndShow)
        #expect(sheet.endShowFirst)
        #expect(sheet.canEndShow)
        #expect(sheet.canStartShow)
    }

    @Test("During a Take, End Show and Start Show are both disabled, and the sheet says why")
    func takeRunning() {
        let sheet = ShowSheet(openShowName: "Gig", isRecording: true)
        #expect(sheet.offersEndShow)
        #expect(!sheet.canEndShow)
        #expect(!sheet.canStartShow)
        #expect(sheet.endShowNote.contains("Take"))
    }

    @Test("The note under End Show says the files are kept")
    func note() {
        let sheet = ShowSheet(openShowName: "Gig", isRecording: false)
        #expect(sheet.endShowNote.contains("keeps its files"))
    }
}
