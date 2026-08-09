#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio midi picker shell
# dotfiles-test-case: pedalboard-midi-profiles-central-contract
# dotfiles-test-case: pedalboard-midi-profile-picker-panel-runs-selection

# Purpose: Verify central Pedalboard MIDI profile metadata and picker dispatch.

profiles_file="${DOTFILES_TEST_ROOT}/audio/dot-local/share/dotfiles/pedalboard-midi-profiles.tsv"
profile_tool="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-profiles"
profile_script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-profile"
picker_script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/pedalboard-midi-profile-picker"

make_fake_picker_path() {
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
            printf 'panel-closed\n' >>"${DOTFILES_TEST_TMP}/events.log"
            exit "$status"
            ;;
        --instance-group=* | --detach=*)
            shift
            ;;
        --detach)
            shift
            ;;
        --override)
            shift 2
            ;;
        *)
            shift
            ;;
        esac
    done
    exit 2
    ;;
*)
    exec "$@"
    ;;
esac
SH
    chmod +x "${bin}/kitten"
    cat >"${bin}/fzf" <<'SH'
#!/usr/bin/env sh
set -eu

printf '%s\n' "$@" >"${DOTFILES_TEST_TMP}/fzf-args"
cat >"${DOTFILES_TEST_TMP}/fzf-input"
grep '^obs	' "${DOTFILES_TEST_TMP}/fzf-input"
SH
    chmod +x "${bin}/fzf"
    cat >"${bin}/pedalboard-midi-profile" <<'SH'
#!/usr/bin/env sh
set -eu

printf '%s\n' "$*" >"${DOTFILES_TEST_TMP}/profile-command.args"
SH
    chmod +x "${bin}/pedalboard-midi-profile"
    printf '%s\n' "$bin"
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
pedalboard-midi-profiles-central-contract)
    bash -n "$profile_tool"
    bash -n "$profile_script"
    sh -n "$picker_script"

    PEDALBOARD_MIDI_PROFILES_FILE="$profiles_file" "$profile_tool" list >"${DOTFILES_TEST_TMP}/profiles.out"
    grep -Fqx $'1\tpiano\tpiano\t1\t64\t66\t67\tmomentary\tmomentary\tpiano\t-' "${DOTFILES_TEST_TMP}/profiles.out"
    grep -Fqx $'2\tguitar\tguitar\t2\t4\t80\t81\tlatch\tlatch\tguitar\t-' "${DOTFILES_TEST_TMP}/profiles.out"
    grep -Fqx $'3\tdesktop\tdesktop\t16\t4\t80\t81\tmomentary\tmomentary\tdesktop\t-' "${DOTFILES_TEST_TMP}/profiles.out"
    grep -Fqx $'4\tobs-mouseless-setup\tobs\t15\t4\t80\t81\tmomentary\tmomentary\tobs-mouseless-setup\tobs' "${DOTFILES_TEST_TMP}/profiles.out"

    PEDALBOARD_MIDI_PROFILES_FILE="$profiles_file" "$profile_tool" get obs >"${DOTFILES_TEST_TMP}/obs.out"
    grep -Fqx $'4\tobs-mouseless-setup\tobs\t15\t4\t80\t81\tmomentary\tmomentary\tobs-mouseless-setup\tobs' "${DOTFILES_TEST_TMP}/obs.out"
    PEDALBOARD_MIDI_PROFILES_FILE="$profiles_file" "$profile_tool" cc 16 80 >"${DOTFILES_TEST_TMP}/desktop-switch.out"
    grep -Fqx $'3\tdesktop\tdesktop\t16\t4\t80\t81\tmomentary\tmomentary\tdesktop\t-\tswitch1' "${DOTFILES_TEST_TMP}/desktop-switch.out"
    PEDALBOARD_MIDI_PROFILES_FILE="$profiles_file" "$profile_tool" action-mappers >"${DOTFILES_TEST_TMP}/action-mappers.out"
    grep -Fqx 'piano' "${DOTFILES_TEST_TMP}/action-mappers.out"
    grep -Fqx 'guitar' "${DOTFILES_TEST_TMP}/action-mappers.out"
    grep -Fqx 'desktop' "${DOTFILES_TEST_TMP}/action-mappers.out"
    grep -Fqx 'obs-mouseless-setup' "${DOTFILES_TEST_TMP}/action-mappers.out"

    # Regression: every profile must have a non-empty action_profile so that
    # pedalboard-midi-profile always starts a host listener.  Instrument
    # profiles without a host action mapper break TFT pedal feedback.
    PEDALBOARD_MIDI_PROFILES_FILE="$profiles_file" "$profile_tool" list | \
      awk -F'\t' '$10 == "-" { print "profile " $2 " has no action mapper" }' >"${DOTFILES_TEST_TMP}/orphan-profiles.txt"
    [[ ! -s "${DOTFILES_TEST_TMP}/orphan-profiles.txt" ]] || {
      cat "${DOTFILES_TEST_TMP}/orphan-profiles.txt" >&2
      exit 1
    }

    # Guard: every profile must appear in action-mappers.
    profile_count=$(wc -l <"${DOTFILES_TEST_TMP}/profiles.out")
    mapper_count=$(wc -l <"${DOTFILES_TEST_TMP}/action-mappers.out")
    [[ "$profile_count" -eq "$mapper_count" ]]

    PEDALBOARD_MIDI_PROFILES_FILE="$profiles_file" PEDALBOARD_MIDI_PROFILES_COMMAND="$profile_tool" "$profile_script" --dry-run obs >"${DOTFILES_TEST_TMP}/obs-profile.out"
    rg -q '^serial profile obs-mouseless-setup$' "${DOTFILES_TEST_TMP}/obs-profile.out"
    rg -q '^systemctl --user start pedalboard-midi-actions@obs-mouseless-setup.service$' "${DOTFILES_TEST_TMP}/obs-profile.out"
    ;;
pedalboard-midi-profile-picker-panel-runs-selection)
    bin=$(make_fake_picker_path)
    : >"${DOTFILES_TEST_TMP}/events.log"

    PATH="${bin}:/usr/bin:/bin" \
      HOME="${DOTFILES_TEST_TMP}/home" \
      PEDALBOARD_MIDI_PROFILES_FILE="$profiles_file" \
      PEDALBOARD_MIDI_PROFILES_COMMAND="$profile_tool" \
      PEDALBOARD_MIDI_PROFILE_COMMAND="${bin}/pedalboard-midi-profile" \
      "$picker_script"

    wait_for_file "${DOTFILES_TEST_TMP}/profile-command.args"
    grep -Fxq 'obs-mouseless-setup' "${DOTFILES_TEST_TMP}/profile-command.args"
    grep -Fqx $'obs\tobs-mouseless-setup\tch 15 / CC 4,80,81\thost actions: obs-mouseless-setup\tobs-mouseless-setup' "${DOTFILES_TEST_TMP}/fzf-input"
    grep -Fqx -- '--preview-label= profile ' "${DOTFILES_TEST_TMP}/fzf-args"
    rg -q '^panel-start$' "${DOTFILES_TEST_TMP}/events.log"
    rg -q '^panel-closed$' "${DOTFILES_TEST_TMP}/events.log"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
