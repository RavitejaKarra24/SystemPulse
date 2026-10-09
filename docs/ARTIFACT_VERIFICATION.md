# Read-only artifact verification

`make verify-zip` extracts `SystemPulse.zip` into a disposable temporary directory, verifies its ad-hoc signature, checks **all** source plist metadata (including version, build and bundle identity), requires the executable/icon, and reports its Mach-O architectures. It neither installs nor launches the app.

To also compare the archive against the built and installed bundles:

```sh
make verify-parity
```

This compares every bundle entry: relative paths, regular-file SHA-256 digests, executable bits and symlink targets, including resources and code-signature payloads. Missing bundles, extra entries and mismatches fail closed. File timestamps and non-executable permission bits are not compared.

An older installed app should fail parity. Do not replace a running app just to make this check pass: normal Quit must drain any in-flight cleanup before explicit installation. This check never terminates the app or removes quarantine.

For a source rebuild without changing the installed app:

```sh
SKIP_LOCAL_INSTALL=1 make zip
./scripts/verify-committed-zip.sh --compare-app dist/SystemPulse.app
```

A source rebuild is needed before claiming source/artifact correspondence; matching plist metadata alone does not prove that the archive contains the latest Swift code. Installed parity is a separate check after an authorized installation.

`make check` includes ten disposable artifact-parity regressions, alongside the Swift suite and installer safety checks. These cover matching payloads, semantic plist comparison, same-version/wrong-build archives, wrong bundle identity, stale executables, missing/changed/extra resources, executable modes, symlinks and missing comparison bundles.

Passing these checks does **not** certify Gatekeeper trust, notarization, a downloaded/quarantined first launch, UI behavior, permission persistence, performance or a 24-hour soak. Those remain separate release gates in [`../todo.md`](../todo.md).
