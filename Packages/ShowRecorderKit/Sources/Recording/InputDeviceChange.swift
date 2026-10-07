import Foundation

/// What the record screen needs to know about one audio input device to decide what to Arm.
public struct InputDeviceInfo: Equatable, Sendable {
    /// Stable across unplug and replug (the Core Audio device UID on macOS).
    public let id: String
    public let name: String
    public let inputChannelCount: Int
    public let sampleRate: Double

    public init(id: String, name: String, inputChannelCount: Int, sampleRate: Double) {
        self.id = id
        self.name = name
        self.inputChannelCount = inputChannelCount
        self.sampleRate = sampleRate
    }
}

/// What to do when the list of audio input devices changes: which device to select, whether to
/// Arm or disarm, whether the running Take must stop, and what to tell the operator.
public struct InputDeviceChange: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        /// Leave the recorder as it is.
        case none
        /// Arm the selected device (disarming whatever was Armed first).
        case arm
        /// Disarm: the Armed device is gone.
        case disarm
    }

    public var selectedID: String?
    public var action: Action
    /// The running Take must be stopped (and its Stems finalized) before acting.
    public var stopsTake: Bool
    public var message: String?

    public init(selectedID: String?, action: Action, stopsTake: Bool, message: String?) {
        self.selectedID = selectedID
        self.action = action
        self.stopsTake = stopsTake
        self.message = message
    }

    /// - Parameters:
    ///   - old: the device list before the change.
    ///   - new: the device list now, in the order it is shown (preferred device first).
    ///   - selectedID: the device chosen in the picker.
    ///   - armed: the device as it was when it was Armed, or nil when nothing is Armed.
    ///   - isRecording: a Take is running.
    public static func decide(
        old: [InputDeviceInfo], new: [InputDeviceInfo],
        selectedID: String?, armed: InputDeviceInfo?, isRecording: Bool
    ) -> InputDeviceChange {
        let newIDs = Set(new.map(\.id))
        let oldIDs = Set(old.map(\.id))
        var change = InputDeviceChange(
            selectedID: selectedID.flatMap { newIDs.contains($0) ? $0 : nil },
            action: .none, stopsTake: false, message: nil)
        var armed = armed
        var isRecording = isRecording

        // The Armed device is gone: disarm, stopping a running Take so its Stems are finalized.
        if let lost = armed, !newIDs.contains(lost.id) {
            change.action = .disarm
            change.stopsTake = isRecording
            change.message = isRecording
                ? "\(lost.name) was disconnected during the Take. Recording stopped and the Stems recorded so far were saved."
                : "\(lost.name) was disconnected, so the recorder is no longer Armed. Reconnect it or choose another input."
            armed = nil
            isRecording = false
        } else if let before = armed, let now = new.first(where: { $0.id == before.id }),
                  now.sampleRate != before.sampleRate || now.inputChannelCount != before.inputChannelCount {
            // Same device, new format: the running audio unit no longer matches it, so re-arm. A
            // Take can't change format part way, so it stops first.
            change.selectedID = now.id
            change.action = .arm
            if isRecording {
                change.stopsTake = true
                let what = now.sampleRate != before.sampleRate
                    ? "changed to \(kilohertz(now.sampleRate)) kHz"
                    : "now sends \(now.inputChannelCount) USB Channels"
                change.message = "\(now.name) \(what) during the Take. Recording stopped and the Stems recorded so far were saved. Press record to start a new Take."
            }
            armed = now
            isRecording = false
        }

        // A Mixer that was just plugged in wins over nothing, or over a device too small to carry
        // it, but never moves a running Take.
        let armedIsUsable = armed.map { $0.inputChannelCount >= Recorder.expectedUSBChannelCount } ?? false
        if !armedIsUsable, !isRecording,
           let full = new.first(where: { !oldIDs.contains($0.id) && $0.inputChannelCount >= Recorder.expectedUSBChannelCount }) {
            change.selectedID = full.id
            change.action = .arm
        }
        return change
    }
}

/// 44100 → "44.1", 48000 → "48".
private func kilohertz(_ rate: Double) -> String {
    String(format: "%g", (rate / 100).rounded() / 10)
}
