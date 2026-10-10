import Recording

/// Whether a screenshot or check launch flag was given. Debug builds only (the `#if DEBUG` is the app's own, so
/// it follows the app's configuration); `LaunchFlags` in the package holds the rule.
func launchFlag(_ flag: String) -> Bool {
    #if DEBUG
    LaunchFlags.isSet(flag, isDebugBuild: true)
    #else
    LaunchFlags.isSet(flag, isDebugBuild: false)
    #endif
}
