//
//  PowerMonitor.swift
//  Skypane
//

import Foundation
import IOKit.ps

/// Tells whether the Mac is short on power: Low Power Mode is on, or it's running on a battery
/// that's at or below 20%.
final class PowerMonitor {
    /// Battery level at or below which effects pause (when running on battery).
    private let lowBatteryLevel = 0.2

    var isLowOnPower: Bool {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return true
        }
        guard let battery = batteryState(), battery.isOnBattery else { return false }
        return battery.level <= lowBatteryLevel
    }

    /// Whether the Mac is running on its internal battery, and how full it is (0 to 1).
    /// Nil on Macs without a battery.
    private func batteryState() -> (isOnBattery: Bool, level: Double)? {
        guard let powerInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerInfo)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for powerSource in powerSources {
            guard let description = IOPSGetPowerSourceDescription(powerInfo, powerSource)?.takeUnretainedValue() as? [String: Any],
                  let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximumCapacity = description[kIOPSMaxCapacityKey] as? Int,
                  maximumCapacity > 0
            else { continue }

            let powerState = description[kIOPSPowerSourceStateKey] as? String
            return (powerState == kIOPSBatteryPowerValue, Double(currentCapacity) / Double(maximumCapacity))
        }
        return nil
    }
}
