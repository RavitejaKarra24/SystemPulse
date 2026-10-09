# Remaining release work

Native validation stopped at the owner's request on 9 October 2026. Current installed version: **SystemPulse 1.7.2, build 17**. Source/package candidate: **1.7.2, build 18**, not installed or natively verified. **Final release sign-off is pending.** The background 24-hour observation was cancelled; it does not count as a completed soak.

Completed evidence and its limits are in [the session record](docs/RELEASE_VALIDATION_2026-10-09.md). Build 17 passes 385 tests, with one opt-in skip and zero failures; three installer safety regressions pass separately. Strict builds, lint, signatures and installed/dist/archive parity passed. Numeric editing and preference restoration were checked on build 17. These results do not close the remaining gates below.

## Safe implementation pass — completed, not native sign-off

- [x] Fix reproduced numeric defects: reject incomplete decimal drafts and preserve the draft's parsing locale during editing; reformat after commit/cancel. Seven added numeric/keyboard regressions cover locale, range, correction, precision and responder transitions.
- [x] Strengthen archive verification to check full plist metadata (including build/identity), report architecture, and optionally compare all bundle payloads without installing/launching. Ten disposable regressions pass; `make verify-parity` checks the installed copy only after an authorized installation.
- [x] Reconcile release/session/performance/support records, preserving build 17 evidence and the **CANCELLED** soak; label historical accessibility wording withdrawn.
- [x] Run the build 18 full default suite, strict debug/release builds, lint, installer/artifact regressions and regenerate the signed archive with matching metadata. Candidate archive/dist parity passed; **installed parity is still pending**.

[Implementation results and artifact identity](docs/TODO_IMPLEMENTATION_2026-10-09.md). No accessibility features, OS setting changes, cleanup or native-action validation were added to this pass. The retained gates below stay open.

## R1 — UI interactions

- [ ] Test physical keyboards and non-US layouts, including topic keys, search, chart arrows and editing versus navigation.
- [ ] Verify pointer hover, outside-click dismissal, rapid opening/closing, Escape and stable popover lifecycle.
- [ ] Check visible focus and ordinary keyboard navigation across the remaining pages, charts, explorer, action dialogs and Settings.
- [ ] Complete remaining numeric-field cases: locale decimal separators, incomplete drafts, invalid ranges, duration/cooldown fields and focus transitions. CPU invalid-entry/Escape/valid-commit/restoration already passed on build 17. Build 18 adds automated locale/incomplete-draft fixes, but their native focus/editing regression is pending.
- [ ] Rerun affected native checks whenever a verified defect changes the UI.

## R2 — Withdrawn by the owner

Explicit app accessibility semantics, announcements, VoiceOver-dependent routing and accessibility display adaptations were removed in build 17. Further accessibility validation is stopped. Native macOS controls retain their platform behavior. Session accessibility settings were returned to off. Do not re-enable or resume this work unless the owner changes the scope.

## R3 — Storage and action safety

- [ ] Resolve the authorized test environment for cleanup: the real home scan found 28 unmeasured locations and correctly kept all results read-only. **Full Disk Access was not authorized or granted. Do not bypass this restriction or enable Trash on partial results.**
- [ ] Test chooser cancellation, rescan, changing/restricted folders, disappearing files, drill-down/Return/Back and scan cancellation during an actual running scan.
- [ ] Exercise large-folder and long-path inventories, retained-result limits and responsiveness with disposable fixtures.
- [ ] On a complete eligible scan, test SystemPulse single-item and batch Trash using only explicitly identified disposable cache folders.
- [ ] Test destructive-dialog Cancel, Escape and Return defaults; no move should occur without explicit approval.
- [ ] Verify failure results, partial batch outcomes, fresh-review retry, stale review invalidation and overlapping-path rejection in the native workflow.
- [ ] Verify Stop finishes the current move and skips remaining items; normal Quit drains an in-flight move without losing accounting.
- [ ] Verify sleep/interruption behavior during scan/cleanup under an authorized workload.
- [ ] Test a long/50-item review and check all exact paths are reviewable.
- [ ] Verify Finder restoration for items actually moved by SystemPulse. Finder Trash/Put Back alone already passed; it does not certify SystemPulse Trash.
- [ ] Finish disposable normal process-Quit/refusal/disappeared-target cases. Protected System controls and disposable Force Quit cancellation/termination already passed on build 16; rerun affected action surfaces on the final build.
- [ ] Restore or remove only session-created fixtures when testing is finished. Never empty Trash or clean real user caches as a substitute for validation.

## R4 — Notifications, settings and export

- [ ] Verify actual notification delivery/presentation after a real sustained rule breach. Authorization status alone is insufficient; the prior CPU test did not independently establish delivery.
- [ ] Check Focus suppression, recovery, cooldown, opt-out and permission revocation with restored test settings afterward.
- [ ] Rerun changed export controls on the final packaged build; JSON/CSV native saves and parsing already passed on build 16.
- [ ] Test native save cancellation and an authorized save-error case; verify no unwanted output or automatic retry.
- [ ] Check final-build snapshot contents and unavailable-value behavior. Snapshot copying passed on build 16; ordinary selected-text Copy passed on build 17.
- [ ] Verify launch at an actual login and registration/approval/error states. Registration Enabled → Off already passed on build 16.
- [ ] Verify preference and permission identity through the supported distribution/upgrade path. App control preferences survived the local 1.7.1 → 1.7.2 update unchanged.
- [ ] Record restoration accurately: app alerts and launch-at-login are off, appearance is System, CPU threshold is 90. OS notifications are Denied/off; the original Not Requested state cannot be restored through the normal toggle. Do not reset permission databases.

## R5 — Performance and soak

The owner accepted these limits: closed average CPU ≤2% of one core and physical footprint ≤100 MiB; open Overview average CPU ≤5% and footprint ≤250 MiB; no sustained footprint growth after warm-up. Energy is a separate check.

- [ ] Measure a controlled final-build Overview workload and compare it with the accepted limits.
- [ ] Measure the closed app after substantial UI/scan activity, with a known visibility state. The fresh closed build 17 sample passed: 0.95% CPU, maximum 17.5 MiB over 60 seconds.
- [ ] Fix any reproducible budget failure and rerun its workload; do not infer a failure from mixed/unclassified UI observations.
- [ ] Obtain suitable actual macOS energy evidence and define its acceptance criterion. Activity Monitor indicators were observed, but no controlled energy gate passed; Xcode PowerProfiler reported unsupported on macOS.
- [ ] **Restart and finish a real 24-hour observation.** The session-created run was cancelled at the owner's stop request. The observer now supports 86,400 seconds, but there is no completed 24-hour result.
- [ ] Arrange sufficient power and leave the target app running; record workload, visibility, settings, thermal/power conditions and any interruptions.
- [ ] Check post-warm-up footprint trends, responsiveness, bounded histories, process churn, wakeups and counters across the long run.
- [ ] Exercise actual sleep/wake, repeated scans, slow/changing filesystems and permitted cleanup workloads. A passive process observation does not certify these cases.

## R6 — Distribution

- [ ] Test a fresh-account/source installation and first launch.
- [ ] Test an actually downloaded/quarantined archive and its Gatekeeper path on a clean account or another Mac. The app is ad-hoc signed and not notarized; Gatekeeper assessment rejected it. Do not strip quarantine or claim trusted distribution.
- [ ] Verify upgrade from a previous distributed version, retained preferences and permission identity, with normal Quit before replacement.
- [ ] Verify the supported uninstall and reinstall workflow, including login registration and retained settings expectations.
- [ ] Install build 18 after normal Quit and recheck installed/dist/extracted archive parity. Build 18 source metadata/version/architecture/signature and dist/extracted parity passed; the installed copy remains build 17. Earlier build 17 installed parity passed.

## R7 — Compatibility

- [ ] Test other supported macOS releases, including the minimum supported macOS 14.
- [ ] Test other Apple Silicon hardware and Intel source builds where supported; the prebuilt archive is arm64, not universal.
- [ ] Test desktop/no-battery and other battery hardware, missing optional readings, legacy battery units and charge/time accuracy. This host's Power charge matched `pmset` at 25%; that is only one reading on one M4 MacBook Air.
- [ ] Test network interface appearance/removal, disconnect/reconnect and baseline resets without changing the user's network unexpectedly.
- [ ] Observe volume appearance, selection, removal and fallback in the actual app. An empty disposable disk image was mounted, but its app UI transition was not verified before stopping; unmount it as session restoration.
- [ ] Test real external-volume transitions, shared APFS capacity behavior and unavailable volumes.
- [ ] Check crowded/notched menu bars, multiple/short displays, scaling and relevant physical keyboard configurations.

## Fixes, documentation and final sign-off

- [ ] Record each verified defect, implement a targeted fix, run meaningful regressions and rerun the affected native checks.
- [x] Reconcile `ROADMAP.md`, release checklist, validation/performance records and installation/support guidance with the current candidate and actual outcomes. Session record now includes build 17 checks/parity/fresh-closed measurement/cancelled soak and the separate build 18 implementation pass. Continue updating after further outcomes.
- [x] Review remaining historical accessibility wording so it is clearly historical and cannot be mistaken for current behavior or a pending release requirement.
- [x] After the build 18 source changes, rerun full default test/build/lint/package checks and regenerate the archive with matching version metadata. Repeat after further source changes; native regression/installation gates are separate.
- [ ] Issue final sign-off only when the retained gates pass or the owner explicitly revises acceptance scope. Do not mark pending, blocked or cancelled checks as completed.

## Deferred — not required for this release

GPU utilization/memory, additional sensors/fans, accessory batteries and reliable in-app Undo/restoration remain deferred. Do not add them to the required release backlog.

## Session artifacts

Private evidence and fixture metadata are under `/private/tmp/systempulse-release-validation-20261009`. Disposable cache folders are `~/Library/Caches/local.systempulse.release-validation-20261009-a` and `-b`; they were created only for this validation. The disposable app helper is under `.build/ReleaseSafetyTarget.app`. Preserve evidence and remove only verified session-created artifacts when cleanup is authorized. SystemPulse itself should not be force-terminated to stop a validation observer.
