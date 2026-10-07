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
        session = try InputSession(deviceID: id, channelCount: inputChannelCount, sampleRate: sampleRate, handler: input)
    }

    public func stop() {
        session?.stop()
        session = nil
    }
}

public enum CoreAudioError: Error, CustomStringConvertible {
    case status(String, OSStatus)
    case noHALUnit

    public var description: String {
        switch self {
        case .status(let step, let status): "Core Audio failed to \(step) (error \(status))"
        case .noHALUnit: "Core Audio's input unit isn't available"
        }
    }
}

// MARK: - AUHAL input session

/// One running AUHAL input. Owns everything the real-time callback touches.
private final class InputSession {
    let unit: AudioUnit
    let channelCount: Int
    let maxFrames: Int
    let handler: AudioInputHandler
    /// Non-interleaved buffer list with one buffer per channel.
    let bufferList: UnsafeMutableAudioBufferListPointer
    let table: UnsafeMutablePointer<UnsafePointer<Float>>
    private var unmanagedSelf: Unmanaged<InputSession>?

    init(deviceID: AudioDeviceID, channelCount: Int, sampleRate: Double, handler: @escaping AudioInputHandler) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw CoreAudioError.noHALUnit }
        var unit: AudioUnit?
        try check("create the input unit", AudioComponentInstanceNew(component, &unit))
        guard let unit else { throw CoreAudioError.noHALUnit }

        self.unit = unit
        self.channelCount = channelCount
        self.handler = handler

        var enable: UInt32 = 1
        var disable: UInt32 = 0
        var device = deviceID
        var maxFrames: UInt32 = 4096
        do {
            try check("enable input", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, UInt32(MemoryLayout<UInt32>.size)))
            try check("disable output", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable, UInt32(MemoryLayout<UInt32>.size)))
            try check("select the device", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, UInt32(MemoryLayout<AudioDeviceID>.size)))

            var format = AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4,
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,
                mChannelsPerFrame: UInt32(channelCount),
                mBitsPerChannel: 32,
                mReserved: 0)
            try check("set the input format", AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))

            var size = UInt32(MemoryLayout<UInt32>.size)
            try check("read the buffer size", AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, &size))
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
        self.maxFrames = Int(maxFrames)

        bufferList = AudioBufferList.allocate(maximumBuffers: max(channelCount, 1))
        for channel in 0..<channelCount {
            let bytes = Int(maxFrames) * MemoryLayout<Float>.size
            bufferList[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes), mData: UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: 16))
        }
        table = .allocate(capacity: max(channelCount, 1))

        let retained = Unmanaged.passRetained(self)
        unmanagedSelf = retained
        var callback = AURenderCallbackStruct(inputProc: inputProc, inputProcRefCon: retained.toOpaque())
        do {
            try check("set the input callback", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
            try check("initialize the input unit", AudioUnitInitialize(unit))
            try check("start the input", AudioOutputUnitStart(unit))
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        unmanagedSelf?.release()
        unmanagedSelf = nil
    }

    deinit {
        for buffer in bufferList { buffer.mData?.deallocate() }
        free(bufferList.unsafeMutablePointer)
        table.deallocate()
    }

    /// Real-time: render this cycle's input and hand it on. No allocation, locks or logging.
    func render(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, timestamp: UnsafePointer<AudioTimeStamp>, frames: UInt32) -> OSStatus {
        let frameCount = min(Int(frames), maxFrames)
        for channel in 0..<channelCount {
            bufferList[channel].mDataByteSize = UInt32(frameCount * MemoryLayout<Float>.size)
        }
        let status = AudioUnitRender(unit, flags, timestamp, 1, UInt32(frameCount), bufferList.unsafeMutablePointer)
        guard status == noErr else { return status }
        for channel in 0..<channelCount {
            table[channel] = UnsafePointer(bufferList[channel].mData!.assumingMemoryBound(to: Float.self))
        }
        handler(AudioBlock(channels: table, channelCount: channelCount, frameCount: frameCount, hostTime: timestamp.pointee.mHostTime))
        return noErr
    }
}

private func inputProc(
    refCon: UnsafeMutableRawPointer,
    flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    timestamp: UnsafePointer<AudioTimeStamp>,
    bus: UInt32,
    frames: UInt32,
    data: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    Unmanaged<InputSession>.fromOpaque(refCon).takeUnretainedValue().render(flags: flags, timestamp: timestamp, frames: frames)
}

private func check(_ step: String, _ status: OSStatus) throws {
    guard status == noErr else { throw CoreAudioError.status(step, status) }
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
