/// What an X-Air's USB Channel carries (#20), from `/routing/usb/NN` = [source, tap]. Source numbers as read on an
/// XR18 (firmware 1.26): 0-15 Ch01-16, 16-17 AuxL/R (the aux return), 18-25 FX 1-4 L/R, 26-31 Bus 1-6, 32-35
/// Send 1-4, 36-37 main L/R. The tap (AIN, IN, PREEQ, POSTEQ, PRE, POST) doesn't change which channel it is.
enum XAirRouting {
    enum Target: Equatable, Sendable {
        /// Input channel 1-16.
        case channel(Int)
        /// The aux return, named at /rtn/aux.
        case auxReturn
    }

    /// The channel a USB source number carries, or nil for FX, buses, sends and the main mix.
    static func target(ofSource source: Int) -> Target? {
        switch source {
        case 0...15: .channel(source + 1)
        case 16...17: .auxReturn
        default: nil
        }
    }
}
