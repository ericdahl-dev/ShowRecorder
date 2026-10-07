import AudioIO
import Recording
import SwiftUI
#if os(macOS)
import CoreAudioIO
#endif

/// The record screen. While it is showing, the recorder is Armed on the chosen device.
struct RecordScreen: View {
    @State private var model = RecordScreenModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let error = model.armError {
                Banner(text: error, systemImage: "exclamationmark.octagon.fill", tint: .red)
            }
            if model.recorder.hasTooFewUSBChannels {
                Banner(
                    text: "This device sends \(model.usbChannelSummary). The XR18 and MR18 send 18, so some of the Mixer won't be recorded.",
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .orange)
            }
            MeterGrid(levels: model.levels)
            Spacer(minLength: 0)
        }
        .padding()
        .task { await model.runWhileVisible() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Input", selection: $model.selectedDeviceID) {
                if model.devices.isEmpty {
                    Text("No audio input").tag(String?.none)
                }
                ForEach(model.devices, id: \.id) { device in
                    Text(device.name).tag(Optional(device.id))
                }
            }
            .onChange(of: model.selectedDeviceID) { model.armSelectedDevice() }

            HStack(spacing: 6) {
                Circle()
                    .fill(model.recorder.isArmed ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(model.recorder.isArmed ? "Armed" : "Not armed")
                Text("·").foregroundStyle(.secondary)
                Text(model.usbChannelSummary)
                    .monospacedDigit()
            }
            .font(.subheadline)
        }
    }
}

/// One choosable audio device.
struct DeviceChoice: Identifiable {
    let id: String
    let name: String
    let make: () -> any AudioIODevice
}

@MainActor
@Observable
final class RecordScreenModel {
    let recorder = Recorder()
    private(set) var devices: [DeviceChoice] = []
    var selectedDeviceID: String?
    private(set) var levels: [Float] = []
    private(set) var armError: String?

    init() {
        devices = Self.availableDevices()
        selectedDeviceID = devices.first?.id
    }

    var usbChannelSummary: String {
        let count = recorder.usbChannelCount
        return count == 1 ? "1 USB Channel" : "\(count) USB Channels"
    }

    /// Arms the selected device, polls meters at about 30 Hz, and disarms when the screen goes away.
    func runWhileVisible() async {
        armSelectedDevice()
        defer { recorder.disarm() }
        while !Task.isCancelled {
            let fresh = recorder.takeMeterLevels()
            levels = fresh.enumerated().map { index, level in
                // Fall back gently so short peaks stay visible.
                max(level, (levels.indices.contains(index) ? levels[index] : 0) * 0.85)
            }
            try? await Task.sleep(for: .milliseconds(33))
        }
    }

    func armSelectedDevice() {
        guard let choice = devices.first(where: { $0.id == selectedDeviceID }) else {
            recorder.disarm()
            return
        }
        do {
            try recorder.arm(choice.make())
            armError = nil
        } catch {
            armError = "Couldn't start \(choice.name): \(error)"
        }
        levels = Array(repeating: 0, count: recorder.usbChannelCount)
    }

    private static func availableDevices() -> [DeviceChoice] {
        var choices: [DeviceChoice] = []
        #if os(macOS)
        // A device that can carry a whole XR18 comes first, then the system default input.
        let defaultID = CoreAudioDevice.defaultInputDeviceID()
        let devices = CoreAudioDevice.inputDevices().sorted { a, b in
            let aFull = a.inputChannelCount >= Recorder.expectedUSBChannelCount
            let bFull = b.inputChannelCount >= Recorder.expectedUSBChannelCount
            if aFull != bFull { return aFull }
            return a.id == defaultID && b.id != defaultID
        }
        for device in devices {
            choices.append(DeviceChoice(
                id: "coreaudio-\(device.id)",
                name: "\(device.name) (\(device.inputChannelCount) in)",
                make: { device }))
        }
        #endif
        #if DEBUG
        choices.append(DeviceChoice(id: "demo", name: "Demo signal (18 channels)", make: { DemoAudioDevice() }))
        #endif
        return choices
    }
}

struct Banner: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(tint)
    }
}

#Preview {
    RecordScreen()
}
