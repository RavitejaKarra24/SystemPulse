# Feasible TODO implementation — 9 October 2026

**Candidate: SystemPulse 1.7.2/build 18, arm64, ad-hoc signed. Installed app: 1.7.2/build 17, unchanged. Final release sign-off remains pending.** This pass implements safe source/test/documentation work requested by the owner. It does not resume the stopped native validation session or withdraw any retained acceptance gate.

## Reproduced defects and fixes

- **Incomplete fractional drafts:** Foundation accepted a trailing decimal separator, including forms such as `900.` and localized `900,e2`. Numeric validation now requires a fractional digit after the locale's separator. Rejected text remains available for correction and does not save preferences.
- **Locale changes during editing:** a preserved comma-decimal draft was parsed using the newly selected locale and rejected. Draft state now retains the locale that produced its text, parses with that locale until commit/cancel, then reformats with the latest locale. Untouched drafts still preserve precision and newer external values.
- **Archive verification gap:** the previous verifier checked the marketing version only. A same-version/wrong-build archive could pass. It now compares the complete source plist, requires the executable/icon, reports architecture, and supports read-only full bundle payload comparison. [Commands and limits](ARTIFACT_VERIFICATION.md).

Seven added Swift regressions cover incomplete/localized fractions, timing ranges, locale transitions, correction/cancel, precision/external updates and keyboard responder transitions. No additional keyboard-routing defect was verified. Ten new disposable Python regressions cover artifact metadata/payload parity. Neither suite certifies physical keyboards or installed native interactions.

## Checks actually run

On the existing M4 MacBook Air/macOS 27.0.1 host, using the full Xcode toolchain via a **process-scoped** `DEVELOPER_DIR`:

| Check | Observed result |
|---|---|
| `make -j1 check` | 393 Swift tests discovered/executed: **391 passes, two opt-in skips, zero failures**. Live telemetry smoke and performance probe were not opted in. Three installer safety and ten artifact-parity regressions passed separately. Strict debug build passed. |
| `make -j1 lint` | Strict Swift formatting/lint and shell syntax passed. |
| `swift build -c release -Xswiftc -warnings-as-errors` | Passed. |
| `SKIP_LOCAL_INSTALL=1 make -j1 zip` | Rebuilt candidate bundle/archive; plist and signatures verified, including after extraction. Installed app was not replaced. |
| Archive verifier with `--compare-app dist/SystemPulse.app` | Passed: full source plist metadata and all candidate/extracted bundle entries match; architecture arm64. Also passed under macOS `/bin/bash` (3.2), with and without comparison arguments. |
| New Python `ruff check` / `ruff format --check`; `git diff --check` | Passed. |
| Installed artifact identity | Still build 17 with the previously recorded executable hash; no candidate installation or installed parity pass claimed. |

The initial default-toolchain check failed before tests because the selected Command Line Tools SDK could not load `SwiftUIMacros.StateMacro`. The retry with full Xcode passed; no global `xcode-select` change or product workaround was made. Native fixture rendering also emitted host contact-helper diagnostics, as in earlier sessions; the tests passed and no cause or permission change is claimed.

Reproduction:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make -j1 check
make -j1 lint
swift build -c release -Xswiftc -warnings-as-errors
SKIP_LOCAL_INSTALL=1 make -j1 zip
./scripts/verify-committed-zip.sh --compare-app dist/SystemPulse.app
```

## Artifact identity

- Archive SHA-256: `e76793d20f2d755dc6d3f98b414944fb7f1ebf75c3272f8eefe8ce3306920357`.
- Candidate executable SHA-256: `7c7a4663238d27555a971206a553c452ae894c0757678d8fdf6b27dc68739184`.
- Unchanged installed build 17 executable SHA-256: `54eb5896d9484555c96dc651064de6647e6fb54679501779ab1b75ce208dbfb6`.
- Bundle identifier remains `local.systempulse.monitor`; no TeamIdentifier/Developer ID or notarization was added. Ad-hoc signature validity is not Gatekeeper trust.

Private raw successful-run stdout/stderr and the initial toolchain-failure log were retained under `/private/tmp/systempulse-build18-validation.cWb4F9` with private permissions. Earlier session evidence and fixtures were preserved. No raw private host logs are committed here.

## Completed documentation work and remaining limits

The roadmap, release checklist, validation/performance records and support guidance now distinguish the build 18 candidate from installed build 17 evidence. The older session record includes the actual build 17 checks/parity, fresh-closed short-window result and **CANCELLED** soak. Historical accessibility material is clearly withdrawn; no accessibility features were added or re-enabled.

No OS permissions/settings were changed, real notifications delivered, login registration modified, user caches scanned/cleaned, real Trash/process actions performed, app force-terminated, network/volume/sleep state changed or 24-hour observer started by this pass. Tests use disposable fixtures and injected clients for those actions; they are not native workflow evidence.

Build 18 still needs authorized installation after normal Quit, installed parity and affected numeric/native UI checks. Remaining physical/hardware, destructive-action, notification/login/save, controlled performance/energy, real 24-hour soak and quarantined/fresh-account distribution checks stay open in [todo.md](../todo.md). The build 17 fresh-closed resource pass does not certify candidate performance. No pending, blocked or cancelled gate was marked passed.
