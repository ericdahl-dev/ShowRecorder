import Foundation
import Recording
import Testing

@Suite("Settings' Help row (#990)")
struct HelpLinkTests {
    @Test("Help opens the website's general help, /docs, tagged so PostHog shows the visit came from the app")
    func opensDocs() {
        #expect(HelpLink.docs.absoluteString == "https://showrecorder.app/docs?utm_source=app&utm_campaign=settings-help")
    }

    @Test("Help is the general help, never a mixer's page or a maker's manual")
    func generalHelpOnly() {
        #expect(HelpLink.docs.host() == "showrecorder.app")
        #expect(HelpLink.docs.path() == "/docs")
    }
}

struct FacebookLinkTests {
    @Test("Settings links the ShowRecorder Facebook Page, so people can follow it (Eric, 2026-11-15)")
    func opensThePage() {
        #expect(HelpLink.facebook.absoluteString == "https://www.facebook.com/profile.php?id=61596288844683")
    }
}
