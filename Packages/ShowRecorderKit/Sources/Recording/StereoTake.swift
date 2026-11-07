import Foundation
import TakeFile

/// A 2-input interface's Take as one stereo file (#1088, Eric 2026-11-07): automatic, no setting. When the interface offers
/// exactly 2 USB Channels and both are armed, the Take is one interleaved stereo Broadcast WAV named "Stereo", listed once in
/// `Take.json` as USB Channel 1 with 2 channels. With one of the two armed, or where `StereoPairAvailability` is off, each
/// channel is its own mono Stem as before. Free, like every Stem on the device.
enum StereoTake {
    /// The pair's name: its Source name in the file's bext and in `Take.json`.
    static let name = "Stereo"
    /// The pair's file in the Take folder.
    static let fileName = "Stereo.wav"

    /// Whether a Take pressed now is one stereo file: `channelCount` USB Channels, `recorded` the ones it records.
    static func isStereo(channelCount: Int, recorded: Set<Int>, available: Bool) -> Bool {
        available && channelCount == 2 && recorded.isSuperset(of: [1, 2])
    }

    /// The pair's one entry in `Take.json`, from its left channel's: named "Stereo", in "Stereo.wav", 2 channels.
    static func listing(left: TakeMetadata.USBChannel) -> TakeMetadata.USBChannel {
        var listing = left
        listing.stemFile = fileName
        listing.name = name
        listing.hasMixerName = false
        listing.nameArrivedLate = nil
        listing.channels = 2
        return listing
    }
}
