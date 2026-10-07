// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShowRecorderKit",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "AudioIO", targets: ["AudioIO"]),
        .library(name: "BroadcastWave", targets: ["BroadcastWave"]),
        .library(name: "Recording", targets: ["Recording"]),
        .library(name: "CoreAudioIO", targets: ["CoreAudioIO"]),
        .library(name: "OSC", targets: ["OSC"]),
        .library(name: "MixerLink", targets: ["MixerLink"]),
    ],
    targets: [
        // The audio I/O boundary and a fake device. No platform audio frameworks.
        .target(name: "AudioIO"),
        // Broadcast WAV Stem files.
        .target(name: "BroadcastWave"),
        // The recorder: Armed state, meters, Shows and Takes. No platform audio frameworks.
        .target(name: "Recording", dependencies: ["AudioIO", "BroadcastWave"]),
        // Core Audio devices on macOS. Empty on other platforms.
        .target(name: "CoreAudioIO", dependencies: ["AudioIO"]),
        // Open Sound Control messages and bundles. Pure encoding, no networking.
        .target(name: "OSC"),
        // The Mixer Link: mixer drivers (X-Air first) over UDP.
        .target(name: "MixerLink", dependencies: ["OSC"]),
        .testTarget(name: "OSCTests", dependencies: ["OSC"]),
        .testTarget(name: "MixerLinkTests", dependencies: ["MixerLink", "OSC"]),
        .testTarget(name: "RecordingTests", dependencies: ["Recording", "AudioIO"]),
        .testTarget(name: "BroadcastWaveTests", dependencies: ["BroadcastWave"]),
    ]
)
