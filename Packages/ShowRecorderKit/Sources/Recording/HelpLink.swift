import Foundation

/// Where Settings' Help row goes (#990): the website's general help. Never a mixer's page or a maker's manual
/// (Eric, 2026-10-28): the app isn't for one mixer, and mixer help lives on the website's mixer pages, where a
/// moved manual can be fixed without an app release. Tagged like the links we post, so PostHog (Owned Sites) shows
/// which docs visits came from the app.
public enum HelpLink {
    public static let docs = URL(string: "https://showrecorder.app/docs?utm_source=app&utm_campaign=settings-help")!
}
