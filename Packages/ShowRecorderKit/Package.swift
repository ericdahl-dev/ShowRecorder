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
        .testTarget(name: "RecordingTests", dependencies: ["Recording", "AudioIO"]),
    ]
)
