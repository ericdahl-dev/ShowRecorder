import OSC

/// Reading one value at a time from a Behringer Mixer over OSC, shared by the X-Air and X32 drivers: both answer a
/// query with the same address and the value as its first argument.
struct MixerQueries: Sendable {
    let client: OSCUDPClient
    let timeout: Duration

    /// One channel's Source from its `base` address ("/ch/07"): name and color, then mute, fader and, when
    /// `inputSourceField` is given, its input source.
    ///
    /// Mute, fader and input source are optional: if the Mixer doesn't answer the first of them, `readsMixState`
    /// turns false and they're skipped for the rest rather than waiting out a timeout per query.
    func source(at base: String, usbChannel: Int, inputSourceField: String?, readsMixState: inout Bool) async throws(MixerLinkProblem) -> Source {
        let name = try await string(at: base + "/config/name")
        let color = MixerColor(xAirIndex: try await int(at: base + "/config/color"))
        var source = name.isEmpty ? .fallback(usbChannel: usbChannel, color: color) : Source(name: name, color: color)
        guard readsMixState else { return source }
        do {
            source.isMuted = try await optional { () async throws(MixerLinkProblem) in try await int(at: base + "/mix/on") == 0 }
            source.fader = try await optional { () async throws(MixerLinkProblem) in try await float(at: base + "/mix/fader") }
            if let inputSourceField {
                source.inputSource = try await optional { () async throws(MixerLinkProblem) in Int(try await int(at: base + "/config/" + inputSourceField)) }
            }
        } catch {
            // No reply: this Mixer doesn't report mix state. Stop asking.
            readsMixState = false
            source.isMuted = nil
            source.fader = nil
            source.inputSource = nil
        }
        return source
    }

    /// Reads an optional value: an odd reply makes it nil; no reply at all is thrown to the caller.
    func optional<T>(_ read: () async throws(MixerLinkProblem) -> T) async throws(MixerLinkProblem) -> T? {
        do {
            return try await read()
        } catch .noReply(let host) {
            throw .noReply(host: host)
        } catch {
            return nil
        }
    }

    func float(at address: String) async throws(MixerLinkProblem) -> Float {
        let reply = try await client.request(OSCMessage(address), timeout: timeout)
        guard case .float(let value)? = reply.arguments.first else { throw .other("\(address) didn't return a level") }
        return value
    }

    func string(at address: String) async throws(MixerLinkProblem) -> String {
        let reply = try await client.request(OSCMessage(address), timeout: timeout)
        guard case .string(let value)? = reply.arguments.first else { throw .other("\(address) didn't return a name") }
        return value
    }

    func int(at address: String) async throws(MixerLinkProblem) -> Int32 {
        let reply = try await client.request(OSCMessage(address), timeout: timeout)
        guard case .int(let value)? = reply.arguments.first else { throw .other("\(address) didn't return a number") }
        return value
    }

    /// `/xinfo`: the Mixer's IP, network name, model and firmware, on the X-Air and the X32 alike.
    func identify() async throws(MixerLinkProblem) -> MixerIdentity {
        let reply = try await client.request(OSCMessage("/xinfo"), timeout: timeout)
        let strings = reply.arguments.compactMap { if case .string(let value) = $0 { value } else { nil } }
        guard strings.count >= 4 else { throw .other("The Mixer's /xinfo reply was incomplete") }
        return MixerIdentity(networkName: strings[1], model: strings[2], firmware: strings[3])
    }
}
