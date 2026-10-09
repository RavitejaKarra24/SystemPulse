# Phase 3 performance probes

## Scope

`scripts/measure-performance.sh` runs five **independent release XCTest processes**, each using live read-only telemetry, an isolated preferences suite, a mock login client and a real menu-bar status item. The open scenario hosts Overview in a nonactivating native window; it does not activate the XCTest host. Actual key/occlusion flags are recorded. An AppKit `isVisible` flag alone is not proof of an unoccluded, foreground display. No installed app is replaced; no notification APIs, permission prompts, real notifications, cleanup scans or process actions are invoked.

This measures **process CPU, sampled physical memory footprint and package-idle wakeup accounting**, not energy consumption, joules, battery life or Apple's Energy Impact. Test/AppKit/probe overhead is included. The hosted Overview is not the actual app popover, and notification authorization is simulated. These probes do **not** close the real-app energy or long-session release gate.

## Run

Use a logged-in GUI session. Keep other workloads and the Mac's power source consistent; do not interact with or cover the temporary Overview window. Compilation is outside measurement windows. No prompts are required.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make measure-performance                  # reports in a new private /tmp folder
# Or choose an EXISTING writable output directory outside the repository:
./scripts/measure-performance.sh --output-dir /tmp --duration 60 --warmup 15
# One scenario; 30–3600s measurement, 15–300s warmup:
./scripts/measure-performance.sh --output-dir /tmp --scenario hidden-disk-alert
```

The default matrix takes roughly six minutes plus the initial release build. Each process warms up for 15 seconds, measures for 60 seconds, and samples process counters every five seconds. The script creates a unique private run folder containing per-scenario JSON/logs and toolchain metadata. Existing reports are never overwritten. Ordinary `make check` skips the performance probe.

| Scenario | Work exercised |
|---|---|
| `hidden-default` | Closed panel; default CPU/memory gauges; alerts off |
| `hidden-disk-menu` | Closed panel; additional home-capacity metric, roughly 10-second capacity attempts |
| `hidden-alerts` | Closed panel; all rules enabled; authorized Boolean simulated; alert sink counts events only |
| `hidden-disk-alert` | Closed panel; only disk rule enabled; approximately five-second capacity attempts |
| `open-overview` | Visible native Overview window with live SwiftUI updates/insights; panel-visible process/volume sampling; alerts off |

All scenarios use light appearance, normal 1.5-second polling and a one-second menu renderer. Minimum cadences round to polling passes. A temporary second status item appears if SystemPulse is already running. Private test preferences are removed on normal completion; forced termination can leave a disposable UUID suite. The shell harness removes its private build/staging directories on exit but retains completed reports/logs.

## Interpretation

- CPU = delta of kernel-reported user + system Mach ticks, converted with the measured `mach_timebase_info` ratio to nanoseconds, divided by monotonic elapsed seconds. The raw counters and timebase are recorded; unavailable/overflow conversions stay null. **100% means one core**, not the entire machine.
- Footprint extrema are sampled every five seconds, not continuous peaks or a leak test. Fresh processes prevent earlier scenarios from retaining SwiftUI/store caches in later measurements.
- Package-idle wakeups are not all interrupts or timer firings. Failed/unsupported or all-zero accounting is explicitly `null`, never claimed as measured zero.
- Reports include sample errors, actual durations, renderer ticks, process refresh counts and caveats. A successful run means the probe executed, **not** that a performance budget passed.
- Compare repeated like-for-like runs on the same hardware/OS/toolchain. Do not compare these process footprints directly with the packaged app, or infer the isolated cost of disk alerts from one noisy run.
- No machine-independent pass/fail budget is imposed. Real-app Instruments Energy Log/Time Profiler, closed/open settings and permission transitions, multiple power states, and a bounded 24-hour soak remain release checks.

## Installed-app observer (separate from XCTest)

`scripts/measure-running-app.sh` observes an **explicit existing SystemPulse PID** using a small compiled external Swift sampler. It neither launches nor controls the target and never reads/writes its preferences, asks for notification/accessibility permissions, sends notifications or changes UI. Process name and app executable shape are checked before and throughout measurement; start identity guards against PID reuse/relaunch. CPU/timebase conversion and footprint/wakeup semantics match the harness above, but the counters belong to the **actual application process**, not XCTest.

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# Inspect pgrep output and choose ONE PID; do not assume the panel or settings state.
pgrep -x SystemPulse
./scripts/measure-running-app.sh --pid YOUR_PID --output-dir /tmp --duration 60 --warmup 15 --label current-session
```

The directory must already exist outside the repository. Compilation finishes before warmup; a unique private report/log folder is retained. No raw executable/user path is saved in report JSON. UI visibility and alert configuration are **unverified**; an optional label is a user declaration, not detection. Target exit/reuse or failed required resource queries abort the report rather than mixing processes. Short process measurements still do not establish energy consumption, leak freedom, foreground rendering or a release budget.

## Current evidence

### Approved 1.7.1 packaged-app observations — completed short runs

User approved non-destructive UI and short-run resource checks on the current **1.7.1/build 16** app. Normal 1.5-second polling, CPU/memory gauges and alerts off were inspected without changing preferences. Separate external observers completed:

| Scenario | Warmup / actual measured duration | One-core CPU | Sampled footprint | Package-idle wakeups |
|---|---|---:|---:|---:|
| Closed default before UI interactions | 30.005s / 180.005s | 1.318% | 21.267–21.313 MiB | 62; 0.344/s |
| Overview after process/chart/Settings interactions | 15.005s / 60.001s | 3.617% | 104.595–154.923 MiB | 30; 0.500/s |

Companion context checks sampled matching version/control preferences and alerts-off state: 44 closed-context checks; 17 Overview checks with owned onscreen window, exposed Overview/popover and active/frontmost application. Context is sampled, not continuous or proof of native key/unoccluded rendering. The first helper did not retain individual window-query error statuses; its closed classification is best-effort. Overview helper retains missing window/AX readings as nullable. External sampler JSON still correctly states that the sampler itself does not verify UI/configuration; original reports are unchanged.

Same process, different durations and prior UI/cache histories; **not a causal closed/open comparison, leak finding or historical-version improvement**. Footprint extrema are sampled and observer/AX/host workload applies. **Energy, an agreed release budget and a real 24-hour/sleep-wake soak remain unverified.** Full scope/results: [LIVE_VALIDATION_1.7.1.md](LIVE_VALIDATION_1.7.1.md).

Raw [closed process](performance/installed-app-1.7.1-closed-default.json)/[context](performance/installed-app-1.7.1-closed-default-context.json), [Overview process](performance/installed-app-1.7.1-overview.json)/[context](performance/installed-app-1.7.1-overview-context.json). No app launch/kill/rebuild, permission request, notification, scan, data move or configuration change during observation.

### Historical source milestones and probe limitations

The 1.6.0/build 10, 1.6.1/build 11, 1.6.2/build 12 and 1.6.3/build 13 storage, plus 1.6.4/build 14 hardware-scope milestones did **not** rerun these opt-in probes: reports below remain 1.5.x evidence. The explorer's 100-file/256-directory caps and 64-scope navigation tests establish retention bounds, not actual large-folder CPU/footprint/energy or native Quick Look performance. The 50-location cleanup-queue cap, detached sequential client tests and mocked normal-Quit drain establish safety/retention behavior, not actual Trash latency, foreground responsiveness or energy. Cancellation/safety tests and builds do not close the energy or long-session scan gates. The static hardware-source disclosure adds no new sampler or permission path; it does not establish an efficiency improvement. A controlled live scan-performance run still requires an explicitly approved scope and workload.

The **1.7.0/build 15** native-accessibility milestone also does **not** rerun these probes. Injected announcement/status tests and native appearance/focus-outline captures establish source behavior/rendering, not actual VoiceOver, packaged-app interaction, energy or long-session efficiency. No additional telemetry timer was added; that is not a measured CPU/footprint improvement claim.

The **1.7.1/build 16** bounded-resource milestone adds a 512-entry icon LRU, weak ownership for a blocked process worker and a single lifecycle authorization-refresh waiter. Synthetic churn, blocked-callback and offscreen native-editor regressions are [source/retention evidence](LONG_SESSION_HARDENING.md), **not** a rerun of these probes or a packaged-app footprint/energy/24-hour result. Entry count is not an NSImage byte budget; cancellation does not interrupt a synchronous OS call. All historical reports below remain unchanged. The subsequent approved 1.7.1 external observations above add current process/context evidence, without rerunning the XCTest matrix or closing energy/soak gates.

### Installed application (not XCTest)

A 60.003-second read-only observation of the running **1.5.1 (build 8)** app completed, after 15-second warmup: **2.250% one-core CPU**, **47.72–98.16 MiB** sampled footprint, and **13 package-idle wakeups** (0.217/s). UI visibility and alert configuration were not inspected or changed. This is an unclassified current-session observation, not a closed-panel baseline, foreground test, energy measurement or controlled comparison. The footprint range is not a leak finding. Raw report: [`installed-app-1.5.1.json`](performance/installed-app-1.5.1.json).

The installed **1.5.2 (build 9)** lifecycle app was separately observed for **60.001 seconds**, after 15-second warmup: **1.003% one-core CPU**, **18.70–18.91 MiB** sampled footprint, **5 package-idle wakeups** (0.083/s). Raw report: [`installed-app-1.5.2.json`](performance/installed-app-1.5.2.json). This preceded the final removal of baseline CPU zeroes from the legacy sparkline and the Overview scope-label correction from “startup volume” to “home volume”; it is an observation of that earlier same-version binary, not exact final-archive performance verification. Both runs had **unverified** UI/configuration and different process sessions: do **not** infer an improvement, controlled regression result or causal alert/UI cost from their differences.

The observer is ready for repeated user-declared scenarios. Actual sleep, foreground UI, real alert delivery, Energy Log and long-session tests remain pending.

### Earlier isolated harness runs (1.5.1-era source)

Four hidden scenarios completed with 15-second warmup and 60-second measurements on this Apple Silicon Mac (10 logical CPUs, macOS 27.0.1). The initial activating XCTest-host Overview attempt failed during warmup with a native `InvalidTransition` error and produced no measurement. A separate nonactivating native-window probe completed after preserving AppKit lifecycle events and disabling input through native window properties. Its window was marked visible, but key and unoccluded flags were **false**: it measures the hosted panel-visible code path, **not verified foreground rendering or the real popover**. The earlier failure is not an application performance result.

| Scenario | CPU % of one core | Sampled footprint (MiB) | Package-idle wakeups/s |
|---|---:|---:|---:|
| hidden-default | 0.912 | 16.47–16.77 | 1.016 |
| hidden-disk-menu | 1.031 | 16.47–16.64 | unavailable |
| hidden-alerts | 1.089 | 16.49–16.64 | unavailable |
| hidden-disk-alert | 1.140 | 16.49–16.70 | unavailable |
| open-overview (hosted; unoccluded=false) | 2.685 | 38.77–89.30 | unavailable |

The hosted Overview run observed 60 renderer ticks, 15 process passes and zero alert-sink events. It is not comparable to an interactive foreground popover, and the short-lived footprint swing is not a leak finding. Those historical runs did not establish packaged-app energy or unoccluded rendering. Current 1.7.1 short observations are documented above; energy, continuous unocclusion and real long-session sign-off remain open.

Each hidden run observed 60 menu-render ticks, four process passes and zero alert-sink events. These single exploratory runs include normal desktop activity and test-harness overhead; they do not isolate causal costs or establish a budget. Null wakeup accounting is not measured zero. Raw JSON is retained in [`docs/performance/`](performance/) with timebase, counter samples and caveats. The matrix used Apple Swift 6.4 in package Swift 5 mode, with a measured CPU timebase of 125/3; results are machine-specific. Human interaction and real notification delivery are separate checks in [VALIDATION.md](VALIDATION.md).
