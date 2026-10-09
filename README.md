# SystemPulse

A menu-bar macOS utility that shows what your computer is doing right now: CPU,
memory, network, disk space, battery, and which apps are using the most of each.

[View the interface walkthrough](organized%20view.webm)

SystemPulse has **no Dock icon**. Monitoring lives in a menu-bar panel, with a
separate native Settings window. After launch, look for its live
gauge in the **menu bar** — the strip at the top right of the screen, next to
the clock and Wi-Fi.

---

## Build 18 candidate

The source/package candidate is **1.7.2 (build 18)**; the installed app remains
build 17. Build 18 fixes incomplete decimal commits and preserves a numeric
draft's parsing locale across locale changes. It adds numeric/keyboard regressions
and stronger [read-only archive/parity checks](docs/ARTIFACT_VERIFICATION.md).
[Implementation and validation results](docs/TODO_IMPLEMENTATION_2026-10-09.md)
are separate from the installed build 17 evidence below. No accessibility features
were added; native UI/resource/distribution gates and final sign-off remain pending.

## Revamp roadmap

[Phased plan and feature statuses](ROADMAP.md) · [Design direction](DESIGN.md) · [Validation and remaining checks](docs/VALIDATION.md) · [Hardware/API scope](docs/HARDWARE_FEASIBILITY.md) · [Resource hardening](docs/LONG_SESSION_HARDENING.md) · [Current release validation](docs/RELEASE_VALIDATION_2026-10-09.md) · [Release gates](docs/RELEASE_CHECKLIST.md)

Phase 1 introduces a neutral, system-appearance interface, an overview dashboard,
expanded process search, swap usage, and safer actions. Phase 2 adds timestamped
history, interface details, volume selection, private exports, and power diagnostics.
Phase 3 adds opt-in local alerts, native Settings, ordered menu-bar metrics and
measurement-based insights. Phase 4 delivers reviewed cleanup, cancellable scans,
folder drill-down and native Quick Look. **1.7.1 (build 16)** continues source
hardening with a bounded process-icon cache, weak process-worker ownership,
one lifecycle authorization-refresh waiter and isolated native editing regressions;
these are not measured-energy or 24-hour soak results. Power’s **Sources and limits** disclosure
from 1.6.4 remains; optional GPU usage, extra sensors/fans and accessory batteries
are deferred, not exposed as fake readings. **1.7.2 (build 17)** removes explicit
VoiceOver announcements, custom accessibility semantics and accessibility display
adaptations at the owner's request. Ordinary keyboard controls, focus indicators,
tooltips and persistent failure feedback remain. Native macOS controls still have
their platform behavior. Accessibility validation is withdrawn from this release's
scope. Physical keyboard/hardware, measured-energy, soak and distribution gates
remain open. **Final release sign-off is pending.** Build 17 has 385 passing tests,
one opt-in skip and zero failures; three installer safety regressions pass separately.
Installed/dist/extracted archive parity passed. A fresh-closed 60-second sample
passed the accepted closed limits at **0.95% one-core CPU / maximum 17.5 MiB**;
visibility/settings were declared, not attested by the observer. It is not energy,
post-activity or soak evidence. The **24-hour observation was CANCELLED** at the
owner's stop request, not completed. Remaining work is tracked in
[todo.md](todo.md) and [ROADMAP.md](ROADMAP.md), not exposed as non-working controls.

## Features

| Area | What it shows |
|---|---|
| Menu bar | Choose/reorder CPU, memory, network, home-volume disk and battery; gauges, compact, detailed or icon-only styles |
| Overview | Live CPU, memory, network, storage and power summaries; jump into any topic |
| CPU | Timestamped 5m/1h/24h history, per-core use, and the processes working hardest |
| Memory | Usage breakdown, swap used, estimated pressure, and the biggest consumers |
| Network | Aggregate or selected-interface rates/session totals, local IPv4/IPv6 and link status |
| Disk | Mounted-volume capacity, all-device I/O history, read-only folder explorer and explicitly reviewed home-cache cleanup queue |
| Power | Charge, estimates, hardware-dependent battery details, Low Power Mode, charging explanations and collection-source/limit disclosure |
| Diagnostics | User-confirmed local JSON/CSV export with raw units and timestamped history; no private identifiers |
| Processes | Search by name, PID, bundle or path; show all groups; confirmed force quit, with system/self protection |
| Settings | Appearance, refresh rate, visible modules, menu-bar order, insights, alert rules and login status |
| Alerts | Opt-in sustained CPU, estimated memory headroom, home-volume disk, battery and thermal rules; silent local notifications |
| Insights | Bounded, read-only observations with measured values, thresholds and expandable evidence |

## Requirements

- macOS 14.0 or later
- Xcode Command Line Tools
- Git

SystemPulse does not upload or send its measurements to a service. Standard
metrics need no additional permissions; protected folders may be unavailable to
the disk scan, and Launch at Login may need approval in System Settings. Exporting
diagnostics, quitting a process or moving cache files to the Trash happens only
after your action. Alerts are off by default; only explicitly enabling alerts
or choosing Enable Notifications can request notification permission.

## Install

```bash
xcode-select --install  # only if `swift --version` fails
git clone https://github.com/RavitejaKarra24/SystemPulse.git
cd SystemPulse
./install.sh
```

`install.sh` checks that Swift is available, builds a release binary, assembles
and ad-hoc signs a real `.app`, validates it, replaces
`~/Applications/SystemPulse.app`, verifies the installed signature, and opens the
app. Quit SystemPulse normally and wait for any cleanup to finish before updating;
installation refuses to replace a running app or an incomplete source bundle.
No `sudo`. Quarantine attributes are preserved so installation does not bypass
Gatekeeper. A freshly compiled local bundle ordinarily has no quarantine attribute.

Inspect `install.sh` before running it if you want to see every system change.

### Optional: prebuilt zip

If you cannot build from source, [download SystemPulse.zip](https://github.com/RavitejaKarra24/SystemPulse/raw/main/SystemPulse.zip)
(~2.2 MB; the current archive is Apple Silicon/arm64, not universal). Intel users
should build from source. Unzip it and move `SystemPulse.app` into **Applications**.
The app is ad-hoc signed, not notarized; downloaded/quarantined copies can be
blocked by Gatekeeper. If macOS offers it, review System Settings > Privacy &
Security > Security > **Open Anyway** before deciding whether to allow it.
Gatekeeper assessment rejected the local bundle; a real downloaded/quarantined
archive on a clean account or another Mac remains unverified. Do not strip
quarantine or treat signature/parity checks as trusted-distribution approval.
Building with `./install.sh` is the path this project supports.

## First launch

Click the SystemPulse icon in the menu bar to open the panel. If you can't find
it, the menu bar may be full; quit another menu-bar app or temporarily hide
other items.

## Launch, update, and uninstall

```bash
# Launch
open "$HOME/Applications/SystemPulse.app"

# Update from the cloned project
git pull --ff-only
./install.sh

# Uninstall: choose Quit SystemPulse normally first and wait for cleanup to finish.
# Then move ~/Applications/SystemPulse.app to Trash in Finder.
```

A second launch does not require rebuilding. `make build`, `make bundle`,
`make test`, `make zip`, and `./install.sh` all replace
`~/Applications/SystemPulse.app` with the bundle they just built, after the app
has quit normally. To assemble a bundle without installation, use
`SKIP_LOCAL_INSTALL=1 ./scripts/build-app.sh`.

## Using it

- **Click** the menu bar icon to open the panel; click anywhere else to close it.
- **Inspect charts:** choose **5m, 1h or 24h**, hover for an actual timestamp, or focus a chart and use **←/→** to inspect observations. **Pause** freezes only that chart; sampling continues. Longer ranges show sample-weighted bucket means, not original peaks. Process-detail charts retain their 20/60-sample controls. History starts at launch, stays in memory and is not invented to fill a selected window.
- **Overview:** the starting page shows current metrics and signals; click a tile for details. Local insights explain available observations; **Show evidence** expands thresholds and caveats. They do not change your system or declare it healthy when readings are missing.
- **Copy a snapshot:** click the copy icon beside **Live** or press **⌘⇧C** for a text summary of current system metrics.
- **Export diagnostics:** click the share icon, choose JSON or CSV, then confirm a save location. Exports contain latest-known readings and up to five minutes of CPU, memory, aggregate network and power history. Cancel writes nothing; errors are reported. No process names, paths, volume names/IDs, addresses or device identifiers are included.
- **Network selection:** select a link, or click its compact row, for that page's rates, totals, addresses and chart. Selected-link history starts when selected. Overview, menu bar and exports keep aggregate network values. Active means a local link, not Internet reachability; SSID is not collected.
- **Volume selection:** change the monitored volume on Disk. Capacity refreshes while the panel is open; removal falls back to the home volume. Capacity is not summed across shared APFS volumes. Selection does not redirect cleanup scans; disk activity remains all-device.
- **Scroll the panel** for additional details. The header and topic navigation stay in place as pages crossfade.
- **Bare number keys 1 to 5** switch between enabled CPU, Memory, Network, Disk, and Power modules; **0** returns to Overview. Hidden modules cannot be opened by these shortcuts. Editing/selecting native text and command/control/option/shift chords are left alone. Topic buttons remain available.
- **Search processes:** enter a name, PID, executable path or bundle identifier; **Show all** reveals groups beyond the top 16.
- **Cleanup:** scan results are locations to review, not a promise that everything can be deleted. **Cancel** stops after the current filesystem call returns; **Scan again** becomes available once the worker exits, never overlapping another scan. Stopped scans and scans with unmeasured locations retain partial results as read-only, with a skipped-location count. A complete rescan is required before cleanup. Cleanup progress counts planned locations, not bytes or time remaining; selected-folder scans use an indeterminate indicator. Non-cache application data stays read-only; Trash actions ask for confirmation. Scope remains known locations in your home folder; the monitored-volume picker does not redirect it.
- **Reviewed cleanup queue:** after a complete home-cleanup scan, use the **+** beside an eligible cache or **Add to Cleanup Queue** in its context menu/detail. Up to **50 non-overlapping locations** are retained in this session only. **Review Queue…** opens one retained native window with every path, logical size and safety note; **Move Reviewed Items to Trash…** then requires an explicit final confirmation. Nothing moves when selecting, reviewing or cancelling. Moves run sequentially off the UI thread, validate each path again, and report moved/failed/not-attempted outcomes. **Stop** finishes the current OS call and skips the rest; normal Quit waits for that call, while force quit/crashes cannot guarantee a recorded result. Failed/skipped items need a new review to retry. New scans invalidate queues and old single/batch confirmations. Selected-folder and partial scans never authorize cleanup. No permanent deletion, elevation or automatic Undo; restore through Finder’s **Put Back** where available. Logical totals are not guaranteed recovered space.
- **Folder inventory:** choose **Disk → Choose Folder…**, then confirm **Scan Folder** in the native chooser. Hidden/package files are measured; small or empty folders are not hidden. The chosen scope is session-only and never added to diagnostics. Folder scans are always read-only—even if the chosen folder is an eligible cache. **Scan again** keeps that folder; **Cleanup locations** explicitly returns to the known home-folder scan. Invalid/unavailable or symlinked roots are not reported as empty. The filesystem root `/` is refused. macOS controls native chooser history; SystemPulse does not save the selected scope.
- **Folder explorer:** after a selected-folder scan, browse up to **100 largest measured files** and **256 discovered immediate folders**, sorted by logical size. The folder list may omit later-discovered children (the count is shown); it is not guaranteed to contain the globally largest folders. Search names/paths and filter Files/Folders within these retained rows only. Select a row, then **Space / Quick Look** previews it; **Return / Scan Folder** rescans a directory. **Back** rescans the parent without leaving the originally selected root; depth is bounded at 64 scopes. File actions revalidate current scope, availability/type and symlink containment; changing files are not atomic snapshots. No Trash actions exist in the explorer. Optional file-allocated bytes are not exclusive/recoverable space; clones, hard links, compression and sparse files affect accounting. Quick Look uses macOS preview providers and may fetch locally referenced cloud content only after your preview action.
- **Hardware sources and limits:** expand this disclosure on Power to distinguish public charge/Low Power Mode/thermal APIs from optional battery-registry details. Battery temperature is not CPU/GPU temperature; hardware-reported input is not calibrated wall power or measured energy. GPU use/total memory, extra CPU/GPU sensors/fans and accessory batteries are **not collected**. No Bluetooth scan/connection or Input Monitoring request is added. [Feasibility evidence and deferred scope](docs/HARDWARE_FEASIBILITY.md).
- **Bare Esc** clears inspection when a chart is focused; elsewhere it goes back a level when not editing/selecting text. **⌘F** focuses search on top-level CPU/Memory only. Native dialogs and Settings numeric drafts retain their own Cancel/Escape behavior.
- **Destructive confirmation defaults:** Force Quit and single/batch Trash alerts assign Return to **Cancel**, with no destructive default shortcut. Approval remains an explicit reviewed action; actual native Cancel/Escape/Return behavior is a pending human validation gate.
- **Action feedback:** failure messages remain readable, selectable and scrollable until **Dismiss** or a newer failure. Routine success/background statuses do not erase an unread failure and are not replayed later. Fresh successes remain transient.
- **Settings:** use the header gear, **⌘,**, or right-click → **Settings…**. General controls appearance, refresh rate, visible modules, insights and login. Menu Bar chooses and reorders metrics; disk describes the home volume and network stays aggregate, regardless of page selection. Icon Only hides numeric readings.
- **Alerts:** explicitly enable alerts in Settings and authorize notifications. Each rule has its own threshold, sustained duration (at least 30 seconds) and cooldown (at least 15 minutes). Recovery is required before another alert for the same breach; cached, missing and gapped readings do not establish sustained time. Battery rules require valid charge while on battery. Memory uses estimated free + cached headroom, not OS memory pressure. Numeric edits save on Return or when leaving the field; invalid values stay unsaved with range feedback, and Escape cancels editing. Brief opt-outs, rule edits and permission revocation invalidate earlier evidence/queued events. Stale readings and delayed notification queries cannot create a wake-up alert. Delivery errors remain visible in Settings; there is no automatic remediation.
- **Right-click** the menu bar icon for quick style/rate/network/login controls and Quit.

## Privacy

SystemPulse reads counters and local interface/volume metadata on your Mac.
**Nothing is uploaded or sent to a service.** History is bounded and in memory;
there are no public-IP lookups, SSID queries or Location Services requests.
Diagnostics are written only after you select and confirm a local destination.
The export schema excludes private identities, addresses and paths. Saving into
a synced or network-mounted folder follows that destination's sync/network behavior.
Local notifications contain only aggregate measurements, never process names,
paths or device identifiers. macOS controls notification visibility and delivery;
Focus settings or denied permission may suppress banners.

## Troubleshooting

- **I can't find the app after opening it.** It has no Dock icon by design. Look
  in the menu bar at the top right of the screen.
- **The disk scan seems slow.** It walks common cache folders in the background
  and fills in as it goes; you can keep using the rest of the app meanwhile.
  Cancel requests a cooperative stop, not an interruption of a blocked OS call.
  A partial/stopped scan cannot authorize cleanup.
- **Numbers freeze or the panel looks stale.** Right-click the menu bar icon,
  choose Quit, and open SystemPulse again:
  `open "$HOME/Applications/SystemPulse.app"`
- **A prebuilt zip said it was blocked.** That is Gatekeeper, not a broken
  download. Use **Open Anyway** as described above, or install from source.

---

# For developers

## Everyday commands

```bash
make run         # Run from SwiftPM during development
make build       # Assemble dist/SystemPulse.app and install it to ~/Applications
make test        # Build, install, and validate both copies
make unit-test   # Deterministic telemetry/action/search and appearance-render tests
make check       # Unit tests and warnings-as-errors debug build
make lint        # Swift formatting/style checks
make format      # Apply the standard Swift formatter
make measure-performance # Opt-in release CPU/footprint/wakeup probes (~6 min), no permissions
make bundle      # Same as make build
make zip         # Build, install, archive, unpack, and re-verify SystemPulse.zip
make verify-zip  # Check the committed zip unpacks, verifies, and isn't stale
make install     # Build, install to ~/Applications, and launch
make clean       # Remove .build and dist (does not uninstall ~/Applications)
```

Every invocation of `scripts/build-app.sh` also updates
`~/Applications/SystemPulse.app` unless `SKIP_LOCAL_INSTALL=1` is set. Installation
requires SystemPulse to be stopped; it never sends a termination signal. Run
`make install-safety-test` for the isolated installer refusal regressions.

If the installed Command Line Tools SDK reports a missing `SwiftUIMacros` plugin,
use the full Xcode toolchain without changing the global developer selection:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make check
```

Generate deterministic UI previews (not live-data screenshots) with:

```bash
SYSTEMPULSE_SCREENSHOT_DIR=/tmp/systempulse-previews make unit-test
```

## Performance probes

[Probe method, scope and current measurements](docs/PERFORMANCE.md).
`make measure-performance` runs separate release test processes for closed-panel
baseline, disk menu, enabled alerts, disk alerts, and live Overview. It uses
isolated preferences and simulated authorization; it never requests permission
or sends notifications. Results include CPU, sampled footprint and optional
package-idle wakeup counters, **not** energy/joules or an app efficiency guarantee.
A separate `scripts/measure-running-app.sh --pid PID --output-dir /tmp`
observes an already-running packaged SystemPulse process without changing its
configuration or UI; visibility and alert state remain unverified by the observer.
It supports 30–86,400-second measurements, but the session's 24-hour run was
cancelled. See the performance document for the build 17 fresh-closed sample and
its limitations. Real-app energy profiling and long-session checks remain open.

## Distribution model

SystemPulse is **source-distributed**. The supported install path is
`./install.sh` to `~/Applications`. The app is ad-hoc signed, not notarized —
notarization needs a paid Apple Developer membership, which this project does
not have.

The committed `SystemPulse.zip` is an optional convenience for people who cannot
build. Downloaded copies may be blocked by Gatekeeper; clean-account download/upgrade
behavior is still a release gate. Please don't add
`notarytool`/`stapler` steps that cannot actually run in this repo's CI.

Practical consequences:

- Use the same bundle identifier (`local.systempulse.monitor`) and install path
  (`~/Applications/SystemPulse.app`) on every build.
- **Regenerate the zip in the same commit as any user-facing change**, and bump
  `CFBundleShortVersionString` in `Resources/Info.plist` while you're there. Git
  will not warn you that a committed build artifact is stale.
- Archiving uses `ditto -c -k --keepParent`, never `zip`. The `zip` command
  drops extended attributes and symlinks, which invalidates the signature and
  produces an app that silently refuses to launch on Apple silicon.
- Ad-hoc signatures change between builds, so if the app ever needs TCC
  permissions, users would be re-prompted after each update.
- Test the real download path from GitHub on another Mac or a fresh user
  account if you change the zip. A freshly compiled local build ordinarily has
  no quarantine attribute and does not reproduce what downloaded zip users see.

## Layout

| Path | Responsibility |
|---|---|
| `Sources/SystemPulse/AppDelegate.swift` | App lifecycle, status item, popover, menu-bar ownership |
| `Sources/SystemPulse/MonitorStore.swift` | `@MainActor` UI state, bounded histories, user actions, toasts |
| `Sources/SystemPulse/SystemSampler.swift` | Mach/BSD CPU, memory, filesystem, network, load, uptime, thermal sampling |
| `Sources/SystemPulse/PowerSampler.swift` | Battery, adapter, and system power draw sampling |
| `Sources/SystemPulse/MetricHistory.swift` | Bounded timestamped raw and aggregate history |
| `Sources/SystemPulse/NetworkInterfaces.swift` | Local interface metadata and independent rate tracking |
| `Sources/SystemPulse/VolumeMonitoring.swift` | Mounted-volume metadata and safe selection fallback |
| `Sources/SystemPulse/DiagnosticsExport.swift` | Privacy-allowlisted JSON/CSV schema and atomic saves |
| `Sources/SystemPulse/MonitorStore+Diagnostics.swift` | User-requested snapshot/history capture boundary |
| `Sources/SystemPulse/AlertEngine.swift` / `AlertCoordinator.swift` | Pure sustained rules, recovery/cooldown and genuine per-source timestamps |
| `Sources/SystemPulse/LocalNotificationService.swift` | Guarded, opt-in native notification delivery and visible errors |
| `Sources/SystemPulse/Preferences.swift` / `SettingsWindowController.swift` | Persisted/migrated preferences and retained native Settings window |
| `Sources/SystemPulse/MenuBarConfiguration.swift` / `MenuBarRenderer.swift` | Ordered metric selections, unknown states and native status rendering |
| `Sources/SystemPulse/HardwareTelemetryNote.swift` | Static collection/provenance notes; no capability probe, device identifiers or permissions |
| `Sources/SystemPulse/MonitoringInsights.swift` / `MonitorStore+Signals.swift` | Measurement-only insights and freshness/eligibility boundaries |
| `Sources/SystemPulse/DiskScanner.swift` / `DiskScanScope.swift` | Cancellable home cleanup and separate read-only folder inventory, containment checks and truthful unavailable states |
| `Sources/SystemPulse/CleanupQueue.swift` / `CleanupReviewWindowController.swift` / `CleanupTerminationGate.swift` | Bounded session-only queue, one-shot reviewed authority, retained native review/results and normal-Quit drain |
| `Sources/SystemPulse/FolderSelectionSession.swift` | Retained native folder chooser with injected tests and stale/shutdown response guards |
| `Sources/SystemPulse/FolderInventory.swift` / `Views/FolderInventoryCard.swift` | Bounded largest files/subfolder summaries, read-only drill-down/search, scope-validated native Quick Look |
| `Sources/SystemPulse/ProcessMetadataProvider.swift` | Process bundles, icons, metadata |
| `Sources/SystemPulse/Views/` | SwiftUI presentation and interactions |
| `Resources/Info.plist` | Bundle metadata, `LSUIElement`, version strings |
| `scripts/build-app.sh` | App-bundle assembly, resource normalization, ad-hoc signing, validation, local install |
| `scripts/install-local.sh` | Replace `~/Applications/SystemPulse.app` from `dist/` |
| `scripts/package-zip.sh` | Archive with `ditto`, unpack to a temp dir, re-verify, report version and size |
| `scripts/verify-committed-zip.sh` | CI guard: the committed zip must unpack, verify, and match `Info.plist`'s version |
| `scripts/test-app-bundle.sh` | Bundle and installed-copy validation run by `make test` and CI |
| `scripts/generate-icon.sh` | Regenerate `Resources/AppIcon.icns` from `Assets/AppIcon.svg` (needs `brew install librsvg`) |
| `install.sh` | One-command user-local installation and launch |

## Architecture notes

Sampling runs off the main actor; `MonitorStore` owns observable state on
`@MainActor`. Counter history continues with the panel closed; process sampling
slows to a 15-second cadence, power sampling is throttled, and volume-capacity
polling occurs only while open (normally every 10 seconds, plus mount changes).
Home-volume capacity additionally samples while closed when a visible disk
menu metric needs it (about 10 seconds), or an enabled, authorized disk alert
needs it (about 5 seconds; cadence rounds to polling passes). This is metadata,
not a cleanup scan. Each alert advances only on a new actual observation; gaps
over 10 seconds reset sustained time. Workspace sleep/wake suspends polling,
rejects pre-sleep in-flight results and refreshes counter baselines without
clearing history or observed session totals. Bytes while suspended are not
counted as measured traffic. Sleep is not recovery for a latched alert;
baseline-only CPU readings and failed memory queries are unavailable to rules.
Shutdown is terminal and releases polling/toast timers.
Timestamped history has fixed capacity,
never a growing on-disk log. Phase 2/3 idle energy and long-session performance
still need measurement; no CPU-budget claim is made here.

## Limitations

- Per-process network throughput is not available through public macOS APIs
  without elevated privileges; SystemPulse reports aggregate and per-interface throughput, not per-app attribution.
- Disk scanning targets well-known developer/cache locations, not a full-volume
  inventory; a selected-folder inventory is separately read-only. Entering the Disk topic does not start a scan; use Scan Cleanup Locations or explicitly confirm Choose Folder.
- Launch at Login uses `SMAppService`; macOS may reject it for an ad-hoc-signed
  build.
- GPU/sensor telemetry is not implemented; the hardware/API feasibility review is completed and these backends are deferred from this release.
- Memory pressure is estimated from available headroom, not the exact macOS pressure signal.
- Disk scan results can include read-only application data; they are not all reclaimable. Unmeasured locations are counted and partial scans cannot authorize Trash; individual error paths/reasons are not yet itemized.
- A materially changed rebuild can still cause macOS to treat the app as new.
  Do not promise that macOS will never prompt again.
