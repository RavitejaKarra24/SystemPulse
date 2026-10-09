# Guided accessibility session — still in progress

Target: installed **SystemPulse 1.7.1/build 16**, macOS 27.0.1, arm64. User explicitly selected guided accessibility checks and controls all macOS accessibility/visual-setting changes. No automatic setting changes, new permissions, notification requests, scans/data/process actions or app-preference-control edits are authorized by this session.

## Entry evidence

- User reported VoiceOver ready with **Control-Option** available as modifier.
- Read-only follow-up confirmed VoiceOver **on**, existing AX/event access, matching installed target, alerts off, 1.5-second polling, CPU/memory gauges, Reduce Motion/Transparency/Increase Contrast still off.
- At that check the app was active, with an exposed popover and one owned onscreen window. This does not establish how it was opened or its spoken/focus behavior.
- `NSApplication.isFullKeyboardAccessEnabled` reported **false before VoiceOver setup, true afterward**. This is the observed AppKit indicator, not an independently verified state/change of the Accessibility → Keyboard Full Keyboard Access switch. Cause is not isolated; no global keyboard setting was changed by the assistant. Record the user's actual switch baseline before any later keyboard-setting test.
- Original observed VoiceOver state was **off**. User-controlled restoration and read-only postflight are required before closing the session.

## Human outcome ledger

No pass is inferred from readiness, an AX action acknowledgment, source tests or offscreen renders. Record human reports separately from machine observations; a reported failure requires the precise control/expected behavior, without private process names/data.

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
| Restore original user-controlled settings / postflight | not started | VoiceOver originally off; record all changes/restoration, do not silently overwrite settings. |

## First procedure

With VoiceOver on, **VO means Control-Option** for this group:
1. If closed, use VO-M-M to reach status menus, navigate to SystemPulse, and activate with VO-Space. If already open, begin at its content; menu-entry behavior still needs its own outcome.
2. Use VO-Left/Right to move through the popover. Where a group requests interaction, use VO-Shift-Down; VO-Shift-Up leaves a group.
3. Locate Overview, CPU, Memory, Network, Disk and Power; listen for understandable names/roles. Activate CPU with VO-Space. Do not activate action menus, scans or preference controls.
4. Report whether labels/activation worked, or identify the missing/misnamed control without private telemetry/process information.

Apple's [menu-bar guidance](https://support.apple.com/guide/voiceover/menu-bar-and-control-center-mchlp2748/mac) documents VO-M-M for status menus. The [navigation guide](https://support.apple.com/en-tj/guide/voiceover/mchlp2699/mac) documents standard VO movement/interaction/activation. Guidance is not evidence that SystemPulse passed.

Related: [ACCESSIBILITY.md](ACCESSIBILITY.md), [current non-destructive automation](LIVE_VALIDATION_1.7.1.md), [ROADMAP.md](../ROADMAP.md), [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md).
