# Release hardening checklist

**Release gate: still in progress.** Version 1.7.1/build 16 delivers Phase 5 bounded-resource/native-responder hardening after the 1.7.0 native-accessibility slice, not a fully signed-off release. Four earlier implementation phases are delivered under the narrowed hardware scope; their human/hardware/resource gates remain open. No completion percentage or date is inferred.

| Gate | Status | Evidence / remaining work |
|---|---|---|
| Native source/automated hardening and current packaging | completed | 1.7.0 accessibility fixes retained; 1.7.1 bounded-icon/weak-process-worker/single-authorization-waiter and offscreen native-editing checks delivered: 27 added regressions, 72 targeted checks, current 390 full-suite passes + one opt-in skip, zero failures. Format/lint, strict debug/release builds, installed-bundle/signature/archive checks passed. [VALIDATION.md](VALIDATION.md), [resource/responder scope](LONG_SESSION_HARDENING.md). |
| Installed non-destructive UI interactions | still in progress | [Current 1.7.1 live checks](LIVE_VALIDATION_1.7.1.md) completed for native search/⌘A/replacement/clear, character-bearing topic events, chart ranges/inspection/freeze, process controls/detail, Settings sidebar/⌘W and settled reopen. Physical/visual/remaining native interactions still open. Controls unchanged; older [1.7.0 evidence](UI_INTERACTION_CHECKS.md) retains its frame-autosave caveat. Not human assistive certification. |
| VoiceOver / Full Keyboard Access / visual settings | still in progress | Guided procedure approved; user enabled VoiceOver/Control-Option and read-only setup confirmed. Spoken/focus/visual outcomes, independent keyboard-switch baseline, other surfaces and restoration still pending. [Human session](HUMAN_ACCESSIBILITY_SESSION.md), [matrix](ACCESSIBILITY.md). |
| Real filesystem, preview and destructive interaction | not started | Approved disposable chooser/Cancel/Rescan, changing/restricted folders, Quick Look/Finder, reviewed single/batch Trash/failure/Stop/sleep/normal Quit and manual Finder Put Back where available. No automated user-file operations stand in for this gate. |
| Notifications / Focus / exports / login | not started | Explicitly approved installed-app authorization/denial/delivery/Focus behavior, native save/Cancel/error workflows and login registration/approval. Existing clients are mocked in tests. |
| Controlled resources and long-session | still in progress | Current 1.7.1 closed/Overview short CPU/footprint/wakeup observations and sampled owned-UI/configuration context completed. Remaining: acceptance budget, real energy, approved scan/cleanup workloads and real 24-hour/sleep-wake soak. No causal closed/open, leak or efficiency claim. [PERFORMANCE.md](PERFORMANCE.md), [live record](LIVE_VALIDATION_1.7.1.md). |
| Fresh install / quarantined archive / upgrade | not started | Fresh account, source install, optional ad-hoc-signed archive Gatekeeper path, upgrade/preferences/permission identity and uninstall; do not blanket-remove quarantine or use elevation. Archive parity alone does not establish these flows. |
| Other hardware / OS / screen sizes | not started | macOS 14+ and Intel/Apple Silicon, desktop/battery, display/network/external-volume transitions and optional legacy battery units/missing readings. Prebuilt artifact remains arm64, not universal. |

## Safe sign-off protocol

1. Get approval for the particular real operation and record version/build, OS/hardware, settings, declared workload and expected outcome. Do not silently alter notification/accessibility/login preferences or manipulate hardware.
2. Use disposable test apps/files/cache folders; review exact paths and authorization. Never use user documents, system processes, real cache cleanup or private device enumeration merely to finish a checklist.
3. Record actual outcomes, cancellation/failure cases and observation limits. An image/build or surviving launch cannot certify keyboard, assistive technology, installation, OS dialogs or energy.
4. Restore deliberately changed test settings where approved. Do not add automatic retries, cleanup, elevation or permanent deletion. Forced termination may prevent in-flight cleanup accounting; ordinary Quit may wait for a blocked OS call.
5. Mark only the named verified gate **completed**; retain **still in progress** or **not started** for the rest. Update [ROADMAP.md](../ROADMAP.md) at every milestone.

GPU utilization/total memory, extra sensors/fans and accessory batteries are explicitly deferred, not incomplete placeholder modules to enable for sign-off. Reopening requires a separate approved API/privacy/device/resource proposal: [HARDWARE_FEASIBILITY.md](HARDWARE_FEASIBILITY.md).
