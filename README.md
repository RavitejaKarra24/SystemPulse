# SystemPulse

A native macOS **menu-bar system monitor** — live CPU, memory, network, and disk
insights with process control and reclaimable-space cleanup. Built as a polished
evolution of the System Monitoring experience in
[OneMenu](https://coffeebreak.software/one-menu/).

## Highlights

### Menu bar
- **Visual gauges** (default) — compact C/M/(N) meters that adapt to light/dark mode
- Styles: Gauges · Compact · Detailed · Icon Only (right-click the status item)
- Rich tooltip with live rates and the current top process
- Optional network readout in the menu bar

### CPU
- Rolling history graph with load-aware coloring
- **Per-core utilization** grid
- Load averages (1 / 5 / 15), peak CPU, top process strip
- Grouped process list with helper rollup (`+N`), usage micro-bars, search
- Right-click: Quit / Force Quit / Reveal in Finder / Copy Path

### Memory
- Live used-bytes history graph
- **Breakdown card** — App · Wired · Compressed · Cached · Free stacked bar
- Memory **pressure** indicator (Normal / Elevated / Critical)
- Processes sorted by resident memory

### Network
- Dual-series throughput graph (download + upload)
- Live rate, session peak, and session totals
- Physical interfaces only (loopback excluded; cellular `pdp_ip*` included)

### Disk
- Capacity ring gauge with free / used / reclaimable totals
- Progressive background scan with **percent progress**
- Categories: Applications · Development · Containers · System
- Covers Xcode, SPM, npm/yarn/pnpm/bun, Homebrew, Docker/OrbStack, Trash, and more
- Two-step delete confirm → moves to Trash
- Auto-starts a scan the first time you open the Disk tab

### Process detail
- Per-group CPU/memory history, hierarchy, thread counts
- Started-at + running-for, copyable paths
- Quit / two-step Force Quit / Reveal in Finder

### Native polish
- Keyboard: `1–4` switch tabs, `Esc` back, `⌘F` focus search
- Toast feedback for quit / copy / delete
- Hover states, matched tab pill, numeric content transitions
- Preferences: refresh rate, menu bar style, launch at login
- Popover sizes to content; menu-bar-only (`LSUIElement`)

## Architecture

| Piece | Role |
|---|---|
| `SystemSampler` | Mach/BSD sampling — per-core CPU deltas, `vm_statistics64`, filesystem capacity, physical NIC counters, load average, uptime, thermal state |
| `ProcessMetadataProvider` | Owning `.app` bundle, icon, start time |
| `DiskScanner` | Categorized progressive scan with progress fraction |
| `MonitorStore` | `@MainActor` `@Observable` store, bounded histories, actions, toasts |
| `Preferences` | UserDefaults + `SMAppService` launch-at-login |
| `MenuBarRenderer` | Template-image gauges for the status item |
| `Views/` | SwiftUI popover UI |

Process CPU is a **real-time percentage** — delta of cumulative Mach user/system
time between samples ÷ elapsed wall time — not a raw cumulative counter.

## Run

```sh
make run
```

## Build a menu-bar app bundle

```sh
make bundle
open dist/SystemPulse.app
```

The app hides its Dock icon (`LSUIElement`) and lives only in the menu bar.

### Right-click menu
- Open SystemPulse
- Menu Bar Style
- Refresh Rate (1s / 1.5s / 3s)
- Show Network in Menu Bar
- Launch at Login
- About / Quit

## Notes / known limitations

- Per-process network throughput isn't exposed by public macOS APIs without
  elevated privileges — only aggregate system throughput is shown.
- Disk scanning covers well-known developer/cache locations, not a full volume
  inventory.
- Launch at Login requires a properly signed/notarized app for
  `SMAppService` registration; unsigned local builds may be rejected by the OS.
- GPU telemetry is intentionally out of scope for the menu-bar popover form factor.
