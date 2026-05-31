#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks reaper wine firejail wwine integration shell fast
# dotfiles-test-firejail: disabled
# dotfiles-test-case: launch-reaper-linux-no-firejail-prepares-sandboxed-yabridge-env
# dotfiles-test-case: launch-reaper-linux-firejail-uses-wwine-reaper-sandbox
# dotfiles-test-case: launch-reaper-linux-firejail-sandbox-is-joinable-by-wwine

# Purpose: Integration tests for launch-reaper-linux, wwine, fj-profile-checker, and real Firejail.

skip_missing_commands() {
    local missing=0
    local command_name

    for command_name in "$@"; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            printf 'SKIP: required command not found: %s\n' "$command_name" >&2
            missing=1
        fi
    done

    [[ "$missing" -eq 0 ]] || exit 77
}

skip_missing_jinja2() {
    if ! python3 - <<'PY' >/dev/null 2>&1; then
import jinja2
PY
        printf 'SKIP: python jinja2 module is required to render templates\n' >&2
        exit 77
    fi
}

require_tools() {
    skip_missing_commands awk bash firejail grep mkdir python3 sed sleep timeout
    skip_missing_jinja2
}

make_fixture() {
    require_tools

    fixture="${DOTFILES_TEST_TMP}/fixture"
    home="${fixture}/home"
    runtime="${fixture}/runtime"
    readonly="${fixture}/readonly"
    hidden="${fixture}/hidden"
    wine_prefix="${fixture}/wine-prefix"
    sandbox_name="wwine-reaper"
    sandbox_profile="${home}/.config/firejail/wine-reaper.local"
    sandbox_check_profile="${home}/.local/share/wwine/firejail-profiles/wine-reaper.local"
    fake_wine_log="${fixture}/fake-wine.log"
    fake_reaper_log="${fixture}/fake-reaper.log"
    checker_log="${fixture}/fj-profile-checker.log"
    kitty_log="${fixture}/kitty.log"
    output="${fixture}/output.log"

    mkdir -p \
        "${home}/bin" \
        "${home}/.local/bin" \
        "${home}/.config/firejail" \
        "${home}/.local/share/wwine/firejail-profiles" \
        "${home}/data/audio-pjs" \
        "${fixture}/bin" \
        "${fixture}/fake-winever/bin" \
        "$runtime" \
        "$readonly" \
        "$hidden" \
        "$wine_prefix"

    cat >"$sandbox_profile" <<PROFILE
quiet
whitelist ${fixture}
whitelist-ro ${readonly}
blacklist ${hidden}
PROFILE
    cp "$sandbox_profile" "$sandbox_check_profile"

    cat >"${home}/bin/fj-profile-checker" <<SH
#!/usr/bin/env sh
printf '%s\n' "\$*" >> "$checker_log"
exec "${DOTFILES_TEST_ROOT}/playbooks/roles/20-dev-tools/files/fj-profile-checker" "\$@"
SH
    chmod +x "${home}/bin/fj-profile-checker"

    write_fake_programs
    render_templates
}

write_fake_programs() {
    cat >"${fixture}/fake-wine" <<SH
#!/usr/bin/env sh
inside=0
if [ -d /run/firejail/profile ] && ! ls /run/firejail/profile >/dev/null 2>&1; then
  inside=1
fi
{
  printf 'INSIDE_FIREJAIL=%s\n' "\$inside"
  printf 'WINEPREFIX=%s\n' "\${WINEPREFIX:-}"
  printf 'WINELOADER=%s\n' "\${WINELOADER:-}"
  printf 'ARGS='
  printf '<%s>' "\$@"
  printf '\n'
} >> "$fake_wine_log"
SH
    chmod +x "${fixture}/fake-wine"

    cat >"${fixture}/fake-wineserver" <<SH
#!/usr/bin/env sh
printf 'WINESERVER_ARGS=' >> "$fake_wine_log"
printf '<%s>' "\$@" >> "$fake_wine_log"
printf '\n' >> "$fake_wine_log"
SH
    chmod +x "${fixture}/fake-wineserver"

    cat >"${fixture}/fake-reaper" <<SH
#!/usr/bin/env sh
inside=0
if [ -d /run/firejail/profile ] && ! ls /run/firejail/profile >/dev/null 2>&1; then
  inside=1
fi
{
  printf 'INSIDE_FIREJAIL=%s\n' "\$inside"
  printf 'WINEPREFIX=%s\n' "\${WINEPREFIX:-}"
  printf 'WINELOADER=%s\n' "\${WINELOADER:-}"
  printf 'WWINE_USE_SANDBOX=%s\n' "\${WWINE_USE_SANDBOX:-}"
  printf 'PIPEWIRE_LATENCY=%s\n' "\${PIPEWIRE_LATENCY:-}"
  printf 'PIPEWIRE_QUANTUM=%s\n' "\${PIPEWIRE_QUANTUM:-}"
  printf 'ARGS='
  printf '<%s>' "\$@"
  printf '\n'
} >> "$fake_reaper_log"
touch "${fixture}/fake-reaper-ready"
if [ -e "${fixture}/reaper-wait" ]; then
  while [ ! -e "${fixture}/stop-reaper" ]; do
    sleep 0.05
  done
fi
SH
    chmod +x "${fixture}/fake-reaper"

    cat >"${fixture}/bin/kitty" <<SH
#!/usr/bin/env bash
set -euo pipefail
printf 'KITTY_ARGS=' >> "$kitty_log"
printf '<%s>' "\$@" >> "$kitty_log"
printf '\n' >> "$kitty_log"

cmd=()
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --hold)
      shift
      ;;
    -o)
      opt="\$2"
      printf 'KITTY_OPT=%s\n' "\$opt" >> "$kitty_log"
      if [[ "\$opt" == env=* ]]; then
        export "\${opt#env=}"
      fi
      shift 2
      ;;
    --directory=*)
      mkdir -p "\${1#--directory=}"
      cd "\${1#--directory=}"
      shift
      ;;
    --directory)
      mkdir -p "\$2"
      cd "\$2"
      shift 2
      ;;
    *)
      cmd=("\$@")
      break
      ;;
  esac
done

for i in "\${!cmd[@]}"; do
  if [[ "\${cmd[\$i]}" == /usr/bin/reaper ]]; then
    cmd[\$i]="${fixture}/fake-reaper"
  fi
done

printf 'KITTY_EXEC=' >> "$kitty_log"
printf '<%s>' "\${cmd[@]}" >> "$kitty_log"
printf '\n' >> "$kitty_log"
exec "\${cmd[@]}"
SH
    chmod +x "${fixture}/bin/kitty"

    cat >"${home}/.local/bin/connect-reaper-to-music-production" <<SH
#!/usr/bin/env sh
printf 'connect-called\n' >> "$kitty_log"
SH
    chmod +x "${home}/.local/bin/connect-reaper-to-music-production"
}

render_templates() {
    local renderer="${fixture}/render-templates.py"
    wwine="${home}/bin/wwine"
    wwine_loader="${home}/bin/wwine-wine-loader"
    launch="${home}/.local/bin/launch-reaper-linux"

    cat >"$renderer" <<'PY'
from pathlib import Path
import os
import stat

import jinja2

test_root = Path(os.environ["DOTFILES_TEST_ROOT"])
fixture = Path(os.environ["REAPER_TEST_FIXTURE"])
home = fixture / "home"
env = jinja2.Environment(undefined=jinja2.StrictUndefined, keep_trailing_newline=True)

common_context = {
    "ansible_facts": {
        "env": {
            "HOME": str(home),
            "PATH": f"{fixture / 'bin'}:/usr/bin:/bin",
        },
    },
}

wwine_template = env.from_string((test_root / "playbooks/roles/10-system-tools/templates/wwine").read_text())
wwine_rendered = wwine_template.render(
    **common_context,
    wine_env_vars={
        "WINEVERPATH": str(fixture / "fake-winever"),
        "WINELOADER": str(fixture / "fake-wine"),
        "WINESERVER": str(fixture / "fake-wineserver"),
        "WINEDLLPATH": "",
        "LD_LIBRARY_PATH": "",
        "PATH": f"{fixture / 'bin'}:{fixture}:/usr/bin:/bin",
        "WINEFSYNC": "0",
    },
    wwine_prefix_aliases={
        "reaper": {
            "path": str(fixture / "wine-prefix"),
            "architecture": "win64",
            "sandbox_profile": str(home / ".config/firejail/wine-reaper.local"),
            "sandbox_check_profile": str(home / ".local/share/wwine/firejail-profiles/wine-reaper.local"),
            "sandbox_name": "wwine-reaper",
        },
    },
)

launch_template = env.from_string((test_root / "playbooks/roles/10-system-tools/templates/launch-reaper-linux").read_text())
launch_rendered = launch_template.render(
    **common_context,
    ansible_managed="dotfiles test fixture",
    pipewire_latency_vars={
        "PIPEWIRE_LATENCY": "512/48000",
        "PIPEWIRE_QUANTUM": "512/48000",
        "PIPEWIRE_RATE": "1/48000",
    },
)

wwine_path = home / "bin/wwine"
loader_path = home / "bin/wwine-wine-loader"
launch_path = home / ".local/bin/launch-reaper-linux"
wwine_path.write_text(wwine_rendered)
loader_path.write_text(wwine_rendered)
launch_path.write_text(launch_rendered)
for path in (wwine_path, loader_path, launch_path):
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
PY

    REAPER_TEST_FIXTURE="$fixture" python3 "$renderer"
}

run_launch() {
    HOME="$home" \
    XDG_RUNTIME_DIR="$runtime" \
    PATH="${fixture}/bin:${fixture}:/usr/bin:/bin" \
    "$launch" "$@"
}

run_wwine() {
    HOME="$home" \
    XDG_RUNTIME_DIR="$runtime" \
    PATH="${fixture}/bin:${fixture}:/usr/bin:/bin" \
    "$wwine" "$@"
}

shutdown_reaper_sandbox() {
    touch "${fixture}/stop-reaper" 2>/dev/null || true
    firejail --shutdown=wwine-reaper >/dev/null 2>&1 || true
}

wait_for_sandbox() {
    local i

    for ((i = 0; i < 80; i++)); do
        if firejail --list 2>/dev/null | awk -F: '$3 == "wwine-reaper" { found = 1 } END { exit found ? 0 : 1 }'; then
            return 0
        fi
        sleep 0.05
    done

    firejail --list >&2 || true
    return 1
}

case "${DOTFILES_TEST_CASE:-}" in
launch-reaper-linux-no-firejail-prepares-sandboxed-yabridge-env)
    make_fixture

    run_launch --no-firejail -- --empty-project
    grep -Fxq "INSIDE_FIREJAIL=0" "$fake_reaper_log"
    grep -Fxq "WINEPREFIX=$wine_prefix" "$fake_reaper_log"
    grep -Fxq "WINELOADER=$wwine_loader" "$fake_reaper_log"
    grep -Fxq "WWINE_USE_SANDBOX=1" "$fake_reaper_log"
    grep -Fxq "PIPEWIRE_LATENCY=512/48000" "$fake_reaper_log"
    grep -Fxq "PIPEWIRE_QUANTUM=512/48000" "$fake_reaper_log"
    grep -Fxq "ARGS=<--empty-project>" "$fake_reaper_log"
    grep -Fq 'KITTY_EXEC=</tmp/' "$kitty_log"
    ;;
launch-reaper-linux-firejail-uses-wwine-reaper-sandbox)
    make_fixture
    trap shutdown_reaper_sandbox EXIT

    run_launch --firejail -- --new-project
    grep -Fxq "INSIDE_FIREJAIL=1" "$fake_reaper_log"
    grep -Fxq "WINEPREFIX=$wine_prefix" "$fake_reaper_log"
    grep -Fxq "WINELOADER=${fixture}/fake-wine" "$fake_reaper_log"
    grep -Fxq "WWINE_USE_SANDBOX=0" "$fake_reaper_log"
    grep -Fxq "ARGS=<--new-project>" "$fake_reaper_log"
    grep -Fq "KITTY_EXEC=<firejail><--profile=$sandbox_profile><--join-or-start=wwine-reaper><${fixture}/fake-reaper><--new-project>" "$kitty_log"
    ;;
launch-reaper-linux-firejail-sandbox-is-joinable-by-wwine)
    make_fixture
    trap shutdown_reaper_sandbox EXIT
    touch "${fixture}/reaper-wait"

    run_launch --firejail -- --live-test >"$output" 2>&1 &
    launch_pid=$!
    wait_for_sandbox

    run_wwine --prefix reaper --no-desktop --use-sandbox wine joined-from-external-host
    grep -Fxq "INSIDE_FIREJAIL=1" "$fake_wine_log"
    grep -Fxq "ARGS=<joined-from-external-host>" "$fake_wine_log"
    grep -Fq "$sandbox_check_profile" "$checker_log"
    [ "$(firejail --list 2>/dev/null | awk -F: '$3 == "wwine-reaper" { count++ } END { print count + 0 }')" -eq 1 ]

    touch "${fixture}/stop-reaper"
    wait "$launch_pid"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
