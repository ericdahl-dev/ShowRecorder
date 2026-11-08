import Foundation
import Recording
import Testing

@Suite("Settings' Help row (#990)")
struct HelpLinkTests {
    @Test("Help opens the website's general help, /docs")
    func opensDocs() {
        #expect(HelpLink.docs.absoluteString == "https://showrecorder.app/docs")
    }

    @Test("Help is the general help, never a mixer's page or a maker's manual")
    func generalHelpOnly() {
        #expect(HelpLink.docs.host() == "showrecorder.app")
        #expect(HelpLink.docs.path() == "/docs")
    }
}
