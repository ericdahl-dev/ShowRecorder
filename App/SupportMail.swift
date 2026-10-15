import Foundation

/// The email Settings' "Contact support" opens (#722). Everything in it is shown in Mail for the user to read, edit or
/// delete before sending; the app sends nothing itself, so "collects no data" still holds.
enum SupportMail {
    static let address = "showrecorder@ericdahl.dev"
    static let subject = "ShowRecorder support"
    /// What the app and device were when support was asked for. Each is a line the user can read.
    struct Details: Equatable {
        /// `AppVersion.current`: the version and build, and a Debug build's commit.
        var version: String
        /// The hardware model, such as "iPhone16,1" or "Mac15,3".
        var device: String
        /// The OS and its version, such as "iOS 26.0.1".
        var system: String
        /// The Armed input's name and USB Channel count, or nil when none is Armed.
        var armedInput: String?
        /// The Mixer Link's family and Mixer, or nil when it isn't linked.
        var mixerLink: String?
    }

    /// Blank lines to write in, then the details below a rule.
    static func body(_ details: Details) -> String {
        """


        ---
        App: \(details.version)
        Device: \(details.device)
        System: \(details.system)
        Armed input: \(details.armedInput ?? "No audio interface")
        Mixer Link: \(details.mixerLink ?? "Not linked")
        """
    }

    /// The Show report the user may attach: the newest Show's `Report.html` on the Device, from Show folders newest
    /// first (as `ShowList.read` returns them). A Show with no report yet, such as one still open, is skipped.
    static func lastReport(showFolders: [URL]) -> URL? {
        // ShowReport.htmlFileName; the app doesn't link ShowReport.
        showFolders.lazy.map { $0.appending(path: "Report.html") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A `mailto:` link to support with the subject and `body`, for the Mac and for an iPhone without Mail set up. Each
    /// value is encoded by hand: `URLComponents.queryItems` leaves "&" and "=" as they are, which would cut the body short.
    static func mailtoURL(body: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        func encode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        return URL(string: "mailto:\(address)?subject=\(encode(subject))&body=\(encode(body))")
    }
}
