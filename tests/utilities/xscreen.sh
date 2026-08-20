#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: xscreen x11 diagnostic
# dotfiles-test-firejail: disabled
# dotfiles-test-case: xscreen-help-lists-commands
# dotfiles-test-case: xscreen-blink-detects-alternating-region
# dotfiles-test-case: xscreen-cursor-finds-solid-block
# dotfiles-test-case: xscreen-start-shot-stop

# Purpose: Guard the headless X display driver used for reproducible GUI/terminal
#          debugging (Xvfb + screenshots + OCR + cursor/blink analysis).

xscreen="${DOTFILES_TEST_ROOT}/utilities/bin/xscreen"

case "${DOTFILES_TEST_CASE:-}" in
xscreen-help-lists-commands)
    "$xscreen" --help >"${DOTFILES_TEST_TMP}/help.txt"
    for cmd in start stop run shot keys ocr blink cursor stack; do
        rg -q "^[[:space:]]*$cmd " "${DOTFILES_TEST_TMP}/help.txt" \
            || { printf 'help does not list command: %s\n' "$cmd" >&2; exit 1; }
    done
    ;;
xscreen-blink-detects-alternating-region)
    a="${DOTFILES_TEST_TMP}/a.png"
    b="${DOTFILES_TEST_TMP}/b.png"
    convert -size 200x100 xc:black "$b"
    convert -size 200x100 xc:black -fill white -draw 'rectangle 60,40 80,60' "$a"

    "$xscreen" blink "$a" "$b" "$a" "$b" >"${DOTFILES_TEST_TMP}/blink.json"
    python3 - <<'PY' "${DOTFILES_TEST_TMP}/blink.json"
import json, sys
data = json.load(open(sys.argv[1]))
if not data["blinking"]:
    print("blink analysis reported no blinking region", file=sys.stderr)
    sys.exit(1)
if not any(r["bbox"] for r in data["regions"]):
    print("blink analysis found no region bbox", file=sys.stderr)
    sys.exit(1)
PY
    ;;
xscreen-cursor-finds-solid-block)
    img="${DOTFILES_TEST_TMP}/cursor.png"
    convert -size 200x100 xc:black -fill white -draw 'rectangle 70,30 90,60' "$img"

    "$xscreen" cursor "$img" >"${DOTFILES_TEST_TMP}/cursor.json"
    python3 - <<'PY' "${DOTFILES_TEST_TMP}/cursor.json"
import json, sys
data = json.load(open(sys.argv[1]))
if not data:
    print("cursor analysis found no solid block", file=sys.stderr)
    sys.exit(1)
PY
    ;;
xscreen-start-shot-stop)
    display=:97
    "$xscreen" start -D "$display" --size 640x480 >/dev/null 2>&1
    shot="${DOTFILES_TEST_TMP}/shot.png"
    "$xscreen" shot -D "$display" -o "$shot" >/dev/null 2>&1
    if [ ! -s "$shot" ]; then
        printf 'screenshot was not produced\n' >&2
        "$xscreen" stop -D "$display" >/dev/null 2>&1 || true
        exit 1
    fi
    "$xscreen" stop -D "$display" >/dev/null 2>&1
    if [ -e "/tmp/.X11-unix/X${display#:}" ]; then
        printf 'Xvfb still alive after stop\n' >&2
        exit 1
    fi
    ;;
*)
    printf 'unknown test case: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
