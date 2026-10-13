#if os(iOS)
import AudioIO
import AudioToolbox
import CoreAudio
import Synchronization

/// The headphone monitor's three switches (#233), set on the main thread and read by the output callback before each
/// render. Relaxed atomics: a switch taking effect one render late doesn't matter. Owned by the App, so they outlive
/// each `MonitorOutput` (a re-Arm makes a new one).
public final class MonitorSwitches: Sendable {
    private let monitorOn = Atomic<Bool>(false)
    private let toneOn = Atomic<Bool>(false)
    private let outputIsHeadphones = Atomic<Bool>(false)

    public init() {}

    public var monitor: Bool {
        get { monitorOn.load(ordering: .relaxed) }
        set { monitorOn.store(newValue, ordering: .relaxed) }
    }

    public var tone: Bool {
        get { toneOn.load(ordering: .relaxed) }
        set { toneOn.store(newValue, ordering: .relaxed) }
    }

    public var headphones: Bool {
        get { outputIsHeadphones.load(ordering: .relaxed) }
        set { outputIsHeadphones.store(newValue, ordering: .relaxed) }
    }

    /// Real-time safe: three relaxed loads.
    var flags: MonitorMixer.Flags {
        MonitorMixer.Flags(monitor: monitor, tone: tone, headphones: headphones)
    }
}

/// The headphone monitor's output (#233 experiment): its own output-only RemoteIO unit, separate from the input's,
/// playing the `MonitorRing` in both ears through `MonitorMixer`. Two-channel non-interleaved Float32 at the input's
/// rate. Nothing here touches the input or the Take: if it fails to start, the caller logs it and the monitor stays
/// silent.
///
/// Two RemoteIO units in one app (this one and `InputSession`'s) is the experiment's untested assumption. If they
/// misbehave on a device (glitches, one stopping the other, a route change killing output), the fallback is one
/// RemoteIO unit with input and output both enabled, which this deliberately doesn't build yet.
public final class MonitorOutput: @unchecked Sendable {
    let unit: AudioUnit
    let ring: MonitorRing
    let switches: MonitorSwitches
    /// The output callback's mixer. Allocated once and only touched by the callback (and `deinit`), so no exclusivity
    /// checks on the real-time thread.
    let mixer: UnsafeMutablePointer<MonitorMixer>
    private var unmanagedSelf: Unmanaged<MonitorOutput>?

    /// Creates and starts the output unit. Throws `CoreAudioError` if any step fails; nothing is left running then.
    public init(ring: MonitorRing, switches: MonitorSwitches, sampleRate: Double) throws {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_RemoteIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0)
        guard let component = AudioComponentFindNext(nil, &description) else { throw CoreAudioError.noInputUnit }
        var created: AudioUnit?
        try check("create the monitor output unit", AudioComponentInstanceNew(component, &created))
        guard let unit = created else { throw CoreAudioError.noInputUnit }
        self.unit = unit
        self.ring = ring
        self.switches = switches
        mixer = .allocate(capacity: 1)
        mixer.initialize(to: MonitorMixer(sampleRate: sampleRate))

        var enable: UInt32 = 1
        var disable: UInt32 = 0
        var maxFrames: UInt32 = 4096
        let size = UInt32(MemoryLayout<UInt32>.size)
        do {
            try check("enable monitor output", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable, size))
            try check("disable monitor input", AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &disable, size))
            var format = AudioStreamBasicDescription(
                mSampleRate: sampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4,
                mFramesPerPacket: 1,
                mBytesPerFrame: 4,
                mChannelsPerFrame: 2,
                mBitsPerChannel: 32,
                mReserved: 0)
            // What this app hands the unit: the input scope of the output bus.
            try check("set the monitor format", AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)))
            try check("set the monitor buffer size", AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, size))
        } catch {
            // `deinit` still runs (every property is set), and frees the mixer.
            AudioComponentInstanceDispose(unit)
            throw error
        }

        let retained = Unmanaged.passRetained(self)
        unmanagedSelf = retained
        var callback = AURenderCallbackStruct(inputProc: monitorRenderProc, inputProcRefCon: retained.toOpaque())
        do {
            try check("set the monitor callback", AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
            try check("initialize the monitor output", AudioUnitInitialize(unit))
            try check("start the monitor output", AudioOutputUnitStart(unit))
        } catch {
            stop()
            throw error
        }
    }

    /// Stops and disposes of the unit. Safe to call more than once.
    public func stop() {
        guard let retained = unmanagedSelf else { return }
        unmanagedSelf = nil
        AudioOutputUnitStop(unit)
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
        retained.release()
    }

    deinit {
        mixer.deinitialize(count: 1)
        mixer.deallocate()
    }

    /// Real-time: fills both channels from the ring. No allocation, locks or logging (ADR 0002).
    func render(frames: UInt32, data: UnsafeMutablePointer<AudioBufferList>?) -> OSStatus {
        guard let data else { return noErr }
        let buffers = UnsafeMutableAudioBufferListPointer(data)
        guard buffers.count >= 2, let left = buffers[0].mData, let right = buffers[1].mData else {
            for buffer in buffers {
                if let bytes = buffer.mData { bytes.initializeMemory(as: UInt8.self, repeating: 0, count: Int(buffer.mDataByteSize)) }
            }
            return noErr
        }
        let capacity = Int(min(buffers[0].mDataByteSize, buffers[1].mDataByteSize)) / MemoryLayout<Float>.size
        let count = min(Int(frames), capacity)
        mixer.pointee.render(
            left: left.assumingMemoryBound(to: Float.self), right: right.assumingMemoryBound(to: Float.self),
            count: count, ring: ring, flags: switches.flags)
        return noErr
    }
}

private func monitorRenderProc(
    refCon: UnsafeMutableRawPointer,
    flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    timestamp: UnsafePointer<AudioTimeStamp>,
    bus: UInt32,
    frames: UInt32,
    data: UnsafeMutablePointer<AudioBufferList>?
) -> OSStatus {
    Unmanaged<MonitorOutput>.fromOpaque(refCon).takeUnretainedValue().render(frames: frames, data: data)
}
#endif
