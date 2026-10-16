import Foundation

/// The email Settings' "Contact support" opens (#722). Everything in it is shown in Mail for the user to read, edit or
/// delete before sending; the app sends nothing itself, so "collects no data" still holds. The subject and the
/// diagnostics body are `SupportDiagnostics`.
enum SupportMail {
    static let address = "showrecorder@ericdahl.dev"
    /// The Show report the user may attach: the newest Show's `Report.html` on the Device, from Show folders newest
    /// first (as `ShowList.read` returns them). A Show with no report yet, such as one still open, is skipped.
    static func lastReport(showFolders: [URL]) -> URL? {
        // ShowReport.htmlFileName; the app doesn't link ShowReport.
        showFolders.lazy.map { $0.appending(path: "Report.html") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A `mailto:` link to support with the subject and `body`, for the Mac and for an iPhone without Mail set up. Each
    /// value is encoded by hand: `URLComponents.queryItems` leaves "&" and "=" as they are, which would cut the body short.
    static func mailtoURL(subject: String, body: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        return URL(string: "mailto:\(address)?subject=\(encode(subject))&body=\(encode(body))")
    }
}
