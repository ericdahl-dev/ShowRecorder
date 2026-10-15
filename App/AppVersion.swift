import Foundation

/// The line at the bottom of Settings that says which build is installed (#697).
enum AppVersion {
    /// "ShowRecorder 1.1.6 (34.1)": the version and the build. A Debug build adds "Debug" and the short git commit that
    /// was stamped into it at build time, since every Debug build reads the same version and build.
    static func line(version: String?, build: String?, isDebug: Bool, commit: String?) -> String {
        var line = "ShowRecorder \(version ?? "?") (\(build ?? "?"))"
        if isDebug {
            line += " · Debug"
            if let commit, !commit.isEmpty { line += " · \(commit)" }
        }
        return line
    }

    /// This build's line, from its Info.plist. `ShowRecorderGitCommit` is stamped by the Debug build's "Stamp git commit" phase.
    static var current: String {
        let info = Bundle.main.infoDictionary
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        return line(
            version: info?["CFBundleShortVersionString"] as? String, build: info?["CFBundleVersion"] as? String,
            isDebug: isDebug, commit: info?["ShowRecorderGitCommit"] as? String)
    }
}
