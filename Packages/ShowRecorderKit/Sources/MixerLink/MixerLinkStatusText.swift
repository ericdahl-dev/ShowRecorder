import Foundation

extension MixerLinkStatus {
    /// What Settings › Mixer Link says about the Link. Not connected, it names the Mixers the Link works with, from
    /// `families` (the families offered in this run of the app, so the WING only where it is turned on). Up, it says
    /// what kind of Mixer the Link is on, from the model the Mixer gave: the same reading that picked its driver.
    public func settingsText(offering families: [MixerFamily] = MixerFamily.allCases) -> String {
        switch self {
        case .idle:
            "Works with \(Self.list(families.map(\.linkModels))). Not connected. Stems use USB Channel names."
        case .connecting(let host):
            "Connecting to \(host)…"
        case .up(let identity, let path):
            "Connected to \(MixerFamily.reading(model: identity.model).linkKind) · \(identity.nameAndModel) · \(path.name)"
        case .down(let problem):
            problem.message
        }
    }

    /// "A", "A and B", "A, B and C".
    private static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        let rest = items.dropLast()
        return rest.isEmpty ? last : "\(rest.joined(separator: ", ")) and \(last)"
    }
}

extension MixerFamily {
    /// The family and its models as the Mixer Link status names them: "X Air (XR12/16/18, MR18)".
    fileprivate var linkModels: String {
        switch self {
        case .xAir: "X Air (XR12/16/18, MR18)"
        case .x32: "X32/M32"
        case .wing: "WING"
        }
    }

    /// The family with its article, for "Connected to an X Air".
    fileprivate var linkKind: String {
        switch self {
        case .xAir: "an X Air"
        case .x32: "an X32"
        case .wing: "a WING"
        }
    }
}
