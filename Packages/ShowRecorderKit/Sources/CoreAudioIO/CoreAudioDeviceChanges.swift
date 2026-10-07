#if os(macOS)
import CoreAudio
import Dispatch

extension CoreAudioDevice {
    /// Yields whenever a device is added or removed, the default input changes, or a device's
    /// sample rate or input channel layout changes. Re-read `inputDevices()` to see what changed.
    ///
    /// Core Audio sends several notifications for one plug or unplug; only the newest is buffered,
    /// so a slow reader sees one event per burst. Listeners are removed when the stream ends
    /// (the iterating task is cancelled or the stream is dropped).
    public static func changes() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let watcher = DeviceChangeWatcher(continuation: continuation)
            watcher.start()
            continuation.onTermination = { _ in watcher.stop() }
        }
    }
}

/// Owns the Core Audio property listeners behind `CoreAudioDevice.changes()`.
///
/// These run on Core Audio's notification path, not the audio thread, but still never block:
/// a listener only yields to the stream. Adding and removing listeners happens on `control`, a
/// serial queue separate from the one listeners are called on, so a removal never waits on its
/// own queue.
private final class DeviceChangeWatcher: @unchecked Sendable {
    private let listenerQueue = DispatchQueue(label: "dev.ericdahl.ShowRecorder.device-changes")
    private let control = DispatchQueue(label: "dev.ericdahl.ShowRecorder.device-changes.control")
    private let continuation: AsyncStream<Void>.Continuation
    private let notify: AudioObjectPropertyListenerBlock

    // Touched only on `control`.
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var watchedDevices: [AudioDeviceID] = []
    private var isStopped = false

    private static let systemAddresses = [
        address(kAudioHardwarePropertyDevices),
        address(kAudioHardwarePropertyDefaultInputDevice),
    ]
    private static let deviceAddresses = [
        address(kAudioDevicePropertyNominalSampleRate),
        address(kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput),
    ]

    init(continuation: AsyncStream<Void>.Continuation) {
        self.continuation = continuation
        notify = { _, _ in continuation.yield() }
    }

    func start() {
        control.async { [self] in
            guard !isStopped else { return }
            // System-level changes can add or remove devices, so they also move the per-device listeners.
            let resync: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                continuation.yield()
                control.async { self.watchCurrentDevices() }
            }
            for var address in Self.systemAddresses {
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, resync)
            }
            systemListener = resync
            watchCurrentDevices()
        }
    }

    func stop() {
        control.async { [self] in
            guard !isStopped else { return }
            isStopped = true
            if let systemListener {
                for var address in Self.systemAddresses {
                    AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, systemListener)
                }
            }
            systemListener = nil
            for device in watchedDevices { remove(from: device) }
            watchedDevices = []
        }
    }

    /// Moves the per-device listeners to the devices present now. Runs on `control`.
    private func watchCurrentDevices() {
        guard !isStopped else { return }
        let current = deviceIDs()
        for device in watchedDevices where !current.contains(device) { remove(from: device) }
        for device in current where !watchedDevices.contains(device) {
            for var address in Self.deviceAddresses {
                AudioObjectAddPropertyListenerBlock(device, &address, listenerQueue, notify)
            }
        }
        watchedDevices = current
    }

    private func remove(from device: AudioDeviceID) {
        // Fails harmlessly for a device that has already gone.
        for var address in Self.deviceAddresses {
            AudioObjectRemovePropertyListenerBlock(device, &address, listenerQueue, notify)
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
#endif
