#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio latency shell fast firejail
# dotfiles-test-case: audio-latency-set-syncs-runtime-state
# dotfiles-test-case: audio-latency-status-reports-runtime-state

script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/audio-latency"

assert_file_contains() {
    local file=$1 pattern=$2
    rg -q --fixed-strings "$pattern" "$file" || {
        printf 'expected %s to contain: %s\n' "$file" "$pattern" >&2
        printf '%s\n' "--- ${file} ---" >&2
        cat "$file" >&2
        exit 1
    }
}

make_fixture() {
    fixture="${DOTFILES_TEST_TMP}/audio-latency"
    home="${fixture}/home"
    xdg_config="${fixture}/config"
    xdg_state="${fixture}/state"
    bin="${fixture}/bin"
    wine_prefix="${fixture}/wine-prefix"
    defaults_file="${xdg_config}/dotfiles/audio-latency.defaults.env"
    reaper_ini="${wine_prefix}/drive_c/users/tester/AppData/Roaming/REAPER/REAPER.ini"
    wwine_log="${fixture}/wwine.log"
    pw_metadata_log="${fixture}/pw-metadata.log"

    mkdir -p \
        "$home/bin" \
        "${xdg_config}/dotfiles" \
        "$xdg_config/pipeasio" \
        "$xdg_state" \
        "$bin" \
        "$(dirname "$reaper_ini")"

    cat >"$defaults_file" <<'ENV'
AUDIO_LATENCY_DEFAULT_BUFFER=2048
AUDIO_LATENCY_DEFAULT_RATE=48000
PIPEWIRE_LATENCY=2048/48000
PIPEWIRE_QUANTUM=2048/48000
PIPEWIRE_RATE=1/48000
WINEASIO_PREFERRED_BUFFERSIZE=2048
ENV

    cat >"${xdg_config}/pipeasio/config.ini" <<'INI'
# PipeASIO settings - managed by dotfiles
[pipeasio]
inputs = 2
outputs = 2
buffer_size = 1024
fixed_buffer_size = 1
sample_rate = 0
auto_connect = 1
follow_device_clock = 0
output_device =
input_device =
node_name =
INI

    cat >"$reaper_ini" <<'INI'
[audioconfig]
mode=3
asio_bsize=1024
asio_bsize_use=1
asio_srate=44100
asio_srate_use=1
[other]
asio_bsize=999
INI

    cat >"${home}/bin/wwine" <<SH
#!/usr/bin/env sh
printf 'wwine' >> "$wwine_log"
printf ' <%s>' "\$@" >> "$wwine_log"
printf '\n' >> "$wwine_log"
SH
    chmod +x "${home}/bin/wwine"

    cat >"${bin}/pw-metadata" <<SH
#!/usr/bin/env sh
if [ "\${1:-}" = "-n" ] && [ "\${2:-}" = "settings" ] && [ "\${3:-}" = "0" ] && [ "\${4:-}" = "" ]; then
  cat <<'EOF'
Found "settings" metadata 36
update: id:0 key:'clock.rate' value:'48000' type:''
update: id:0 key:'clock.quantum' value:'768' type:''
update: id:0 key:'clock.force-quantum' value:'0' type:''
EOF
  exit 0
fi
printf 'pw-metadata' >> "$pw_metadata_log"
printf ' <%s>' "\$@" >> "$pw_metadata_log"
printf '\n' >> "$pw_metadata_log"
SH
    chmod +x "${bin}/pw-metadata"
}

run_audio_latency() {
    HOME="$home" \
        USER=tester \
        XDG_CONFIG_HOME="$xdg_config" \
        XDG_STATE_HOME="$xdg_state" \
        REAPER_WINE_PREFIX="$wine_prefix" \
        PATH="${bin}:$PATH" \
        "$script" "$@"
}

case "${DOTFILES_TEST_CASE:-}" in
audio-latency-set-syncs-runtime-state)
    make_fixture
    run_audio_latency set 256 >"${fixture}/set.out"

    state_file="${xdg_state}/dotfiles/audio-latency.env"
    pipeasio_config="${xdg_config}/pipeasio/config.ini"
    assert_file_contains "$defaults_file" "AUDIO_LATENCY_DEFAULT_BUFFER=2048"
    assert_file_contains "$state_file" "AUDIO_LATENCY_BUFFER=256"
    assert_file_contains "$state_file" "AUDIO_LATENCY_RATE=48000"
    assert_file_contains "$state_file" "PIPEWIRE_LATENCY=256/48000"
    assert_file_contains "$state_file" "PIPEWIRE_QUANTUM=256/48000"
    assert_file_contains "$state_file" "PIPEWIRE_RATE=1/48000"
    assert_file_contains "$state_file" "WINEASIO_PREFERRED_BUFFERSIZE=256"

    assert_file_contains "$pipeasio_config" "buffer_size = 256"
    assert_file_contains "$reaper_ini" "asio_bsize=256"
    assert_file_contains "$reaper_ini" "asio_bsize_use=1"
    assert_file_contains "$reaper_ini" "asio_srate=48000"
    assert_file_contains "$reaper_ini" "asio_srate_use=1"
    assert_file_contains "$reaper_ini" "[other]"
    assert_file_contains "$reaper_ini" "asio_bsize=999"
    assert_file_contains "$wwine_log" "wwine <--prefix> <reaper> <--wine-debug> <-all> <wine> <reg> <add> <HKCU\\Software\\Wine\\WineASIO> </v> <Preferred buffersize> </t> <REG_DWORD> </d> <256> </f>"
    assert_file_contains "$pw_metadata_log" "pw-metadata <-n> <settings> <0> <clock.quantum> <256>"
    assert_file_contains "$pw_metadata_log" "pw-metadata <-n> <settings> <0> <clock.force-quantum> <0>"
    assert_file_contains "${fixture}/set.out" "audio latency set to 256/48000"
    ;;
audio-latency-status-reports-runtime-state)
    make_fixture
    mkdir -p "${xdg_state}/dotfiles"
    cat >"${xdg_state}/dotfiles/audio-latency.env" <<'ENV'
AUDIO_LATENCY_BUFFER=1024
AUDIO_LATENCY_RATE=48000
PIPEWIRE_LATENCY=1024/48000
PIPEWIRE_QUANTUM=1024/48000
PIPEWIRE_RATE=1/48000
WINEASIO_PREFERRED_BUFFERSIZE=1024
ENV
    run_audio_latency status >"${fixture}/status.out"
    assert_file_contains "${fixture}/status.out" "defaults:   2048/48000 (${defaults_file})"
    assert_file_contains "${fixture}/status.out" "state:      1024/48000 (${xdg_state}/dotfiles/audio-latency.env)"
    assert_file_contains "${fixture}/status.out" "pipewire:   quantum=768"
    assert_file_contains "${fixture}/status.out" "pipeasio:   buffer_size=1024 (${xdg_config}/pipeasio/config.ini)"
    assert_file_contains "${fixture}/status.out" "reaper ini: asio_bsize=1024 asio_srate=44100 (${reaper_ini})"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
