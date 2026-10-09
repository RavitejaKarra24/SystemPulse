#!/usr/bin/env bash
# Opt-in Phase 3 process probe. No app installation, notification service or user-preference access.
# Default matrix: five sequential, independent RELEASE XCTest subprocesses (never --parallel).
set -euo pipefail
umask 077

usage() {
    printf '%s\n' \
        'Usage: scripts/measure-performance.sh --output-dir EXISTING_DIRECTORY [options]' \
        '  --duration SECONDS   Measurement per scenario: 30..3600 (default 60)' \
        '  --warmup SECONDS     Warmup per scenario: 15..300 (default 15)' \
        '  --scenario NAME      Run only one scenario; otherwise run all five sequentially' \
        'Scenarios: hidden-default hidden-disk-menu hidden-alerts hidden-disk-alert open-overview' \
        'Output directory must be writable and outside the repository/system directories.' \
        'A private, unique run folder holds JSON and logs; existing files are never overwritten.' \
        'Run on an idle Mac in a logged-in GUI session; do not cover/interact with Overview.' \
        'These are process CPU/footprint/package-idle-wakeup proxies, NOT energy/joules.'
}
fail() { printf 'Performance probe: %s\n' "$*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
OUTPUT_DIR=''
DURATION="${SYSTEMPULSE_PERFORMANCE_DURATION:-60}"
WARMUP="${SYSTEMPULSE_PERFORMANCE_WARMUP:-15}"
SELECTED=''
while (($#)); do
    case "$1" in
        --output-dir|--duration|--warmup|--scenario)
            (($# >= 2)) || fail "Missing value for $1"
            case "$1" in
                --output-dir) OUTPUT_DIR="$2" ;;
                --duration) DURATION="$2" ;;
                --warmup) WARMUP="$2" ;;
                --scenario) SELECTED="$2" ;;
            esac
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; fail "Unknown argument: $1" ;;
    esac
done

# Bound strings before arithmetic, avoiding overflow, octal parsing, expressions and huge runs.
[[ "$DURATION" =~ ^[0-9]{1,4}$ ]] || fail 'Duration must be an integer from 30 to 3600'
[[ "$WARMUP" =~ ^[0-9]{1,3}$ ]] || fail 'Warmup must be an integer from 15 to 300'
DURATION=$((10#$DURATION))
WARMUP=$((10#$WARMUP))
((DURATION >= 30 && DURATION <= 3600)) || fail 'Duration must be from 30 to 3600'
((WARMUP >= 15 && WARMUP <= 300)) || fail 'Warmup must be from 15 to 300'
SCENARIOS=(hidden-default hidden-disk-menu hidden-alerts hidden-disk-alert open-overview)
if [[ -n "$SELECTED" ]]; then
    case "$SELECTED" in
        hidden-default|hidden-disk-menu|hidden-alerts|hidden-disk-alert|open-overview) SCENARIOS=("$SELECTED") ;;
        *) fail "Unknown scenario: $SELECTED" ;;
    esac
fi

[[ "$(uname -s)" == Darwin ]] || fail 'macOS 14+ is required'
command -v swift >/dev/null || fail 'Swift/Xcode toolchain not found'
[[ -n "$OUTPUT_DIR" && -d "$OUTPUT_DIR" && -w "$OUTPUT_DIR" ]] || fail 'Choose an existing writable output directory'
[[ "$OUTPUT_DIR" != *$'\n'* && "$OUTPUT_DIR" != *$'\r'* ]] || fail 'Output path cannot contain newlines'
# Canonicalize existing directory before policy checks; symlinks cannot bypass protected paths.
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
case "$OUTPUT_DIR/" in
    /|/System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/dev/*|/private/etc/*|/private/var/db/*)
        fail "Unsafe output directory: $OUTPUT_DIR" ;;
esac
[[ "$OUTPUT_DIR" != / ]] || fail 'Cannot write reports at filesystem root'
[[ "$OUTPUT_DIR" != "$ROOT_DIR" && "$OUTPUT_DIR" != "$ROOT_DIR/"* ]] || fail 'Reports must be outside the repository'
[[ -f "$ROOT_DIR/Tests/SystemPulseTests/PerformanceProbeTests.swift" ]] || fail 'Probe test file is missing'

# The test records this toolchain plus OS/runtime metadata. All builds/caches are private to this run.
TOOLCHAIN="$(swift --version 2>&1)"
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/systempulse-performance-work.XXXXXX")"
WORK_DIR="$(cd "$WORK_DIR" && pwd -P)"
STAGING_DIR=''
cleanup() {
    [[ -z "$STAGING_DIR" ]] || rm -rf -- "$STAGING_DIR"
    rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
RUN_DIR="$(mktemp -d "$OUTPUT_DIR/systempulse-performance.XXXXXX")"
STAGING_DIR="$(mktemp -d "$RUN_DIR/.staging.XXXXXX")"
printf 'Reports: %s\nDuration: %ss + %ss warmup per scenario\n' "$RUN_DIR" "$DURATION" "$WARMUP"
printf '%s\n' "$TOOLCHAIN" > "$RUN_DIR/toolchain.txt"

cd "$ROOT_DIR"
for scenario in "${SCENARIOS[@]}"; do
    printf 'Running %s (release, independent subprocess)…\n' "$scenario"
    # Reuse compiled artifacts, not processes/stores/caches/timers. No other test class executes.
    # Do not inherit screenshot/live-smoke opt-ins. Redirect instead of streaming logs while measuring.
    if ! env -u SYSTEMPULSE_SCREENSHOT_DIR -u SYSTEMPULSE_LIVE_SMOKE \
        SYSTEMPULSE_PERFORMANCE_SCENARIO="$scenario" \
        SYSTEMPULSE_PERFORMANCE_OUTPUT="$STAGING_DIR/$scenario.json" \
        SYSTEMPULSE_PERFORMANCE_DURATION="$DURATION" \
        SYSTEMPULSE_PERFORMANCE_WARMUP="$WARMUP" \
        SYSTEMPULSE_PERFORMANCE_TOOLCHAIN="$TOOLCHAIN" \
        SWIFT_MODULE_CACHE_PATH="$WORK_DIR/module-cache" \
        CLANG_MODULE_CACHE_PATH="$WORK_DIR/clang-module-cache" \
        swift test -c release --scratch-path "$WORK_DIR/build" --filter PerformanceProbeTests \
        > "$RUN_DIR/$scenario.log" 2>&1; then
        fail "$scenario failed; see $RUN_DIR/$scenario.log (completed reports retained)"
    fi
    [[ -f "$STAGING_DIR/$scenario.json" && -s "$STAGING_DIR/$scenario.json" && ! -L "$STAGING_DIR/$scenario.json" ]] \
        || fail "$scenario did not produce a regular JSON report; see $RUN_DIR/$scenario.log"
    # Staging and reports share a filesystem; rename publishes the already-atomically-written JSON.
    mv -- "$STAGING_DIR/$scenario.json" "$RUN_DIR/$scenario.json"
    printf '  %s\n' "$RUN_DIR/$scenario.json"
done
printf 'Finished %s scenario(s). No energy/joules inference; compare only like-for-like runs.\n' "${#SCENARIOS[@]}"
