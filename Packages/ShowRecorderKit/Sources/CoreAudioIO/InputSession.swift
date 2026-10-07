import AudioIO
import AudioToolbox
import CoreAudio

public enum CoreAudioError: Error, CustomStringConvertible {
    case status(String, OSStatus)
    case noInputUnit

    public var description: String {
        switch self {
        case .status(let step, let status): "Core Audio failed to \(step) (error \(status))"
        case .noInputUnit: "The audio input unit isn't available"
        }
    }
}

// MARK: - Input session

/// One running input audio unit (AUHAL on macOS, RemoteIO on iOS).
/// Owns everything the real-time callback touches.
final class InputSession {
    let unit: AudioUnit
    let channelCount: Int
    let maxFrames: Int
    let handler: AudioInputHandler
    /// Non-interleaved buffer list with one buffer per channel.
    let bufferList: UnsafeMutableAudioBufferListPointer
    let table: UnsafeMutablePointer<UnsafePointer<Float>>
    private var unmanagedSelf: Unmanaged<InputSession>?

    /// - Parameters:
    ///   - subtype: `kAudioUnitSubType_HALOutput` (macOS) or `kAudioUnitSubType_RemoteIO` (iOS).
    ///   - selectDevice: sets the unit's device before it is initialized (macOS only).
    init(
        subtype: OSType,
        channelCount: Int,
        sampleRate: Double,
        handler: @escaping AudioInputHandler,
        selectDevice: (AudioUnit) throws -> Void = { _ in }
    ) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: subtype,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw CoreAudioError.noInputUnit }
        var unit: AudioUnit?
        try check("create the input unit", AudioComponentInstanceNew(component, &unit))
        guard let unit else { throw CoreAudioError.noInputUnit }

        self.unit = unit
        self.channelCount = channelCount
        self.handler = handler

        var enable: UInt32 = 1
        var disable: UInt32 = 0
        var maxFrames: UInt32 = 4096
        do {
            try check("enable input", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, UInt32(MemoryLayout<UInt32>.size)))
            try check("disable output", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disable, UInt32(MemoryLayout<UInt32>.size)))
            try selectDevice(unit)

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

            // Set, not just read: the render callback must never be asked for more frames than
            // the preallocated buffers hold.
            try check("set the buffer size", AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, UInt32(MemoryLayout<UInt32>.size)))
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
        // Never truncate silently. A slice larger than the buffers is an error the HAL reports.
        guard Int(frames) <= maxFrames else { return kAudioUnitErr_TooManyFramesToProcess }
        let frameCount = Int(frames)
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

func check(_ step: String, _ status: OSStatus) throws {
    guard status == noErr else { throw CoreAudioError.status(step, status) }
}
