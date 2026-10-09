# Historical guided accessibility session — closed; scope withdrawn

**Session closed for restoration; acceptance work withdrawn on 9 October 2026.** The owner reported Settings labels, values and activation worked. Test accessibility settings were returned to off; no further testing is scheduled. Explicit app additions are removed in 1.7.2/build 17. The ledger below is historical and its pending procedure is superseded by [the current scope/restoration record](RELEASE_VALIDATION_2026-10-09.md).

Target: installed **SystemPulse 1.7.1/build 16**, macOS 27.0.1, arm64. User explicitly selected guided accessibility checks and controls all macOS accessibility/visual-setting changes. No automatic setting changes, new permissions, notification requests, scans/data/process actions or app-preference-control edits are authorized by this session.

## Entry evidence

- User reported VoiceOver ready with **Control-Option** available as modifier.
- Read-only follow-up confirmed VoiceOver **on**, existing AX/event access, matching installed target, alerts off, 1.5-second polling, CPU/memory gauges, Reduce Motion/Transparency/Increase Contrast still off.
- At that check the app was active, with an exposed popover and one owned onscreen window. This does not establish how it was opened or its spoken/focus behavior.
- `NSApplication.isFullKeyboardAccessEnabled` reported **false before VoiceOver setup, true afterward**. This is the observed AppKit indicator, not an independently verified state/change of the Accessibility → Keyboard Full Keyboard Access switch. Cause is not isolated; no global keyboard setting was changed by the assistant. Record the user's actual switch baseline before any later keyboard-setting test.
- Original observed VoiceOver state was **off**. At this entry checkpoint, user-controlled restoration and read-only postflight were still required. Subsequent restoration and scope withdrawal are recorded below.

## Historical human outcome ledger — incomplete rows withdrawn

No pass is inferred from readiness, an AX action acknowledgment, source tests or offscreen renders. Human reports are separate from machine observations. “Not started”/“await” entries below preserve the earlier checkpoint only: they are **withdrawn from current acceptance**, not instructions to resume. Limited later Settings/visual observations and restoration are appended after the table.

| Check group | Status | Evidence |
|---|---|---|
| User approval / VoiceOver setup | completed | Explicit guided-scope selection; user readiness report and read-only VoiceOver-on confirmation. |
| Spoken topic labels / CPU activation | completed | User reported all six names understandable and CPU opened through VoiceOver activation. This is a human outcome, not inferred from AX metadata. |
| Status-menu entry | not started | How the already-exposed popover was entered was not independently reported; do not infer VoiceOver menu entry from the topic pass. |
| Spoken metrics, values, headings and chart adjustment | not started | Await real reading/interaction, including range/live-frozen/unavailable semantics. |
| Control-Option/Caps Lock command safety and native search | not started | Await actual modifier/text-editing outcomes; no clipboard commands. |
| Focus order / close-reopen / escaping groups | not started | Await real focus and lifecycle observations, not synthetic helper success. |
| Persistent failure read/scroll/dismiss/announcement | not started | Need an approved non-destructive way to create a real failure; no fake production reading/status injection. |
| Actual Full Keyboard Access / keyboard navigation | not started | First establish the user's independent switch baseline; do not equate the AppKit indicator with certification. |
| Light/dark, contrast, transparency, motion and legibility | not started | User-controlled setting changes and actual visual outcomes pending. |
| Restore original user-controlled settings / postflight | completed for named restoration below; originally not started | Earlier checkpoint: VoiceOver originally off; restoration pending. Later VoiceOver/display/motion off states observed; Full Keyboard Access toggled off before leaving its pane. No broad assistive pass inferred. |

## Final historical outcomes and restoration

The later build 16 release session records the owner's report that **Settings labels, values and activation worked**. Full Keyboard Access's independent switch baseline was off; it was enabled for a focus/sidebar check and then turned off. Increase Contrast and Reduce Transparency were exercised and restored off; Reduce Motion was enabled for a static view and restored off. Static images did not certify animation suppression. VoiceOver was restored off with an observed native switch confirmation. VoiceOver/display/motion off states were observed; Full Keyboard Access was toggled off before leaving its pane.

The earlier pending restoration row is therefore superseded by these named outcomes, not a broad assistive pass. The owner withdrew acceptance work on 9 October; explicit app semantics, announcements, VO-dependent routing and display adaptations were removed in **1.7.2/build 17**. No further accessibility testing is scheduled. [Exact restoration and limits](RELEASE_VALIDATION_2026-10-09.md). Overall release sign-off remains pending for retained non-accessibility gates.

## Historical first procedure — withdrawn, not current authorization

Preserved for history only; do not enable settings or resume this procedure unless the owner changes scope. In the original procedure, **VO meant Control-Option** for this group:
1. If closed, use VO-M-M to reach status menus, navigate to SystemPulse, and activate with VO-Space. If already open, begin at its content; menu-entry behavior still needs its own outcome.
2. Use VO-Left/Right to move through the popover. Where a group requests interaction, use VO-Shift-Down; VO-Shift-Up leaves a group.
3. Locate Overview, CPU, Memory, Network, Disk and Power; listen for understandable names/roles. Activate CPU with VO-Space. Do not activate action menus, scans or preference controls.
4. Report whether labels/activation worked, or identify the missing/misnamed control without private telemetry/process information.

Apple's [menu-bar guidance](https://support.apple.com/guide/voiceover/menu-bar-and-control-center-mchlp2748/mac) documents VO-M-M for status menus. The [navigation guide](https://support.apple.com/en-tj/guide/voiceover/mchlp2699/mac) documents standard VO movement/interaction/activation. Guidance is not evidence that SystemPulse passed.

Related: [ACCESSIBILITY.md](ACCESSIBILITY.md), [current non-destructive automation](LIVE_VALIDATION_1.7.1.md), [ROADMAP.md](../ROADMAP.md), [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
