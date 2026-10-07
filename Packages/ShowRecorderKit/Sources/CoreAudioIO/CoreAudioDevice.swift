#if os(macOS)
import AudioIO
import AudioToolbox
import CoreAudio

/// A Core Audio device on macOS, used as the recorder's audio I/O.
///
/// Input runs through an AUHAL unit pinned to this device. Its input callback is the real-time
/// path: it renders into a buffer list and channel-pointer table allocated in `start`, then hands
/// the block on. Nothing is allocated per block (ADR 0002).
public final class CoreAudioDevice: AudioIODevice, @unchecked Sendable {
    public let id: AudioDeviceID
    public let name: String
    public let inputChannelCount: Int
    public let outputChannelCount: Int
    public let sampleRate: Double

    private var session: InputSession?

    init(id: AudioDeviceID, name: String, inputChannelCount: Int, outputChannelCount: Int, sampleRate: Double) {
        self.id = id
        self.name = name
        self.inputChannelCount = inputChannelCount
        self.outputChannelCount = outputChannelCount
        self.sampleRate = sampleRate
    }

    deinit { stop() }

    /// Every Core Audio device with at least one input channel.
    public static func inputDevices() -> [CoreAudioDevice] {
        deviceIDs().compactMap { id in
            let inputs = channelCount(of: id, scope: kAudioObjectPropertyScopeInput)
            guard inputs > 0 else { return nil }
            return CoreAudioDevice(
                id: id,
                name: stringProperty(kAudioObjectPropertyName, of: id) ?? "Audio Device \(id)",
                inputChannelCount: inputs,
                outputChannelCount: channelCount(of: id, scope: kAudioObjectPropertyScopeOutput),
                sampleRate: nominalSampleRate(of: id))
        }
    }

    /// The system's default input device, if there is one.
    public static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    public func start(input: @escaping AudioInputHandler) throws {
        stop()
        let id = id
        session = try InputSession(
            subtype: kAudioUnitSubType_HALOutput,
            channelCount: inputChannelCount,
            sampleRate: sampleRate,
            handler: input,
            selectDevice: { unit in
                var device = id
                try check("select the device", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)))
            })
    }

    public func stop() {
        session?.stop()
        session = nil
    }
}

// MARK: - Core Audio property helpers

private func deviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

private func channelCount(of id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: scope,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
    let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return list.reduce(0) { $0 + Int($1.mNumberChannels) }
}

private func stringProperty(_ selector: AudioObjectPropertySelector, of id: AudioDeviceID) -> String? {
    var address = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
}

private func nominalSampleRate(of id: AudioDeviceID) -> Double {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyNominalSampleRate,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var rate: Float64 = 0
    var size = UInt32(MemoryLayout<Float64>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr else { return 0 }
    return rate
}
#endif
