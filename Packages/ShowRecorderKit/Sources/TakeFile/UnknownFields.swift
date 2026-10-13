import Foundation

/// The top-level fields of a `Take.json` or `Show.json` this version doesn't know: written by a newer ShowRecorder.
/// Kept when the file is read, so saving it again (a renamed Marker, a venue) doesn't drop them.
public struct UnknownFields: Equatable, Sendable {
    /// A JSON object holding just those fields.
    private let json: Data

    /// The fields of the JSON object in `data` whose names aren't in `known`. Nil when there are none.
    public static func find(in data: Data, known: Set<String>) -> UnknownFields? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let unknown = object.filter { !known.contains($0.key) }
        guard !unknown.isEmpty, let json = try? JSONSerialization.data(withJSONObject: unknown) else { return nil }
        return UnknownFields(json: json)
    }

    /// `encoded`, a JSON object, with these fields added where it has none of that name, laid out as `JSONEncoder`
    /// lays out the files (pretty-printed, keys sorted).
    public func merged(into encoded: Data) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any],
              let unknown = try JSONSerialization.jsonObject(with: json) as? [String: Any] else { return encoded }
        for (key, value) in unknown where object[key] == nil { object[key] = value }
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}
