/// Where auto-gain (#155) is offered: every build, once it passed the live XR18 test with Eric. (v1.1.1 hid it outside
/// Debug builds until then.) Clip protection keeps its own rule (`ClipProtectionSetting.isOffered`).
public enum AutoGainAvailability {
    public static func isAvailable(isDebugBuild: Bool = LaunchFlags.isDebugBuild) -> Bool {
        true
    }
}
