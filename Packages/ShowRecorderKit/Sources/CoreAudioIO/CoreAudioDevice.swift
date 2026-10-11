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
    /// The device's persistent UID. Unlike `id`, it stays the same when the device is unplugged and
    /// plugged back in.
    public let uid: String
    public let name: String
    public let inputChannelCount: Int
    public let outputChannelCount: Int
    public let sampleRate: Double

    private var session: InputSession?

    init(id: AudioDeviceID, uid: String, name: String, inputChannelCount: Int, outputChannelCount: Int, sampleRate: Double) {
        self.id = id
        self.uid = uid
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
                uid: stringProperty(kAudioDevicePropertyDeviceUID, of: id) ?? "id-\(id)",
                name: stringProperty(kAudioObjectPropertyName, of: id) ?? "Audio Device \(id)",
                inputChannelCount: inputs,
                outputChannelCount: channelCount(of: id, scope: kAudioObjectPropertyScopeOutput),
                sampleRate: nominalSampleRate(of: id))
        }
    }

    /// The sample rates the device offers, in whole Hz, lowest first (#195). A mixer's USB input usually offers
    /// only the rate set on the mixer.
    public var availableSampleRates: [Int] { availableNominalSampleRates(of: id) }

    /// Sets the device's sample rate, which on a Mac is the interface's rate for every app (Audio MIDI Setup), and
    /// returns the device as it is afterwards. Throws when the device refuses or doesn't change within a second.
    public static func settingSampleRate(_ rate: Int, of device: CoreAudioDevice) throws -> CoreAudioDevice {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var wanted = Float64(rate)
        let status = AudioObjectSetPropertyData(device.id, &address, 0, nil, UInt32(MemoryLayout<Float64>.size), &wanted)
        guard status == noErr else { throw SampleRateError.refused(status) }
        for _ in 0..<50 where Int(nominalSampleRate(of: device.id).rounded()) != rate {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard let updated = inputDevices().first(where: { $0.uid == device.uid }),
              Int(updated.sampleRate.rounded()) == rate else { throw SampleRateError.notApplied(rate) }
        return updated
    }

    public enum SampleRateError: Error, CustomStringConvertible {
        case refused(OSStatus)
        case notApplied(Int)

        public var description: String {
            switch self {
            case .refused(let status): "the interface refused the sample rate (\(status))"
            case .notApplied(let rate): "the interface didn't switch to \(rate) Hz"
            }
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

func deviceIDs() -> [AudioDeviceID] {
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

/// The device's offered rates. Core Audio gives ranges; a range offers the common rates inside it.
private func availableNominalSampleRates(of id: AudioDeviceID) -> [Int] {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &ranges) == noErr else { return [] }
    let common = [44_100, 48_000, 88_200, 96_000, 176_400, 192_000]
    var rates = Set<Int>()
    for range in ranges {
        if range.mMinimum == range.mMaximum {
            rates.insert(Int(range.mMinimum.rounded()))
        } else {
            rates.formUnion(common.filter { Double($0) >= range.mMinimum && Double($0) <= range.mMaximum })
        }
    }
    return rates.sorted()
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
