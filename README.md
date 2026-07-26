# SystemPulse

A native macOS menu-bar monitor for live CPU, memory, network, disk, and process
insights—plus focused cleanup of reclaimable developer and system space.

[View the interface walkthrough](organized%20view.webm). SystemPulse runs in the
**menu bar**, not the Dock.

## Features

| Area | What it provides |
|---|---|
| Menu bar | Adaptive gauges, compact/detailed styles, live tooltip, and optional network readout |
| CPU | Rolling history, per-core utilization, load averages, peak/top process, and process actions |
| Memory | Used-memory history, app/wired/compressed/cached/free breakdown, pressure state, and process ranking |
| Network | Download/upload history, current and session rates, totals, and physical-interface sampling |
| Disk | Capacity/reclaimable-space gauge and a progressive scan of common development caches, containers, and Trash |
| Process detail | Grouped process hierarchy, CPU/memory history, thread count, paths, and quit/force-quit controls |

Keyboard shortcuts: `1`–`4` switch tabs, `Esc` returns, and `⌘F` focuses process
search.

## Requirements

- macOS 14.0 or later
- Xcode Command Line Tools (free): `xcode-select --install`
- Git

SystemPulse does not collect, transmit, or require special Privacy & Security
permissions. It reads system counters locally. Process termination and moving
items to Trash require an explicit action in the app.

## Install from source

SystemPulse is intentionally distributed as source. Building locally avoids
shipping an unsigned downloaded app and installs a locally ad-hoc-signed bundle
without `sudo`.

```bash
# Run this first only if `swift --version` is unavailable.
xcode-select --install

# Clone, inspect, and install.
git clone https://github.com/RavitejaKarra24/SystemPulse.git
cd SystemPulse
./install.sh
```

`install.sh` verifies the free toolchain, builds the release executable, creates
and validates a real `.app` bundle, installs it to
`~/Applications/SystemPulse.app`, and opens it. It stops only an older
`SystemPulse` process and removes quarantine only from the bundle it just built.

After installation, click the SystemPulse icon in the menu bar.

### Launch, update, and uninstall

```bash
# Launch an installed copy
open "$HOME/Applications/SystemPulse.app"

# Update a previously cloned checkout
cd SystemPulse
git pull --ff-only
./install.sh

# Uninstall
pkill -x SystemPulse 2>/dev/null || true
rm -rf "$HOME/Applications/SystemPulse.app"
```

## Development

```bash
make run       # Run from SwiftPM during development
make build     # Build the release executable
make test      # Build and validate the distributable app bundle
make bundle    # Assemble and validate dist/SystemPulse.app
make install   # Build, install to ~/Applications, and launch
```

The generated app hides its Dock icon (`LSUIElement`) and lives only in the
menu bar. Right-click its status item to open it, change menu-bar styles and
refresh rate, toggle the network readout or launch-at-login, or quit.

## Architecture

| Path | Responsibility |
|---|---|
| `Sources/SystemPulse/AppDelegate.swift` | App lifecycle, status item, popover, and menu-bar ownership |
| `Sources/SystemPulse/MonitorStore.swift` | `@MainActor` UI state, bounded histories, user actions, and toasts |
| `Sources/SystemPulse/SystemSampler.swift` | Mach/BSD CPU, memory, filesystem, network, load, uptime, and thermal sampling |
| `Sources/SystemPulse/DiskScanner.swift` | Background, categorized reclaimable-space scan with progress |
| `Sources/SystemPulse/ProcessMetadataProvider.swift` | Process bundles, icons, and metadata |
| `Sources/SystemPulse/Views/` | SwiftUI presentation and interactions |
| `scripts/build-app.sh` | Reproducible app-bundle assembly, resource normalization, ad-hoc signing, and validation |
| `install.sh` | One-command user-local installation |

`Resources/AppIcon.icns` is generated from `Assets/AppIcon.svg`. To regenerate
it after editing the source artwork, install `librsvg` (`brew install librsvg`)
and run:

```bash
./scripts/generate-icon.sh
```

## Limitations

- Per-process network throughput is not available through public macOS APIs
  without elevated privileges; SystemPulse reports aggregate throughput only.
- Disk scanning targets well-known developer/cache locations, not a full-volume
  inventory.
- Launch at Login uses `SMAppService`; macOS may reject it for an unsigned local
  build.
- GPU telemetry is outside this menu-bar utility's scope.
- A significantly changed local rebuild can cause macOS to re-evaluate an
  existing protected permission; no installer can silently grant permissions.
