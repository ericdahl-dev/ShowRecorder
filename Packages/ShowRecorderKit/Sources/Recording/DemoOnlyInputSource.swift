import AudioIO
import Foundation

/// The inputs a screenshot build may Arm: only demo inputs (ids starting "demo"), never a microphone, a USB interface
/// or an iPhone's route, so a screenshot run can't record a room (#374). The app uses it when its bundle ID ends in
/// ".screens" (`isScreenshotBuild`); the sequencer Arms only what its source offers.
@MainActor
public struct DemoOnlyInputSource: InputDeviceSource {
    private let source: any InputDeviceSource

    public init(_ source: any InputDeviceSource) {
        self.source = source
    }

    public func devices() -> [DeviceChoice] {
        Self.onlyDemo(source.devices())
    }

    /// The demo inputs among `choices`.
    public static func onlyDemo(_ choices: [DeviceChoice]) -> [DeviceChoice] {
        choices.filter { $0.id.hasPrefix("demo") }
    }

    public func currentRouteDevice(sampleRate: Int?) throws -> any AudioIODevice {
        throw CocoaError(.featureUnsupported)
    }

    /// Whether the running app is the screenshot build, by its bundle ID.
    public static func isScreenshotBuild(bundleID: String? = Bundle.main.bundleIdentifier) -> Bool {
        bundleID?.hasSuffix(".screens") == true
    }
}
