import Foundation
import Testing
@testable import ShowRecorder

struct SupportMailTests {
    private let linked = SupportMail.Details(
        version: "ShowRecorder 1.1.6 (34.1)", device: "iPhone16,1", system: "iOS 26.0.1",
        armedInput: "X18/XR18 · 18 USB Channels", mixerLink: "X Air · XR18, firmware 1.22")

    @Test("The body leaves room to write above the app and device details, one per line (#722)")
    func bodyWithEverything() {
        #expect(SupportMail.body(linked) == """


            ---
            App: ShowRecorder 1.1.6 (34.1)
            Device: iPhone16,1
            System: iOS 26.0.1
            Armed input: X18/XR18 · 18 USB Channels
            Mixer Link: X Air · XR18, firmware 1.22
            """)
    }

    @Test("With nothing Armed and no Mixer Link, the body says so instead of leaving blanks (#722)")
    func bodyWithNothingArmed() {
        var details = linked
        details.armedInput = nil
        details.mixerLink = nil
        let body = SupportMail.body(details)
        #expect(body.contains("\nArmed input: No audio interface\n"))
        #expect(body.hasSuffix("\nMixer Link: Not linked"))
    }

    @Test("The mailto link goes to showrecorder@ericdahl.dev with the subject and the body, line breaks kept (#722)")
    func mailtoLink() throws {
        let url = try #require(SupportMail.mailtoURL(body: "Hi\nApp: 1.1.6 & more"))
        #expect(url.scheme == "mailto")
        let parts = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(parts.path == "showrecorder@ericdahl.dev")
        #expect(parts.queryItems?.first { $0.name == "subject" }?.value == SupportMail.subject)
        #expect(parts.queryItems?.first { $0.name == "body" }?.value == "Hi\nApp: 1.1.6 & more")
        // Spaces as %20, never "+", which Mail would show as a plus sign.
        #expect(!url.absoluteString.contains("+"))
        #expect(url.absoluteString.contains("Hi%0AApp"))
    }

    @Test("The report to attach is the newest Show's Report.html, skipping Shows that have none yet (#722)")
    func lastReport() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SupportMailTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let newest = root.appending(path: "2026-10-15 Open Show"), older = root.appending(path: "2026-10-14 Bar")
        let oldest = root.appending(path: "2026-10-01 Club")
        for folder in [newest, older, oldest] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        for folder in [older, oldest] { try Data("<html>".utf8).write(to: folder.appending(path: "Report.html")) }

        #expect(SupportMail.lastReport(showFolders: [newest, older, oldest]) == older.appending(path: "Report.html"))
        #expect(SupportMail.lastReport(showFolders: [newest]) == nil)
        #expect(SupportMail.lastReport(showFolders: []) == nil)
    }
}
