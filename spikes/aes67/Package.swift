// swift-tools-version:5.9
// Throwaway spike for #1235: receive one AES67 stream and record one WAV per channel.
// Not part of the app or the shipping packages.
import PackageDescription

let package = Package(
    name: "AES67Spike",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "AES67Core"),
        .executableTarget(name: "aes67rec", dependencies: ["AES67Core"]),
        .testTarget(name: "AES67CoreTests", dependencies: ["AES67Core"]),
    ]
)
