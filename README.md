# SystemPulse

A small Mac app that lives in your menu bar and shows you what your computer is
doing right now: CPU, memory, network, disk space, battery, and which apps are
using the most of each.

- **Just want to use it?** Read [Install and use](#install-and-use).
- **Want to read or change the code?** Read [For developers](#for-developers).

Requirements: macOS 14.0 or later. Free, open source, and nothing it measures
leaves your Mac.

[View the interface walkthrough](organized%20view.webm)

---

# Install and use

## What you get

| Area | What it shows |
|---|---|
| Menu bar | Live gauges you can keep an eye on, in a compact or detailed style |
| CPU | Recent history, per-core use, and the processes working hardest |
| Memory | What's in use, how it's split up, memory pressure, and the biggest consumers |
| Network | Download and upload speed, plus totals for this session |
| Disk | How full the drive is, live read/write activity, and a scan for space you can safely reclaim |
| Power | Charge level, time remaining, battery health, cycle count, and live power draw |
| Processes | A grouped list of everything running, with the option to quit something |

## Install

**Before you start:** macOS will show a security warning the first time you open
SystemPulse. That is expected. It means the app has not paid for Apple's
notarization service, not that anything is wrong with it. Steps 4 to 6 walk you
through it, and **you only do this once.**

1. **Download the app.**
   [Download SystemPulse.zip](https://github.com/RavitejaKarra24/SystemPulse/raw/main/SystemPulse.zip)
   It's about 1.5 MB and lands in your **Downloads** folder.

2. **Unzip it.** Double-click `SystemPulse.zip` in Downloads. A `SystemPulse`
   app icon appears next to it.

3. **Move it to Applications.** Open a new Finder window, click
   **Applications** in the sidebar, and drag `SystemPulse` into it.

4. **Try to open it.** Double-click `SystemPulse` in Applications. A dialog
   says **"SystemPulse" Not Opened** — *Apple could not verify "SystemPulse" is
   free of malware…* Click **Done**. Nothing has gone wrong; this is the
   warning mentioned above.

5. **Allow it.** Open **System Settings** (Apple menu > System Settings), click
   **Privacy & Security** in the sidebar, and scroll down to the **Security**
   section near the bottom. You'll see *"SystemPulse" was blocked to protect
   your Mac.* Click **Open Anyway** next to it.

6. **Confirm.** Unlock with Touch ID or your login password, then click
   **Open Anyway** once more if you're asked again.

SystemPulse is now open, and every future launch is a normal double-click.

> Steps 4 to 6 are as of macOS 26 (July 2026). Apple changes the exact wording
> from time to time, but the path is always System Settings > Privacy &
> Security > Security.

## Where the app appears

**SystemPulse has no Dock icon and no window.** It runs in the **menu bar** —
the strip at the top right of your screen, next to the clock and Wi-Fi. Look for
its small live gauge there and click it to open the panel.

If you can't find it, your menu bar may be full; try quitting an app or two, or
temporarily hiding other menu bar items.

## Using it

- **Click** the menu bar icon to open the panel; click anywhere else to close it.
- **Inspect charts:** hover to read a sample, choose the latest **20 or 60 samples**, or use **Pause** to freeze that chart. Resume returns to live data; other metrics keep updating. Sample counts are used because refresh rates vary.
- **Copy a snapshot:** click the copy icon beside **LIVE** for a text summary of current system metrics.
- **Scroll the panel** for additional details. The header and topic navigation stay in place as pages crossfade; macOS Reduce Motion disables the navigation animation.
- **Number keys 1 to 5** switch between CPU, Memory, Network, Disk, and Power.
- **Esc** goes back a level, **⌘F** jumps to the process search box.
- **Right-click** the menu bar icon for settings: menu bar style, refresh rate,
  whether to show network speed, launch at login, and Quit.

## Update

There is no automatic updater. To move to a newer version:

1. Right-click the SystemPulse icon in the menu bar and choose **Quit**.
2. Download the zip again using the link above and unzip it.
3. Drag the new `SystemPulse` into **Applications** and click **Replace** when
   Finder asks.

You may have to repeat the "Open Anyway" steps once for the new version. That is
normal for apps distributed this way.

## Uninstall

1. Right-click the SystemPulse icon in the menu bar and choose **Quit**.
2. Open **Applications**, drag `SystemPulse` to the Trash, and empty it.

That's everything. SystemPulse stores only a small preferences entry under your
own user account, which macOS discards on its own.

## Privacy

SystemPulse reads system counters on your Mac and displays them. **Nothing is
collected, uploaded, or sent anywhere** — there is no network code in the app
beyond measuring your own throughput numbers. It needs no Privacy & Security
permissions. Quitting a process or moving files to the Trash happens only when
you click the button that does it.

## Troubleshooting

- **Nothing happened when I double-clicked it.** The security dialog may be
  hiding behind another window, or you may have missed it. Try again, then
  follow steps 5 and 6.
- **I don't see "Open Anyway" in System Settings.** It only appears for a short
  while after a blocked launch. Double-click the app again, then go straight
  back to System Settings > Privacy & Security.
- **I can't find the app anywhere after opening it.** It has no Dock icon by
  design. Look in the menu bar at the top right of the screen.
- **The disk scan seems slow.** It walks common cache folders in the background
  and fills in as it goes; you can keep using the rest of the app meanwhile.
- **Numbers freeze or the panel looks stale.** Right-click the menu bar icon,
  choose Quit, and open SystemPulse again from Applications.

---

# For developers

## Clone, build, run

```bash
# Only needed if `swift --version` fails.
xcode-select --install

git clone https://github.com/RavitejaKarra24/SystemPulse.git
cd SystemPulse
./install.sh
```

`install.sh` builds the release executable, assembles and validates a real
`.app`, installs it to `~/Applications/SystemPulse.app`, and opens it. No
`sudo`. A locally built app is never quarantined, so you will not see the
Gatekeeper prompt that downloaders see.

## Everyday commands

```bash
make run         # Run from SwiftPM during development
make build       # Release build of the executable
make test        # Build and validate the distributable app bundle
make bundle      # Assemble and validate dist/SystemPulse.app
make zip         # Build, archive, unpack, and re-verify SystemPulse.zip
make verify-zip  # Check the committed zip unpacks, verifies, and isn't stale
make install     # Build, install to ~/Applications, and launch
make clean       # Remove .build and dist
```

## Distribution model

SystemPulse is **ad-hoc signed and not notarized**. Notarization requires a paid
Apple Developer membership, which this project does not have, so downloaded
copies hit Gatekeeper once and users clear it through System Settings. That
trade-off is deliberate — please don't add `notarytool`/`stapler` steps that
cannot actually run in this repo's CI.

Practical consequences:

- `SystemPulse.zip` is committed at the repo root, outside the ignored `dist/`
  directory, and served over `raw.githubusercontent.com`. At ~1.5 MB, repo
  bloat is not yet a reason to move to GitHub Releases.
- **Regenerate the zip in the same commit as any user-facing change**, and bump
  `CFBundleShortVersionString` in `Resources/Info.plist` while you're there. Git
  will not warn you that a committed build artifact is stale.
- Archiving uses `ditto -c -k --keepParent`, never `zip`. The `zip` command
  drops extended attributes and symlinks, which invalidates the signature and
  produces an app that silently refuses to launch on Apple silicon.
- Ad-hoc signatures change between builds, so if the app ever needs TCC
  permissions, users would be re-prompted after each update. That would be the
  point to buy the $99 membership.
- Test the real download path from GitHub on another Mac or a fresh user
  account. Your local build is never quarantined and will never reproduce what
  users see.

## Layout

| Path | Responsibility |
|---|---|
| `Sources/SystemPulse/AppDelegate.swift` | App lifecycle, status item, popover, menu-bar ownership |
| `Sources/SystemPulse/MonitorStore.swift` | `@MainActor` UI state, bounded histories, user actions, toasts |
| `Sources/SystemPulse/SystemSampler.swift` | Mach/BSD CPU, memory, filesystem, network, load, uptime, thermal sampling |
| `Sources/SystemPulse/PowerSampler.swift` | Battery, adapter, and system power draw sampling |
| `Sources/SystemPulse/DiskScanner.swift` | Background, categorized reclaimable-space scan with progress |
| `Sources/SystemPulse/ProcessMetadataProvider.swift` | Process bundles, icons, metadata |
| `Sources/SystemPulse/Views/` | SwiftUI presentation and interactions |
| `Resources/Info.plist` | Bundle metadata, `LSUIElement`, version strings |
| `scripts/build-app.sh` | App-bundle assembly, resource normalization, ad-hoc signing, validation |
| `scripts/package-zip.sh` | Archive with `ditto`, unpack to a temp dir, re-verify, report version and size |
| `scripts/verify-committed-zip.sh` | CI guard: the committed zip must unpack, verify, and match `Info.plist`'s version |
| `scripts/test-app-bundle.sh` | Bundle validation run by `make test` and CI |
| `scripts/generate-icon.sh` | Regenerate `Resources/AppIcon.icns` from `Assets/AppIcon.svg` (needs `brew install librsvg`) |
| `install.sh` | One-command user-local installation |

## Architecture notes

SystemPulse idles at roughly 0.3% CPU while the panel is closed: with nothing on
screen it collects only what the menu bar draws, and defers the process table,
volume capacity, and load averages until you open it. Sampling lives off the
main actor; `MonitorStore` is the single `@MainActor` state holder that views
observe.

## Limitations

- Per-process network throughput is not available through public macOS APIs
  without elevated privileges; SystemPulse reports aggregate throughput only.
- Disk scanning targets well-known developer/cache locations, not a full-volume
  inventory.
- Launch at Login uses `SMAppService`; macOS may reject it for an ad-hoc-signed
  build.
- GPU telemetry is outside this menu-bar utility's scope.
