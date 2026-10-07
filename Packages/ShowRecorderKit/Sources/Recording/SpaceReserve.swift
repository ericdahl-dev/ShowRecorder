import BroadcastWave

/// How much space a Destination keeps free: 60 s of audio for every channel. A Copy that is short stops
/// cleanly while another has room; when the last healthy one is short the Take ends; and Repair never
/// grows a Copy past it.
struct SpaceReserve {
    static let seconds = 60

    let bytes: Int64

    init(channelCount: Int, sampleRate: Int) {
        bytes = Int64(Self.seconds * channelCount * sampleRate * StemWriter.bytesPerSample)
    }

    /// Whether `free` bytes leaves less than the reserve.
    func isLow(free: Int64) -> Bool { free < bytes }

    /// Whether writing `extra` more bytes into `free` would take the Destination below the reserve.
    /// Writing nothing never breaches it.
    func wouldBreach(free: Int64, adding extra: Int64) -> Bool { extra > 0 && free - extra < bytes }
}
