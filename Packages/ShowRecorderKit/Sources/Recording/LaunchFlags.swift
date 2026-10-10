/// Launch flags for screenshots and checks (`-demoRecord`, `-showList` and so on). They work in a Debug build
/// only, so a released app can't be steered by launch arguments.
public enum LaunchFlags {
    public static func isSet(_ flag: String, in arguments: [String] = CommandLine.arguments, isDebugBuild: Bool = Self.isDebugBuild) -> Bool {
        isDebugBuild && arguments.contains(flag)
    }

    public static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
