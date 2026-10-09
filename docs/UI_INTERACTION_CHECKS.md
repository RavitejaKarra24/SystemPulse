# Installed-app non-destructive UI checkpoint

**Status: still in progress.** User approved opening and testing the installed app's popover/Settings, navigation, text editing, focus and cancellation. This is scoped interaction automation, not human VoiceOver/Full Keyboard Access certification.

## Target and safety boundary

- Installed **SystemPulse 1.7.0/build 15**, Apple Silicon host, macOS 27.0.1. No product-source or binary changes in this checkpoint.
- Existing Accessibility trust and event-posting access were available. Read-only preflight did not request permission. VoiceOver, Full Keyboard Access, Reduce Motion/Transparency and Increase Contrast were **off**; none was enabled or changed.
- Own-app AX elements and process-targeted CG events only. No global keyboard posting, Apple Events, screenshot capture or private UI text dumps. Logs contain allowlisted UI labels and outcome booleans, not process names, interface addresses or user paths.
- Alerts were confirmed off before interaction. No notification authorization/delivery, login registration, chooser/folder scan, Trash, Force Quit, Finder, Quick Look, clipboard operation or hardware manipulation was invoked.
- No preference controls were changed. The Settings-open observation found the overall application preference domain changed, while `prefs.*` control values were unchanged. A native `NSWindow Frame SystemPulse.Settings` autosave entry was present afterward; the exact write was not isolated. Do not describe this real UI session as zero preference-domain writes, and do not overwrite/delete saved state to conceal it.

## Observations

| Named check | Status | Observed evidence / limit |
|---|---|---|
| Permission/target preflight | completed | Existing trust/event-post access; one matching installed application with version/build parity. No prompt. |
| Popover entry and accessible chrome | completed | Own status-item AX press exposed one AXPopover; bounded tree contained all six named topic buttons, the Monitoring topics group, copy/settings controls and headings. This does not certify visual contrast or spoken labels. |
| Topic buttons and 0–5 | completed | CPU button activated; process-targeted digits navigated through Memory/Network/Disk/Power/Overview/CPU with corresponding header text. This is not a physical keyboard/global-shortcut or other-layout test. |
| Process-search routing | completed | ⌘F focused the named text field. Typed fixture digits `12345` stayed in search and did not navigate topics. Control-Option-digit retained CPU with VoiceOver off; no actual VO command was exercised. Empty search was restored. |
| Select All / selected-text replacement | still in progress | Initial Unicode-bearing targeted-event attempt did not establish expected replacement. App activation/focus and subsequent popover exposure were inconsistent; later guarded attempts stopped before editing. Do not infer a production defect or successful responder-chain Copy/Select All from this evidence. |
| Escape / popover lifecycle / remaining focus | still in progress | Escape removed observable topic content in the search session. Later AX/targeted-mouse actions acknowledged success without consistently exposing the popover. Those acknowledgments were not counted as verified opens. Foreground setter succeeded, but stable foreground popover behavior was not established across sessions. |
| Native Settings sidebar | completed | Real window appeared with section title `General` (not the controller's initial `SystemPulse Settings`). Selecting native rows changed the displayed title to General, Menu Bar and Alerts. No toggle, picker or numeric-value changes. |
| Settings close key | completed | Own-window raise/foreground checks followed by targeted ⌘W closed the native Settings window. `prefs.*` values remained equal before/after navigation/close. |
| VoiceOver / Full Keyboard Access / visual settings | not started | Those settings remained off. Focus-ring rendering fixtures and AX labels are not certification of focus order, speech or actual system-setting behavior. |
| Native destructive/default dialogs and data operations | not started | Outside this approval. No confirmation, deletion/process action, native chooser/preview or error-producing filesystem test. |

## Automation limitations and disposition

The bounded AX tree can expose aliases; a broad Settings-label search initially found four candidates and stopped without clicking. Restricting traversal to the owned application menu and deduplicating AX identities produced one command. A window-title filter initially missed Settings because SwiftUI publishes the selected section title. These are harness limitations, not verified app regressions.

One guarded temporary helper stopped with a local assertion before finding a CPU control; this was the helper, not an observed SystemPulse crash. Subsequent guarded attempts also stopped on absent expected controls rather than sending speculative input. An attempted transient app-local AX client-mode setter returned `notImplemented` for both set/restore and did not establish a mode change; no global accessibility setting was modified.

Post-interaction read-only checks confirmed the same installed version/build, existing permissions, unchanged off-state VoiceOver/Reduce Motion/Reduce Transparency/Increase Contrast, and zero owned onscreen windows. Swift/shell lint, `git diff --check`, local documentation links and unchanged archive SHA-256 parity passed. The source suite was not rerun for this documentation-only checkpoint.

Temporary Swift helpers ran outside the repository. Only sanitized outcomes are retained here. No interaction-only run is substituted for the existing 363-pass/one-skip automated suite, historical performance probes or human release gates. Production code is unchanged; version/build/archive remain 1.7.0/15.

Later 1.7.1 source work added offscreen native SearchField focus/Select All/replacement regressions and extracted the unchanged nil-target Edit menu into a testable factory. Those local responder tests do not retest this installed 1.7.0 session or resolve its transient-popover uncertainty. See [LONG_SESSION_HARDENING.md](LONG_SESSION_HARDENING.md).

A subsequent approved **1.7.1 live checkpoint** verified native ⌘A/replacement/clear, character-bearing topic events, chart inspection, process controls and settled reopening, plus short resource observations: [LIVE_VALIDATION_1.7.1.md](LIVE_VALIDATION_1.7.1.md). It corrects helper event/exposure/attribute-query limitations but does not retroactively change this older session or certify physical/assistive behavior.

Next: separately approved remaining foreground/manual keyboard checks for Select All/replacement, Escape and focus; actual VoiceOver/Full Keyboard Access and visual settings; then the remaining resource/distribution and real OS-action gates in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md). Do not silently enable permissions/preferences or broaden to destructive actions to finish this matrix.
