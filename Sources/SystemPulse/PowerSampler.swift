import Foundation
import IOKit
import IOKit.ps

/// Reads battery, adapter, and live power-draw figures from IOKit.
///
/// Two sources are combined: `IOPowerSources` gives the normalized charge and
/// time estimates that macOS itself displays, while the `AppleSmartBattery`
/// registry entry carries the richer detail (cycles, design capacity,
/// temperature, instantaneous wattage) that has no public API.
enum PowerSampler {

    static func sample() -> PowerInfo {
        var info = PowerInfo()
        applyPowerSources(to: &info)
        applySmartBattery(to: &info)
        applyAdapter(to: &info)
        return info
    }

    // MARK: - IOPowerSources

    private static func applyPowerSources(to info: inout PowerInfo) {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            guard desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            info.hasBattery = true

            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            info.chargePercent = max > 0 ? Double(current) / Double(max) * 100 : 0

            info.isCharging = desc[kIOPSIsChargingKey] as? Bool ?? false
            info.isFullyCharged = desc[kIOPSIsChargedKey] as? Bool ?? false
            info.isPluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            // Both estimates use -1 while macOS is still calibrating.
            let minutes = info.isCharging
                ? desc[kIOPSTimeToFullChargeKey] as? Int ?? -1
                : desc[kIOPSTimeToEmptyKey] as? Int ?? -1
            info.timeRemaining = minutes > 0 ? TimeInterval(minutes) * 60 : nil

            if let health = desc[kIOPSBatteryHealthKey] as? String {
                info.condition = health
            }
            break
        }
    }

    // MARK: - AppleSmartBattery registry

    private static func applySmartBattery(to info: inout PowerInfo) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSmartBattery")
        )
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else { return }

        info.hasBattery = true
        info.cycleCount = props["CycleCount"] as? Int ?? 0
        info.designCycleCount = props["DesignCycleCount9C"] as? Int ?? 0

        let design = props["DesignCapacity"] as? Int ?? 0
        // Apple Silicon reports the real mAh figure under the "raw" key; the
        // plain MaxCapacity key is normalized to 100 there.
        let maxCapacity = props["AppleRawMaxCapacity"] as? Int
            ?? props["MaxCapacity"] as? Int ?? 0
        info.designCapacity = design
        info.fullChargeCapacity = maxCapacity
        if design > 0, maxCapacity > 0 {
            info.healthPercent = min(100, Double(maxCapacity) / Double(design) * 100)
        }

        // Reported in hundredths of a degree Celsius.
        if let raw = props["Temperature"] as? Int, raw > 0 {
            info.temperatureC = Double(raw) / 100
        }

        // Amperage is signed: negative while the battery is discharging.
        if let millivolts = props["Voltage"] as? Int,
           let milliamps = props["Amperage"] as? Int {
            info.batteryPowerWatts = Double(millivolts) * Double(milliamps) / 1_000_000
        }

        // Whole-machine draw at the wall, in milliwatts.
        if let telemetry = props["PowerTelemetryData"] as? [String: Any],
           let milliwatts = telemetry["SystemPowerIn"] as? Int, milliwatts > 0 {
            info.systemPowerWatts = Double(milliwatts) / 1000
        }

        if let failure = props["PermanentFailureStatus"] as? Int, failure != 0 {
            info.condition = "Service Battery"
        }
    }

    // MARK: - Adapter

    private static func applyAdapter(to info: inout PowerInfo) {
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue()
                as? [String: Any] else { return }
        info.adapterWatts = details["Watts"] as? Int
        info.adapterName = details["Name"] as? String ?? details["Description"] as? String
        if info.adapterWatts != nil {
            info.isPluggedIn = true
        }
    }
}
