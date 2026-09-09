#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities snippets kitty fzf xclip xdotool shell
# dotfiles-test-case: snippets-syntax
# dotfiles-test-case: snippets-panel-pick-pastes-selection
# dotfiles-test-case: snippets-lists-public-and-private
# dotfiles-test-case: snippets-direct-paste-by-name-with-vars
# dotfiles-test-case: snippets-direct-paste-expands-clipboard-regex
# dotfiles-test-case: snippets-preview-renders-clipboard-regex-expansion
# dotfiles-test-case: snippets-invalid-regex-aborts-before-paste
# dotfiles-test-case: snippets-refocus-click-for-wine-target

# Purpose: Verify the shared snippet picker metadata display and paste handoff.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/snippets"

make_fake_path() {
    local bin="${DOTFILES_TEST_TMP}/bin"

    mkdir -p "$bin"
    cat >"${bin}/kitten" <<'SH'
#!/usr/bin/env sh
set -eu

case "$1" in
quick-access-terminal)
    shift
    while [ "$#" -gt 0 ]; do
        case $1 in
        env)
            shift
            printf 'panel-start\n' >>"${DOTFILES_TEST_TMP}/events.log"
            env "$@"
            status=$?
            touch "${DOTFILES_TEST_TMP}/panel-closed"
            printf 'panel-closed\n' >>"${DOTFILES_TEST_TMP}/events.log"
            exit "$status"
            ;;
        --instance-group=*|--detach=*|--detach|--override)
            shift
            [ "${1:-}" = "--override" ] && shift || true
            ;;
        *)
            shift
            ;;
        esac
    done
    exit 2
    ;;
@)
    exit 0
    ;;
*)
    exec "$@"
    ;;
esac
SH
    chmod +x "${bin}/kitten"
    cat >"${bin}/systemd-run" <<'SH'
#!/usr/bin/env sh
set -eu

printf 'unexpected systemd-run call: %s\n' "$*" >&2
exit 2
SH
    chmod +x "${bin}/systemd-run"
    cat >"${bin}/fzf" <<'SH'
#!/usr/bin/env sh
set -eu

input_file="${DOTFILES_TEST_TMP}/fzf-input"
args_file="${DOTFILES_TEST_TMP}/fzf-args"
printf '%s\n' "$@" >"$args_file"
cat >"$input_file"
sed -n '1p' "$input_file"
SH
    chmod +x "${bin}/fzf"
    cat >"${bin}/xclip" <<'SH'
#!/usr/bin/env sh
set -eu

read_only=0
for arg in "$@"; do
    [ "$arg" = "-o" ] && read_only=1
done

if [ "$read_only" = 1 ]; then
    if [ -e "${DOTFILES_TEST_TMP}/clipboard-source.txt" ]; then
        cat "${DOTFILES_TEST_TMP}/clipboard-source.txt"
    else
        exit 1
    fi
else
    cat >"${DOTFILES_TEST_TMP}/clipboard.txt"
fi
printf 'xclip\n' >>"${DOTFILES_TEST_TMP}/events.log"
SH
    chmod +x "${bin}/xclip"
    cat >"${bin}/bat" <<'SH'
#!/usr/bin/env sh
set -eu

file=
for arg in "$@"; do
    case "$arg" in
    --*) ;;
    *) file=$arg ;;
    esac
done
cat "$file"
SH
    chmod +x "${bin}/bat"
cat >"${bin}/xdotool" <<'SH'
#!/usr/bin/env sh
set -eu

case "$*" in
"getactivewindow")
    # Return the picker window (1000) while the panel is open, then model the
    # handoff: the first poll after the panel closes still sees the picker
    # (focus-still-picker), and later polls see the previously focused window
    # (2000). Independent of how many window polls happen before the panel
    # opens (for example the launch-target capture).
    if [ ! -e "${DOTFILES_TEST_TMP}/panel-closed" ]; then
        printf '%s\n' 1000
    elif [ ! -e "${DOTFILES_TEST_TMP}/after-panel-poll" ]; then
        : >"${DOTFILES_TEST_TMP}/after-panel-poll"
        printf 'focus-still-picker\n' >>"${DOTFILES_TEST_TMP}/events.log"
        printf '%s\n' 1000
    else
        printf '%s\n' 2000
    fi
    ;;
"getwindowclassname 1000")
    printf '%s\n' "${DOTFILES_TEST_XDOTOOL_CLASS_DURING_PANEL:-kitty-snippets}"
    ;;
"getwindowclassname 2000")
    printf '%s\n' "${DOTFILES_TEST_XDOTOOL_CLASS_AFTER_PANEL:-brave-browser}"
    ;;
"key --clearmodifiers ctrl+shift+v")
    printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/xdotool-key.txt"
    printf 'paste-terminal\n' >>"${DOTFILES_TEST_TMP}/events.log"
    ;;
"key --clearmodifiers ctrl+v")
    printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/xdotool-key.txt"
    printf 'paste-browser\n' >>"${DOTFILES_TEST_TMP}/events.log"
    ;;
"getmouselocation --shell")
    printf 'X=42\nY=43\n'
    ;;
"mousemove --sync "*)
    printf 'refocus-mousemove %s %s\n' "$3" "$4" >"${DOTFILES_TEST_TMP}/refocus-point.txt"
    printf 'refocus-mousemove\n' >>"${DOTFILES_TEST_TMP}/events.log"
    ;;
"click --clearmodifiers 1")
    printf 'refocus-click\n' >>"${DOTFILES_TEST_TMP}/events.log"
    ;;
*)
    printf 'unexpected xdotool call: %s\n' "$*" >&2
    exit 2
    ;;
esac
SH
    chmod +x "${bin}/xdotool"
    printf '%s\n' "$bin"
}

write_snippet_fixture() {
    local snippets_dir="${DOTFILES_TEST_TMP}/home/dotfiles/utilities/dot-local/share/dotfiles/snippets"

    mkdir -p "$snippets_dir"
    cat >"${snippets_dir}/orchestrate-agent-tasks-reminder" <<'EOF'
---
snippet-title: Delegate agent tasks
snippet-summary: Remind the model to delegate implementation work to child agents, keep listening for follow-up prompts, parallelize with copy-* worktrees, and reuse Chromium/Playwright instances for tests.
---

Recuerda que tu trabajo es orquestar a los agentes hijos (agent-tasks) de esta sesión, las implementaciones debes delegarlas de modo que quedes libre para seguir recibiendo prompts. Cuando delegues, recuerda quedarte escuchando el state de los agentes hijos de modo que puedas enviar prompts adicionales, o bien responder preguntas y decisiones que estos agentes estén esperando (revisar agent-tasks para más información).

Recuerda que puedes paralelizar el trabajo usando los agentes hijos que están en worktrees de frontend (copy-*) que ya hemos creado con anticipación.

Recuerda que tenemos varias instancias de chromium abiertas en puertos específicos para que puedas paralelizar también los tests usando alguno de los mcps de playwright que hemos creado para esas instancias/perfiles de chromium.
EOF
    printf '%s\n' "$snippets_dir"
}

wait_for_file() {
    local path=$1
    local attempts=${2:-200}
    local attempt

    for ((attempt = 0; attempt < attempts; attempt++)); do
        [ -e "$path" ] && return 0
        sleep 0.05
    done

    return 1
}

case "${DOTFILES_TEST_CASE:-}" in
snippets-syntax)
    sh -n "$script_under_test"
    ;;
snippets-panel-pick-pastes-selection)
    bin=$(make_fake_path)
    snippets_dir=$(write_snippet_fixture)
    : >"${DOTFILES_TEST_TMP}/events.log"

    PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        DOTFILES_TEST_XDOTOOL_CLASS_AFTER_PANEL=brave-browser \
        "$script_under_test"

    wait_for_file "${DOTFILES_TEST_TMP}/clipboard.txt"
    wait_for_file "${DOTFILES_TEST_TMP}/xdotool-key.txt"

    expected_input=$(printf 'public\tDelegate agent tasks\tRemind the model to delegate implementation work to child agents, keep listening for follow-up prompts, parallelize with copy-* worktrees, and reuse Chromium/Playwright instances for tests.\torchestrate-agent-tasks-reminder\t%s\n' "${snippets_dir}/orchestrate-agent-tasks-reminder")
    expected_payload="${DOTFILES_TEST_TMP}/expected-payload"
    cat >"$expected_payload" <<'EOF'
Recuerda que tu trabajo es orquestar a los agentes hijos (agent-tasks) de esta sesión, las implementaciones debes delegarlas de modo que quedes libre para seguir recibiendo prompts. Cuando delegues, recuerda quedarte escuchando el state de los agentes hijos de modo que puedas enviar prompts adicionales, o bien responder preguntas y decisiones que estos agentes estén esperando (revisar agent-tasks para más información).

Recuerda que puedes paralelizar el trabajo usando los agentes hijos que están en worktrees de frontend (copy-*) que ya hemos creado con anticipación.

Recuerda que tenemos varias instancias de chromium abiertas en puertos específicos para que puedas paralelizar también los tests usando alguno de los mcps de playwright que hemos creado para esas instancias/perfiles de chromium.
EOF
    expected_content=$(cat "$expected_payload")
    printf '%s' "$expected_content" >"$expected_payload"
    grep -Fqx "$expected_input" "${DOTFILES_TEST_TMP}/fzf-input"
    grep -Fqx -- '--gap=1' "${DOTFILES_TEST_TMP}/fzf-args"
    cmp -s "$expected_payload" "${DOTFILES_TEST_TMP}/clipboard.txt"
    grep -Fxq 'key --clearmodifiers ctrl+v' "${DOTFILES_TEST_TMP}/xdotool-key.txt"
    [ ! -e "${DOTFILES_TEST_TMP}/systemd-run.args" ]
    rg -q '^panel-closed$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^focus-still-picker$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^xclip$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^paste-browser$' "${DOTFILES_TEST_TMP}/events.log"
    panel_closed_line=$(rg -n '^panel-closed$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    focus_still_picker_line=$(rg -n '^focus-still-picker$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    xclip_line=$(rg -n '^xclip$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    paste_line=$(rg -n '^paste-browser$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    [ "$panel_closed_line" -lt "$xclip_line" ]
    [ "$xclip_line" -lt "$focus_still_picker_line" ]
    [ "$focus_still_picker_line" -lt "$paste_line" ]
    [ "$xclip_line" -lt "$paste_line" ]
    ;;
snippets-lists-public-and-private)
    # Regression: when launched without an explicit DOTFILES_SNIPPETS_DIR the
    # picker must enumerate both the public and the private snippet roots, not
    # collapse onto a single "custom" directory.
    bin=$(make_fake_path)
    snippets_dir=$(write_snippet_fixture)
    private_dir="${DOTFILES_TEST_TMP}/home/dotfiles/for-my-eyes-only/dot-local/share/dotfiles/snippets"
    mkdir -p "$private_dir"
    cat >"${private_dir}/cf-private-snippet" <<'EOF'
---
snippet-title: Private snippet
snippet-summary: A snippet that lives in for-my-eyes-only.
---

private body text
EOF
    : >"${DOTFILES_TEST_TMP}/events.log"

    PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        DOTFILES_TEST_XDOTOOL_CLASS_AFTER_PANEL=brave-browser \
        "$script_under_test"

    wait_for_file "${DOTFILES_TEST_TMP}/fzf-input"
    grep -Fq $'public\tDelegate agent tasks\t' "${DOTFILES_TEST_TMP}/fzf-input"
    grep -Fq $'private\tPrivate snippet\t' "${DOTFILES_TEST_TMP}/fzf-input"
    ;;
snippets-direct-paste-by-name-with-vars)
    # Direct paste mode must resolve a snippet by basename, strip metadata,
    # substitute {var:KEY} placeholders from var:KEY=VALUE args, and reuse the
    # same clipboard + terminal paste handoff as the picker.
    bin=$(make_fake_path)
    snippets_dir=$(write_snippet_fixture)
    cat >"${snippets_dir}/html-local" <<'EOF'
---
snippet-title: Read later
snippet-summary: Save this conversation to re-read later.
---

Guarda esta conversación en formato markdown en este archivo: ~/data/notes/foam/agents/{var:AGENT_NAME}/{var:CWD}/{var:CHAT_ID}.md

Si el archivo ya existe actualiza con contenido nuevo.
EOF
    : >"${DOTFILES_TEST_TMP}/events.log"

    PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        DOTFILES_TEST_XDOTOOL_CLASS_DURING_PANEL=kitty \
        "$script_under_test" \
        html-local \
        var:AGENT_NAME=claude \
        var:CWD=/tmp/sandbox \
        var:CHAT_ID=abc123

    wait_for_file "${DOTFILES_TEST_TMP}/clipboard.txt"
    wait_for_file "${DOTFILES_TEST_TMP}/xdotool-key.txt"

    grep -Fqx 'Guarda esta conversación en formato markdown en este archivo: ~/data/notes/foam/agents/claude/tmp/sandbox/abc123.md' "${DOTFILES_TEST_TMP}/clipboard.txt"
    grep -Fqx 'Si el archivo ya existe actualiza con contenido nuevo.' "${DOTFILES_TEST_TMP}/clipboard.txt"
    if rg -Fq '{var:' "${DOTFILES_TEST_TMP}/clipboard.txt"; then
        printf 'unresolved {var:} placeholder in direct paste payload\n' >&2
        exit 1
    fi
    grep -Fxq 'key --clearmodifiers ctrl+shift+v' "${DOTFILES_TEST_TMP}/xdotool-key.txt"
    [ ! -e "${DOTFILES_TEST_TMP}/fzf-input" ]
    rg -q '^xclip$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^paste-terminal$' "${DOTFILES_TEST_TMP}/events.log"
    ;;
snippets-refocus-click-for-wine-target)
    # Regression: Wine/REAPER windows stop routing keyboard input to the
    # focused control once another window has taken focus. When the target
    # window class is a refocus-click class (default: reaper), snippets must
    # replay the pointer click recorded when it was summoned before sending the
    # Ctrl+V paste keystroke.
    bin=$(make_fake_path)
    snippets_dir=$(write_snippet_fixture)
    : >"${DOTFILES_TEST_TMP}/events.log"

    PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        DOTFILES_TEST_XDOTOOL_CLASS_DURING_PANEL=REAPER \
        "$script_under_test" \
        orchestrate-agent-tasks-reminder

    wait_for_file "${DOTFILES_TEST_TMP}/clipboard.txt"
    wait_for_file "${DOTFILES_TEST_TMP}/xdotool-key.txt"

    grep -Fxq 'refocus-mousemove 42 43' "${DOTFILES_TEST_TMP}/refocus-point.txt"
    grep -Fxq 'key --clearmodifiers ctrl+v' "${DOTFILES_TEST_TMP}/xdotool-key.txt"
    rg -q '^refocus-click$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^paste-browser$' "${DOTFILES_TEST_TMP}/events.log"
    refocus_click_line=$(rg -n '^refocus-click$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    paste_line=$(rg -n '^paste-browser$' "${DOTFILES_TEST_TMP}/events.log" | cut -d: -f1)
    [ "$refocus_click_line" -lt "$paste_line" ]
    ;;
snippets-direct-paste-expands-clipboard-regex)
    # Direct paste mode must expand {regex:s/.../.../} placeholders against the
    # current clipboard before copying and pasting: the payload becomes the
    # snippet body with the converted clipboard text inlined.
    bin=$(make_fake_path)
    snippets_dir=$(write_snippet_fixture)
    cat >"${snippets_dir}/regex-https" <<'EOF'
---
snippet-title: Regex clipboard
snippet-summary: Clipboard regex placeholder expansion.
---

Convierte a https estos enlaces: {regex:s/http:(.*)/https:\1/g}
EOF
    printf 'http://first.test/a\nhttp://second.test/b' >"${DOTFILES_TEST_TMP}/clipboard-source.txt"
    : >"${DOTFILES_TEST_TMP}/events.log"

    PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        DOTFILES_TEST_XDOTOOL_CLASS_DURING_PANEL=kitty \
        "$script_under_test" \
        regex-https

    wait_for_file "${DOTFILES_TEST_TMP}/clipboard.txt"
    wait_for_file "${DOTFILES_TEST_TMP}/xdotool-key.txt"

    expected_payload="${DOTFILES_TEST_TMP}/expected-payload"
    cat >"$expected_payload" <<'EOF'
Convierte a https estos enlaces: https://first.test/a
https://second.test/b
EOF
    expected_content=$(cat "$expected_payload")
    printf '%s' "$expected_content" >"$expected_payload"
    cmp -s "$expected_payload" "${DOTFILES_TEST_TMP}/clipboard.txt"
    grep -Fxq 'key --clearmodifiers ctrl+shift+v' "${DOTFILES_TEST_TMP}/xdotool-key.txt"
    if rg -Fq '{regex:' "${DOTFILES_TEST_TMP}/clipboard.txt"; then
        printf 'unresolved {regex:} placeholder in direct paste payload\n' >&2
        exit 1
    fi
    rg -q '^paste-terminal$' "${DOTFILES_TEST_TMP}/events.log"
    ;;
snippets-preview-renders-clipboard-regex-expansion)
    # The picker preview action must render the body with {regex:...}
    # placeholders already resolved against the current clipboard, so the user
    # sees the conversion result before choosing the snippet.
    bin=$(make_fake_path)
    snippets_dir=$(write_snippet_fixture)
    cat >"${snippets_dir}/regex-https" <<'EOF'
---
snippet-title: Regex clipboard
snippet-summary: Clipboard regex placeholder expansion.
---

Convierte a https estos enlaces: {regex:s/http:(.*)/https:\1/g}
EOF
    printf 'http://first.test/a\nhttp://second.test/b' >"${DOTFILES_TEST_TMP}/clipboard-source.txt"
    : >"${DOTFILES_TEST_TMP}/events.log"

    DOTFILES_SNIPPETS_ACTION=preview \
        PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        "$script_under_test" \
        "${snippets_dir}/regex-https" >"${DOTFILES_TEST_TMP}/preview.out"

    expected_payload="${DOTFILES_TEST_TMP}/expected-payload"
    cat >"$expected_payload" <<'EOF'
Convierte a https estos enlaces: https://first.test/a
https://second.test/b
EOF
    cmp -s "$expected_payload" "${DOTFILES_TEST_TMP}/preview.out"
    if rg -Fq '{regex:' "${DOTFILES_TEST_TMP}/preview.out"; then
        printf 'raw {regex:} placeholder leaked into preview\n' >&2
        exit 1
    fi
    ;;
snippets-invalid-regex-aborts-before-paste)
    # A snippet whose {regex:...} substitution does not compile must abort the
    # paste before the clipboard is overwritten or a paste keystroke is sent.
    bin=$(make_fake_path)
    snippets_dir=$(write_snippet_fixture)
    cat >"${snippets_dir}/regex-bad" <<'EOF'
---
snippet-title: Regex bad
snippet-summary: Invalid clipboard regex placeholder.
---

Mensaje {regex:s/(/x/g} final
EOF
    printf 'http://first.test/a\n' >"${DOTFILES_TEST_TMP}/clipboard-source.txt"
    : >"${DOTFILES_TEST_TMP}/events.log"

    if PATH="${bin}:/usr/bin:/bin" \
        HOME="${DOTFILES_TEST_TMP}/home" \
        DISPLAY=:99 \
        XAUTHORITY="${DOTFILES_TEST_TMP}/Xauthority" \
        DOTFILES_TEST_XDOTOOL_CLASS_DURING_PANEL=kitty \
        "$script_under_test" \
        regex-bad >"${DOTFILES_TEST_TMP}/run.out" 2>&1; then
        printf 'invalid {regex:...} placeholder should abort the paste\n' >&2
        exit 1
    fi
    [ ! -e "${DOTFILES_TEST_TMP}/clipboard.txt" ]
    [ ! -e "${DOTFILES_TEST_TMP}/xdotool-key.txt" ]
    rg -Fq 'could not expand {regex:...}' "${DOTFILES_TEST_TMP}/run.out"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
