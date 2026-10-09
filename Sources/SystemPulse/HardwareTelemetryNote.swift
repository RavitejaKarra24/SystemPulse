/// Describes the application's collection scope, not a live capability probe.
/// This value has no I/O, authorization, identifiers or background work.
enum HardwareTelemetryNote: String, CaseIterable, Identifiable, Sendable {
    case macOSPower
    case batteryDetails
    case thermalState
    case graphics
    case additionalSensors
    case accessoryBatteries

    var id: String { rawValue }

    var title: String {
        switch self {
        case .macOSPower: return "Charge and power settings"
        case .batteryDetails: return "Battery details and input power"
        case .thermalState: return "System thermal state"
        case .graphics: return "GPU usage and memory"
        case .additionalSensors: return "CPU/GPU temperatures and fans"
        case .accessoryBatteries: return "Accessory batteries"
        }
    }

    var scopeLabel: String {
        switch self {
        case .macOSPower, .thermalState: return "Public macOS APIs"
        case .batteryDetails: return "Hardware-dependent"
        case .graphics, .additionalSensors, .accessoryBatteries: return "Not collected"
        }
    }

    var explanation: String {
        switch self {
        case .macOSPower:
            return
                "Charge and time estimates use macOS power sources; Low Power Mode uses ProcessInfo. Missing readings remain unavailable, not zero."
        case .batteryDetails:
            return
                "Cycle count, capacity, battery temperature and power estimates use hardware-specific registry fields. Their availability and meaning can vary. Battery temperature is not CPU/GPU temperature; reported input is not calibrated wall power or energy use."
        case .thermalState:
            return
                "ProcessInfo reports a system thermal category, not degrees Celsius, a per-chip sensor or a diagnosis."
        case .graphics:
            return
                "Metal resource and command-buffer counters do not establish whole-machine GPU usage or total GPU memory. SystemPulse does not collect these metrics."
        case .additionalSensors:
            return
                "No SMC/private sensor backend, helper, privilege escalation or fan control. No temperature or fan reading is inferred from thermal state."
        case .accessoryBatteries:
            return
                "No Bluetooth scanning, pairing or connections, and no Input Monitoring request. Battery reporting varies by device; no accessory charge or connection state is inferred."
        }
    }
}
