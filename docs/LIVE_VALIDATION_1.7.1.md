# Approved live checkpoint — SystemPulse 1.7.1/build 16

**Named non-destructive UI and short-run resource checks: completed as listed below. Overall release: still in progress.** User selected this scope explicitly. This is real installed-app automation, not human VoiceOver certification, energy measurement or a completed 24-hour gate.

## Scope and safeguards

- Current installed/source/archive version **1.7.1/build 16**; Apple Silicon, 10 logical CPUs, macOS 27.0.1. The same installed process remained running throughout. No product source or binary changes.
- Existing Accessibility/event-posting permission was checked without requesting access. VoiceOver, Full Keyboard Access, Reduce Motion/Transparency and Increase Contrast remained off.
- Own-app AX controls and process-targeted CG events only; no global keyboard/mouse posting, screenshots, Apple Events, raw process-name/path/address logs or private UI dumps.
- Alerts off; normal **1.5-second polling**, CPU/memory **Gauges**. No preference controls changed. Settings status queries are read-only; no notification authorization request/delivery, login registration, clipboard/export, scan/chooser, Trash/Force Quit, Finder/Quick Look or hardware action.
- Synthetic search text was entered only into an initially empty search and cleared. Charts were resumed after inspection. Final checks showed no owned onscreen windows or exposed popover, and the original off-state accessibility/visual settings.
- Control-preference comparisons passed during interaction and resource context checks. The Settings/control-navigation helper also found the whole app preference domain unchanged during its run. This does not retroactively erase the native-frame-autosave observation in the older 1.7.0 checkpoint.

## Installed UI results

| Named check | Status | Actual observed evidence / limit |
|---|---|---|
| Current target/permission preflight | completed | One installed 1.7.1/build 16 app, existing trust/event-post access, declared default workload, no windows initially. |
| Popover and CPU topic entry | completed | Own status AX press exposed topic controls; CPU button produced the CPU page. Bounded waits were required for accessibility exposure. |
| Topic keys 0–5 | completed | Character-bearing process-targeted events produced all six corresponding page headings. This is not physical/non-US keyboard certification. |
| Chart ranges | completed | Last hour/24 hours/five minutes actions produced the matching 1h/24h/5m chart accessibility description, not merely a successful action acknowledgment. |
| Freeze/resume | completed | Freeze changed the control to Resume live chart; resume restored Freeze chart. No claim that a UI fixture measured underlying sampling cadence. |
| Native search/editing | completed | ⌘F focused Search processes; `12345` entered as text while retaining CPU. Native virtual-key ⌘A selected all five characters; replacement yielded `0` without topic navigation. Clear restored empty search. No clipboard action. |
| Show all/show fewer | completed | Actions toggled the actual Show fewer control/state and returned to the limited list. No process identifiers recorded. |
| Process expansion/collapse | completed | Actual accessibility Expanded/Collapsed state changed both ways. |
| Process detail / Escape | completed | Process row opened detail; a digit did not leave detail; Escape returned to the topic, with Back absent afterward. No process action or context-menu command invoked. |
| Chart inspection/focus/keys | completed | On a frozen chart, AX decrement changed `AXValueDescription`; AX focus matched the chart element; Left changed inspection, Right reversed it, and chart Escape restored the latest summary while retaining the topic. This does not certify visible focus styling or spoken summaries. |
| Power source disclosure | still in progress | Two native disclosure actions were accepted; full expanded-body/wrapping/keyboard/spoken behavior was not certified. |
| Settings sidebar / close | completed | General/Menu Bar/Alerts selected rows matched the native window title; ⌘W closed Settings. No picker/toggle/numeric-draft changes. |
| Popover Escape / delayed reopen | completed | Topic Escape removed exposed topic content; reopening after a 1.5-second settling delay exposed it again. Rapid-toggle and actual outside-pointer behavior remain open. |
| Physical input / remaining human UI | still in progress | Physical/non-US keys, pointer hover/outside click, visible focus order/legibility, Settings numeric-draft interactions and remaining surfaces need separately recorded outcomes. |
| Assistive, permission and destructive gates | not started | Outside this approval; no real VoiceOver, global setting change, permission/save/login or disposable destructive/preview workflow was attempted. |

## Harness corrections, not product fixes

Initial bare virtual-key events navigated inconsistently; character-bearing events subsequently passed all topic checks. This demonstrates a limitation of the initial event construction, not a verified app keyboard defect. Command shortcuts were tested with native virtual-key events without injected Unicode.

An immediate reopen attempt and a one-second exposure wait did not reliably expose controls. A bounded longer exposure wait and delayed reopen passed. Rapid/native-pointer behavior is still not certified; no speculative activation workaround was shipped.

The chart publishes its summary in **AXValueDescription**, not the helper's initially queried AXValue. After correcting that observation, adjustment and Left/Right/Escape checks passed. An accepted accessibility action alone was not counted as a verified state change. Guarded unavailable-control attempts stopped before speculative input. No installed-app crash was observed.

## Current packaged-app resource observations

These external observations did not launch/kill/rebuild the app or change its configuration. Each uses checked kernel CPU/timebase/footprint/wakeup readings and process identity throughout. The companion context watchers read only allowlisted configuration and owned UI state at roughly five-second intervals.

| Scenario | Warmup / measured duration | CPU, one core = 100% | Sampled footprint | Package-idle wakeups |
|---|---|---:|---:|---:|
| Closed default, before this UI session | 30.005s / 180.005s | **1.318%** | **21.267–21.313 MiB** | **62; 0.344/s** |
| Overview, after process/chart/Settings interactions | 15.005s / 60.001s | **3.617%** | **104.595–154.923 MiB** | **30; 0.500/s** |

- Closed context: **44 checks** reported matching version/configuration, alerts off, zero owned onscreen/AX windows and no exposed popover. The first helper did not retain individual window-query error statuses; treat this as best-effort sampled context, not proof of continuous visibility or a failure-proof absence detector.
- Overview context: **17 checks** found matching version/configuration, alerts off, an owned onscreen window, exposed Overview/popover and frontmost/active app. Missing window/AX observations are nullable in this helper. This still does not establish continuous unocclusion, native key-window state or frame-rendering cost.
- Same process, different durations and prior UI/cache histories: these are **not a causal closed-versus-open comparison**, a leak finding or an improvement over historical versions. Footprint extrema are sampled, not continuous peaks. Host activity and external AX/observer overhead apply.
- Raw observer JSON continues to label UI/configuration unverified by the sampler itself; companion evidence narrows that limitation only at its recorded observation times. Original reports were not rewritten to imply full verification.
- **Energy/joules/battery life were not measured. No agreed pass/fail resource budget or real 24-hour/sleep-wake soak was completed.** R5 remains still in progress.

Raw retained evidence:
- [Closed process report](performance/installed-app-1.7.1-closed-default.json), [closed context](performance/installed-app-1.7.1-closed-default-context.json).
- [Overview process report](performance/installed-app-1.7.1-overview.json), [Overview context](performance/installed-app-1.7.1-overview-context.json).

Temporary helper scripts and raw logs remained outside the repository. Retained reports contain no raw PID, executable/user path, process names or interface/device identity. Existing 390-pass/one-skip source-suite evidence and archive hash are unchanged; this checkpoint adds interaction/resource evidence rather than claiming a new source build. See [ROADMAP.md](../ROADMAP.md) and [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) for the remaining approval-dependent and other-hardware gates.
