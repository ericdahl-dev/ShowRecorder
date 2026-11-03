// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShowRecorderKit",
    platforms: [.iOS("26.0"), .macOS("26.0"), .watchOS("26.0")],
    products: [
        .library(name: "AudioIO", targets: ["AudioIO"]),
        .library(name: "BroadcastWave", targets: ["BroadcastWave"]),
        .library(name: "Recording", targets: ["Recording"]),
        .library(name: "CoreAudioIO", targets: ["CoreAudioIO"]),
        .library(name: "OSC", targets: ["OSC"]),
        .library(name: "MixerLink", targets: ["MixerLink"]),
        .library(name: "Destinations", targets: ["Destinations"]),
        .library(name: "ShowReport", targets: ["ShowReport"]),
        .library(name: "TakeActivity", targets: ["TakeActivity"]),
        .library(name: "AutoGain", targets: ["AutoGain"]),
        .library(name: "WatchRemote", targets: ["WatchRemote"]),
        .library(name: "Telemetry", targets: ["Telemetry"]),
        .library(name: "TelemetrySinks", targets: ["TelemetrySinks"]),
    ],
    // Only TelemetrySinks uses these (ADR 0007). Pinned exactly: a new SDK version is its own reviewed change.
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa", exact: "9.32.0"),
        .package(url: "https://github.com/PostHog/posthog-ios", exact: "3.93.3"),
    ],
    targets: [
        // The audio I/O boundary and a fake device. No platform audio frameworks.
        .target(name: "AudioIO"),
        // Broadcast WAV Stem files.
        .target(name: "BroadcastWave"),
        // The recorder: Ready state, meters, Shows and Takes. No platform audio frameworks.
        .target(name: "Recording", dependencies: ["AudioIO", "BroadcastWave", "MixerLink", "ShowReport", "ProjectExport", "Destinations", "TakeFile", "AutoGain", "WatchRemote", "Telemetry"]),
        // A Take's Take.json: what was recorded, its Markers, Gaps, Dropouts and Repairs. Written by Recording,
        // read by Recording and the Show report.
        .target(name: "TakeFile", dependencies: ["Destinations"]),
        // Core Audio devices on macOS. Empty on other platforms.
        .target(name: "CoreAudioIO", dependencies: ["AudioIO"]),
        // Open Sound Control messages and bundles. Pure encoding, no networking.
        .target(name: "OSC"),
        // The Mixer Link: mixer drivers (X-Air first) over UDP.
        .target(name: "MixerLink", dependencies: ["OSC", "AutoGain"]),
        // The Show report (Report.html and Channels.csv) built from a Show folder's Take.json files and Stems.
        .target(name: "ShowReport", dependencies: ["TakeFile", "Destinations", "BroadcastWave"]),
        // DAW projects (Reaper first) from a Show's Takes. Pure rendering, no file access.
        .target(name: "ProjectExport", dependencies: ["MixerLink"]),
        // Where Takes are written: the Drive folder chosen by the operator.
        .target(name: "Destinations"),
        // The running Take as a Live Activity: what it shows and when it starts, updates and ends. Shared by the
        // app and its widget extension, so it depends on nothing else here.
        .target(name: "TakeActivity"),
        // Auto-gain (#151): the closed-loop rule that steps a channel's preamp to a target Average level. Pure logic
        // with no dependencies, so the Mixer drivers that move the preamp and the recorder that runs it can both use it.
        .target(name: "AutoGain"),
        // The Apple Watch remote (#100): what the watch shows and the three commands it sends, and how each side
        // handles them. Pure logic, no WatchConnectivity, so the iPhone app and the watch app share it.
        .target(name: "WatchRemote"),
        // Crash reports and usage (ADR 0007, #1026): the sharing switch, the install ID, the fixed list of events and
        // handled failures, handed to sinks. No SDKs here; the app adds GlitchTip and PostHog as sinks. Never called
        // from the real-time audio path (ADR 0002).
        .target(name: "Telemetry"),
        // The app's Telemetry sinks: crashes and handled failures to GlitchTip (Sentry SDK), usage to PostHog.
        .target(name: "TelemetrySinks", dependencies: [
            "Telemetry",
            .product(name: "Sentry", package: "sentry-cocoa"),
            .product(name: "PostHog", package: "posthog-ios"),
        ]),
        .testTarget(name: "DestinationsTests", dependencies: ["Destinations"]),
        .testTarget(name: "TakeActivityTests", dependencies: ["TakeActivity"]),
        .testTarget(name: "AutoGainTests", dependencies: ["AutoGain"]),
        .testTarget(name: "WatchRemoteTests", dependencies: ["WatchRemote"]),
        .testTarget(name: "TelemetryTests", dependencies: ["Telemetry"]),
        .testTarget(name: "TelemetrySinksTests", dependencies: ["TelemetrySinks", "Telemetry"]),
        .testTarget(name: "OSCTests", dependencies: ["OSC"]),
        .testTarget(name: "MixerLinkTests", dependencies: ["MixerLink", "OSC", "AutoGain"]),
        .testTarget(name: "AudioIOTests", dependencies: ["AudioIO"]),
        .testTarget(name: "RecordingTests", dependencies: ["Recording", "AudioIO", "MixerLink", "Destinations", "AutoGain", "WatchRemote", "Telemetry"]),
        .testTarget(name: "BroadcastWaveTests", dependencies: ["BroadcastWave"]),
        .testTarget(name: "ShowReportTests", dependencies: ["ShowReport", "Recording", "AudioIO", "MixerLink", "BroadcastWave", "ProjectExport"]),
        .testTarget(name: "ProjectExportTests", dependencies: ["ProjectExport", "Recording", "AudioIO", "MixerLink"]),
    ]
)
