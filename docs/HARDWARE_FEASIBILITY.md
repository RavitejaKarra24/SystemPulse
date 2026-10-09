# Hardware telemetry feasibility and scope

## Decision

**Feasibility review: completed. Optional GPU/sensor/accessory-battery implementation: not started and deferred from the current release scope.** This is a scope decision, not a claim that no device can expose those readings. Do not represent deferred data with zeroes, sample histories, disabled future modules or permission-triggering probes.

Keep existing public system thermal categories, macOS power-source charge/estimates and Low Power Mode. Keep the existing optional battery-registry details with explicit hardware-dependent provenance; do not present that backend as a general CPU/GPU sensor implementation or a calibrated energy meter. Power now has a native **Sources and limits** disclosure explaining actual collection boundaries without enabling anything.

The remaining planned implementation work is Phase 5 hardening. Phase 4 and earlier phases still have open human/hardware release gates; this review does not close them. Reopening deferred expansion requires a separate documented backend proposal, explicit privacy/permission design and supported-device validation.

## Evidence and method

- Inspected the installed full Xcode macOS 27 SDK headers (the product still targets **macOS 14+**). A declaration in this SDK does not prove availability on macOS 14, live device support, correct units or acceptable energy cost.
- Read official Apple documentation for Metal resources/counter sampling, public thermal state and Bluetooth privacy; read the Bluetooth SIG Battery Service overview.
- Audited current `PowerSampler.swift`, `SystemSampler.swift`, Power views and metadata. No Metal command queue, Bluetooth manager, HID device manager or private sensor client was instantiated. No device enumeration, connection, scan, authorization query/request, hardware manipulation, user-folder scan, notification or real Trash operation was needed for the feasibility review.
- Negative findings mean **no approved stable contract established in the reviewed material**, not an exhaustive proof that no API, driver or vendor-specific implementation exists.

## Support matrix

| Desired information | Verified contract / boundary | Current scope decision |
|---|---|---|
| Internal battery charge/time estimate | IOKit `IOPowerSources` and `IOPSKeys` provide normalized power-source descriptions. These are the existing charge/estimate source; missing/invalid capacity is unavailable. | Retain; never treat unknown as zero, or an estimate as guaranteed runtime. |
| Low Power Mode and system thermal category | Foundation `ProcessInfo.isLowPowerModeEnabled` and `thermalState` are public. Thermal state is a system category, not a Celsius reading or a per-chip temperature. | Retain current diagnostics, insights and thermal alerts. No new temperature inference. |
| Cycle/health/capacity, battery temperature, battery flow and system input | Existing `AppleSmartBattery` registry decoding reads hardware-specific keys. Public IOKit registry-access functions do not turn those fields, their units or their stability into a portable sensor contract. `PowerTelemetryData.SystemPowerIn` is not calibrated wall power. | Retain legacy optional readings with explicit provenance and existing unknown states. Cross-Mac units/accuracy remain unverified; no new generic sensors or energy claim. |
| GPU identity/static Metal capabilities | `MTLDevice` exposes device metadata and capabilities; availability varies by OS and GPU. Unified-memory architecture is not a separate VRAM capacity. Several Intel/topology-oriented properties are deprecated in the macOS 27 SDK as not applicable to Apple Silicon. | Technically a possible future read-only inventory, but not GPU utilization. No new identification-only GPU module just to imply monitoring parity. |
| Total GPU utilization / memory | `currentAllocatedSize` concerns resources allocated by the queried Metal device; `recommendedMaxWorkingSetSize` is an approximation for good performance, not physical total VRAM. Command-buffer times and sampled counters require the app's encoders/passes and supported sampling boundaries. The reviewed APIs do not establish an all-process utilization/total-memory feed. | Defer. Do not label app resource allocations, a working-set recommendation, command timing, or a synthetic workload as whole-machine GPU use. No workload submission solely to manufacture a measurement. |
| CPU/GPU temperatures, fan RPM and chip energy | Public thermal categories provide no such conversion. No approved cross-Intel/Apple-Silicon user-process sensor contract was established. SMC key protocols, driver-specific registry statistics and private IOReport consumption are not made portable by generic public IOKit calls. DriverKit IOReporter declarations are for drivers, not a general monitoring-app feed. | Defer additional sensor backend; no private framework, helper installation, elevation or fan control. Existing battery temperature is separate and hardware-dependent. |
| Classic Bluetooth paired devices | Public `IOBluetoothDevice` declares pairing/connection APIs, but no generic battery-level property in the inspected header. Its `pairedDevices` documentation explicitly describes system-wide devices paired by any user, not a current-user-only list. | Do not enumerate paired identities merely to display missing batteries. Pairing or a baseband connection is not evidence of a battery reading. |
| BLE Battery Service | Bluetooth SIG defines a Battery Service; an individual peripheral must expose an appropriate service/characteristic. Core Bluetooth discovery/connection/read work needs an explicit privacy design, supported devices and asynchronous missing/error/stale semantics. Apple requires `NSBluetoothAlwaysUsageDescription` for Bluetooth-interface use on supported macOS versions. | Defer. No central/peripheral manager, scan, pairing, connection, private Bluetooth preference database, nearby-device history or permission request. A standardized service is not a promise that arbitrary headphones, AirPods, keyboards or mice expose it to this app. |
| Connected HID battery strength | `IOHIDUsageTables.h` declares battery-strength **usages**. That is not a guaranteed percent-valued property on every HID device. The inspected public property-key headers do not establish a generic `BatteryPercent`/`BatteryStrength` registry contract. HID descriptors, values, units/ranges and access differ by device. The SDK's `hidsystem/IOHIDLib.h` warns that listen-event access can be requested on the process's behalf by manager/device Open calls. | Defer. No HID device opening, input report listening, Input Monitoring request or undocumented property shortcut. Any future battery-only HID proposal must first prove its narrow read path and permission behavior; not every property read is asserted to prompt. |

## Implementation and release consequences

- No GPU, sensor or Bluetooth menu metric, topic, preference, alert rule, export field or placeholder button is added.
- **Sources and limits** is explanatory local UI, not a live hardware availability test. “Public macOS APIs” describes provenance, not proof that a current reading exists. “Not collected” is an application scope statement, not “your device has no GPU/accessory.” It performs no I/O and stores no identifiers or preferences.
- Public thermal state must never be converted into a fabricated temperature, fan speed, energy amount or diagnosis.
- Existing registry battery readings remain optional. Hardware-reported input and signed battery flow must not be relabelled as whole-machine measured energy or efficiency. CPU/footprint/wakeup performance probes remain proxies, not joules or battery-life guarantees.
- If expansion is reconsidered: specify exact public contract and units, minimum OS and supported devices; cap polling/retention; distinguish unsupported/denied/disconnected/stale/unknown from observed zero; invalidate work on disable/sleep/quit; omit names/addresses/identifiers from diagnostics; require explicit opt-in before permission-gated actions; use injected clients in ordinary tests. Approve controlled hardware/permission/energy tests separately.
- No version bump is justified merely by research. The **1.6.4/build 14** maintenance package is for the new truthful Power disclosure, not new GPU/sensor/Bluetooth telemetry.

## Sources

Official pages inspected:

1. [MTLDevice.currentAllocatedSize](https://developer.apple.com/documentation/metal/mtldevice/currentallocatedsize) — resource allocation, not an approved whole-system GPU-usage contract.
2. [Sampling GPU data into counter sample buffers](https://developer.apple.com/documentation/metal/sampling-gpu-data-into-counter-sample-buffers) — samples encoded at supported pass/command boundaries, not a passive monitor of every process.
3. [Understanding Metal Performance HUD metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics) — process/device memory and the app's frame/command-buffer GPU times.
4. [ProcessInfo.thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property) — current system thermal category.
5. [NSBluetoothAlwaysUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription) — explicit Bluetooth privacy requirement.
6. [Bluetooth SIG Battery Service](https://www.bluetooth.com/specifications/specs/battery-service/) — a device service, not universal peripheral support.

Reproducible installed-SDK references, relative to `xcrun --sdk macosx --show-sdk-path` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`:

- `System/Library/Frameworks/Metal.framework/Headers/MTLDevice.h`: unified memory, working-set recommendation, allocation and sampling declarations.
- `System/Library/Frameworks/IOBluetooth.framework/Versions/A/Headers/objc/IOBluetoothDevice.h`: public classic APIs and system-wide paired-device scope; no generic battery property found.
- `System/Library/Frameworks/CoreBluetooth.framework/Headers/CBManager.h`: authorization states; do not create a manager as an unsolicited feasibility probe.
- `System/Library/Frameworks/IOKit.framework/Headers/hid/{IOHIDDevice.h,IOHIDDeviceKeys.h,IOHIDKeys.h,IOHIDUsageTables.h}`: property/value APIs versus battery-strength usages.
- `System/Library/Frameworks/IOKit.framework/Headers/hidsystem/IOHIDLib.h`: access-check/request declarations and Open-call permission discussion.
- `System/Library/Frameworks/IOKit.framework/Headers/ps/{IOPowerSources.h,IOPSKeys.h}`: public power-source descriptions (internal battery/UPS contracts are not a general accessory-battery enumeration promise). The documented deciKelvin UPS **command** must not be assumed to define the units of the legacy `AppleSmartBattery.Temperature` field.

The Apple CoreHID URL guessed during research returned 404; it was not used as evidence. Newer CoreHID declarations/documentation also would not establish a macOS 14 backend without availability and permission validation.
