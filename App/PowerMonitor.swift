import Foundation
import Observation
import Recording
#if os(iOS)
import UIKit
#elseif os(macOS)
import IOKit.ps
#endif

/// Reads the battery and thermal state from the system and keeps a `PowerStatus` current, for the status
/// strip. The rules are in `PowerStatus`; this is only the system glue. It lives as long as the app.
@MainActor
@Observable
final class PowerMonitor {
    private(set) var status = PowerStatus(batteryLevel: nil, charging: .unknown, thermal: .nominal)
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var poll: Timer?

    init() {
        var names: [Notification.Name] = [ProcessInfo.thermalStateDidChangeNotification]
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        names += [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification]
        #else
        // macOS has no battery notification without a run loop source; reading every 30 s is plenty.
        poll = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        #endif
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func refresh() {
        let battery = Self.readBattery()
        status = PowerStatus(batteryLevel: battery.level, charging: battery.charging, thermal: Self.readThermal())
    }

    private static func readThermal() -> PowerStatus.Thermal {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .nominal
        }
    }

    #if os(iOS)
    private static func readBattery() -> (level: Double?, charging: PowerStatus.Charging) {
        let device = UIDevice.current
        // -1 means the system can't say (the Simulator).
        let level = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        switch device.batteryState {
        case .charging: return (level, .charging)
        case .full: return (level, .full)
        case .unplugged: return (level, .unplugged)
        default: return (level, .unknown)
        }
    }
    #else
    /// The Mac's internal battery, or nil level on a Mac without one.
    private static func readBattery() -> (level: Double?, charging: PowerStatus.Charging) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (nil, .unknown) }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTransportTypeKey] as? String == kIOPSInternalType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let level = Double(current) / Double(max)
            if description[kIOPSIsChargingKey] as? Bool == true { return (level, .charging) }
            let state = description[kIOPSPowerSourceStateKey] as? String
            return (level, state == kIOPSACPowerValue ? .full : .unplugged)
        }
        return (nil, .unknown)
    }
    #endif
}
