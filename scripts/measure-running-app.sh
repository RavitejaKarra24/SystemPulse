#!/usr/bin/env bash
# Opt-in observer of an already-running packaged app; never launches or controls the app.
set -euo pipefail
umask 077

usage() {
    printf '%s\n' \
        'Usage: scripts/measure-running-app.sh --pid PID --output-dir EXISTING_DIRECTORY [options]' \
        '  --duration SECONDS   30..3600 (default 60)' \
        '  --warmup SECONDS     0..300 (default 15)' \
        '  --label LABEL        Optional user declaration: 1..48 ASCII letters/digits/_/-;' \
        '                       first character must be a letter or digit.' \
        'Output must be an existing writable directory outside this repository.' \
        'Creates a unique private run folder with atomic report.json and retained logs.' \
        'Only observes the supplied PID; requires SystemPulse in an actual .app bundle.' \
        'No launch/kill, sudo, preferences, permission requests, notifications or UI changes.' \
        'CPU/footprint/package-idle wakeups are proxies, NOT energy measurements.' \
        'UI visibility and alert configuration are user-declared/unverified (label optional).'
}
fail() { printf 'Running-app probe: %s\n' "$*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PID=''
OUTPUT_DIR=''
DURATION=60
WARMUP=15
LABEL=''
SEEN=' '
while (($#)); do
    case "$1" in
        --pid|--output-dir|--duration|--warmup|--label)
            (($# >= 2)) || fail "Missing value for $1"
            [[ "$SEEN" != *" $1 "* ]] || fail "Duplicate option: $1"
            SEEN+="$1 "
            case "$1" in
                --pid) PID="$2" ;;
                --output-dir) OUTPUT_DIR="$2" ;;
                --duration) DURATION="$2" ;;
                --warmup) WARMUP="$2" ;;
                --label) LABEL="$2"
                    [[ "$LABEL" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,47}$ ]] || fail 'Invalid label' ;;
            esac
            shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; fail "Unknown argument: $1" ;;
    esac
done

# Bound digit strings before arithmetic: no overflow, octal interpretation or expressions.
[[ "$PID" =~ ^[0-9]{1,10}$ ]] || fail 'An explicit positive --pid is required'
[[ "$DURATION" =~ ^[0-9]{1,4}$ ]] || fail 'Duration must be an integer from 30 to 3600'
[[ "$WARMUP" =~ ^[0-9]{1,3}$ ]] || fail 'Warmup must be an integer from 0 to 300'
PID=$((10#$PID))
DURATION=$((10#$DURATION))
WARMUP=$((10#$WARMUP))
((PID > 0 && PID <= 2147483647)) || fail 'PID is outside the positive pid_t range'
((DURATION >= 30 && DURATION <= 3600)) || fail 'Duration must be from 30 to 3600'
((WARMUP >= 0 && WARMUP <= 300)) || fail 'Warmup must be from 0 to 300'
[[ "$(uname -s)" == Darwin ]] || fail 'macOS is required'
((EUID != 0)) || fail 'Run as the logged-in user, not root/sudo'
[[ -n "$OUTPUT_DIR" && -d "$OUTPUT_DIR" && -w "$OUTPUT_DIR" ]] || fail 'Choose an existing writable --output-dir'
[[ "$OUTPUT_DIR" != *$'\n'* && "$OUTPUT_DIR" != *$'\r'* ]] || fail 'Output path cannot contain newlines'
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"
[[ "$OUTPUT_DIR" != "$ROOT_DIR" && "$OUTPUT_DIR" != "$ROOT_DIR/"* ]] || fail 'Reports must be outside the repository'
case "$OUTPUT_DIR/" in
    /|/System/*|/Library/*|/usr/*|/bin/*|/sbin/*|/dev/*|/private/etc/*|/private/var/db/*)
        fail 'Choose a non-system output directory' ;;
esac
[[ "$OUTPUT_DIR" != / ]] || fail 'Cannot write reports at filesystem root'
command -v xcrun >/dev/null || fail 'Xcode/Command Line Tools are required'
# Inherit DEVELOPER_DIR, SDKROOT and TOOLCHAINS; never select or modify Xcode globally.
SWIFTC="$(xcrun --find swiftc)" || fail 'Swift compiler not found in the inherited toolchain'
SDK_PATH="$(xcrun --show-sdk-path)" || fail 'SDK not found in the inherited toolchain'
[[ -f "$ROOT_DIR/scripts/measure-running-app.swift" ]] || fail 'Sampler source is missing'

RUN_DIR="$(mktemp -d "$OUTPUT_DIR/systempulse-running-app.XXXXXX")"
printf 'Run folder: %s\n' "$RUN_DIR"
WORK_DIR=''
cleanup() {
    [[ -z "$WORK_DIR" ]] || rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/systempulse-running-app-work.XXXXXX")"
"$SWIFTC" --version > "$RUN_DIR/toolchain.log" 2>&1
# No package build/XCTest, no repo build caches; compiler work finishes before warmup.
if ! CLANG_MODULE_CACHE_PATH="$WORK_DIR/clang-module-cache" \
    "$SWIFTC" -sdk "$SDK_PATH" -O -warnings-as-errors -module-cache-path "$WORK_DIR/module-cache" \
    "$ROOT_DIR/scripts/measure-running-app.swift" -o "$WORK_DIR/sampler" \
    > "$RUN_DIR/compile.log" 2>&1; then
    fail "Compilation failed; see $RUN_DIR/compile.log"
fi
if ! "$WORK_DIR/sampler" "$PID" "$RUN_DIR/report.json" "$DURATION" "$WARMUP" "$LABEL" \
    > "$RUN_DIR/sampler.log" 2>&1; then
    fail "Measurement failed (no successful report); see $RUN_DIR/sampler.log"
fi
[[ -f "$RUN_DIR/report.json" && -s "$RUN_DIR/report.json" && ! -L "$RUN_DIR/report.json" ]] \
    || fail "Sampler did not publish a report; see $RUN_DIR/sampler.log"
printf 'Raw output: %s/report.json\n' "$RUN_DIR"
printf '%s\n' 'Completed. Energy not measured; UI visibility and alert configuration unverified.'
