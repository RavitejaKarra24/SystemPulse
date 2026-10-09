# Phase 5 — bounded-resource and responder hardening

**Source/automated milestone: completed. Overall Phase 5: still in progress.** Verified package **1.7.1/build 16**. This milestone closes verified source-level lifetime/retention issues and adds isolated native responder checks. It does not establish actual energy, a 24-hour packaged-app soak, stable installed-popover activation or human accessibility sign-off.

## Source findings and changes

### Process icons

The previous shared dictionary retained every distinct process-icon key for the entire session. No production caller cleared it. Repeated launches from distinct executable/bundle paths could grow the cache without a bound.

`IconCache` now retains at most **512 entries**, evicting the least recently used key. Hits and replacements update recency; missing reads do not. One lock protects images and ordering, including clear. No timer, persistence, live file enumeration or new icon sampler was added. The small linear recency operation is bounded by configured capacity. Eviction changes only reusable icon retention: an icon can be resolved again if needed.

This is an **entry-count bound**, not a byte budget: `NSImage` representations and images retained by UI/OS callers have their own memory. No measured footprint/CPU/energy improvement is inferred.

### In-flight process sampling

The outer process worker previously captured the store strongly when constructing its inner weak MainActor callback. A blocked process/metadata pass therefore retained the entire store until completion.

The outer worker now captures the injected process sampler and **weak store**, just like telemetry sampling. The store retains a task handle for a non-launching join and cancels it on deallocation; synchronous OS calls are not forcibly interruptible. Existing single-in-flight and polling-generation checks still prevent overlap or stale publication across suspension/terminal stop, and resumed passes reset CPU baselines. No additional production process pass or PID query was added.

Active-lifecycle tests use a manual automatic-polling driver plus an injected synthetic process sampler. The driver prevents startup/restart/wake/visibility telemetry and volume queries; explicit test process scheduling still exercises the real single-in-flight/generation logic. Preview `startPolling: false` remains inactive, and production retains the default automatic driver.

### Lifecycle authorization refresh waiters

The notification service already coalesces its underlying query. However, every periodic AppDelegate refresh added another suspended caller while a callback was stalled; wake callbacks could add more.

`NotificationAuthorizationRefresh` bounds the AppDelegate lifecycle caller to **one in-flight task**, with no queue/replay. A 60-second acceptance cadence remains; wake can bypass cadence but not a pending operation. Invalid/retrograde clocks do not generate query spam. Terminal teardown cancels the waiter, rejects new requests and suppresses late store callbacks; weak ownership allows deallocation while a callback remains pending. Cancelling this waiter does **not** cancel a shared notification-service query or promise to interrupt the framework callback. Explicit Settings authorization and alert delivery retain their existing paths and version/permission protections.

No notification request/delivery, permission change or automatic retry was added. This bounds lifecycle waiters, not every possible interactive/service caller.

### Native editing coverage, not speculative activation changes

The existing nil-target Edit menu commands were extracted into `ApplicationEditMenu.make()` without changing their actions or shortcuts. Three new tests inspect Command-only/native nil-target selectors and exercise the actual hosted `SearchField`'s local native field editor: focus request, digit binding, Select All and selected-text replacement.

These windows remain offscreen and unactivated. Tests do not install a real application menu, post keyboard events, touch the clipboard, change preferences or use the installed app's key window. Local responder dispatch verifies the control/selector boundary, not the full OS key-equivalent or transient-popover activation path. Source review found no verified activation defect, so uncertain installed-AX observations were not used to justify an activation workaround. [The earlier installed-UI checkpoint](UI_INTERACTION_CHECKS.md) remains open where stated.

## Verification checkpoint

- Initial bounded-cache tests: **8 passing**.
- Final targeted cache/process/native-responder/authorization plus existing keyboard/lifecycle/service/Settings subset: **72 passing**, zero failures, with warnings-as-errors. **27 new regressions**: eight cache, five process/manual-driver, eleven authorization-waiter and three native-edit tests. A scoped read-only final review found no concrete introduced regressions.
- Final full suite: **390 passes + one opt-in performance skip = 391 discovered**, zero failures, including the established read-only live telemetry smoke. Format/lint, strict debug/release builds, installed-bundle/ad-hoc-signature and unpacked-archive/version checks passed. Installed/running source build and `SystemPulse.zip` match **1.7.1/build 16**. Archive SHA-256: `08b659a9955c86c35b2c852e3ae590888a6d5c14f8ff40777108d7a09dba07d7`.
- Isolated fixtures contain synthetic keys/process groups and injected pending callbacks only. No home-folder scan, user-data move, process signal, notification, login registration or global accessibility setting change.

Native Settings fixtures still emitted the previously observed contactsd/CoreData helper diagnostics while passing. No Contacts/AddressBook/CoreData API was found in app source; their root cause remains unestablished. No new UI styling/captures or live installed-app interaction/performance run was added for this source-only milestone.

## Subsequent live validation

A separately approved [1.7.1 installed-UI/short-resource checkpoint](LIVE_VALIDATION_1.7.1.md) now adds named real interaction results and closed/Overview CPU/footprint/wakeup reports with sampled context. It does not change the source/build evidence above or establish a 24-hour soak, energy budget, causal comparison or human assistive certification.

## Still-open release gates

Current packaged-app controlled CPU/footprint/wakeup/energy measurement and 24-hour sleep/wake soak; real foreground popover keys/focus; VoiceOver/Full Keyboard Access and global visual settings; native chooser/preview/Trash/restore; notification/Focus/export/login; fresh/quarantined install/upgrade and cross-hardware/OS validation. No new efficiency guarantee or completion percentage. See [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md) and [PERFORMANCE.md](PERFORMANCE.md).
