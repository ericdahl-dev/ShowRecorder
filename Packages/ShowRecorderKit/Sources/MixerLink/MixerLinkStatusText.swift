import Foundation

extension MixerLinkStatus {
    /// What Settings › Mixer Link says about the Link. `families` are the Mixer families offered in this run of the
    /// app (the WING only where it is turned on).
    public func settingsText(offering families: [MixerFamily] = MixerFamily.allCases) -> String {
        switch self {
        case .idle:
            "Not connected to a Mixer. Stems use USB Channel names."
        case .connecting(let host):
            "Connecting to \(host)…"
        case .up(let identity, let path):
            "Mixer Link up · \(identity.networkName) (\(identity.model)) · \(path.name)"
        case .down(let problem):
            problem.message
        }
    }
}
