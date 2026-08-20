#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio pipewire routing shell fast firejail
# dotfiles-test-case: set-output-route-syntax
# dotfiles-test-case: set-output-route-list-lists-physical-sinks
# dotfiles-test-case: set-output-route-status-reports-presets-and-connections
# dotfiles-test-case: set-output-route-routes-single-logical-sink
# dotfiles-test-case: set-output-route-routes-to-explicit-node
# dotfiles-test-case: set-output-route-routes-all-to-default
# dotfiles-test-case: set-output-route-unknown-target-fails

# Purpose: Verify set-output-route resolves physical sinks, reports status, and
# rewires logical sinks to studio monitors, an explicit node, or the
# WirePlumber default sink without touching the real PipeWire graph.

script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/set-output-route"

focusrite_sink='alsa_output.usb-Focusrite_Scarlett_4i4_4th_Gen_S4ENWQ4520CE64-00.pro-output-0'
motherboard_sink='alsa_output.pci-0000_06_00.6.analog-stereo'
bluetooth_sink='bluez_output.40_E6_4B_27_3C_16.1'

assert_file_contains() {
    local file=$1 pattern=$2
    rg -q --fixed-strings -- "$pattern" "$file" || {
        printf 'expected %s to contain: %s\n' "$file" "$pattern" >&2
        printf '%s\n' "--- ${file} ---" >&2
        cat "$file" >&2
        exit 1
    }
}

assert_stdout_matches() {
    local pattern=$1
    rg -q "$pattern" "$stdout" || {
        printf 'stdout missing regex: %s\n' "$pattern" >&2
        printf '%s\n' "--- stdout ---" >&2
        cat "$stdout" >&2
        exit 1
    }
}

make_fixture() {
    fixture="${DOTFILES_TEST_TMP}/set-output-route"
    bin="${fixture}/bin"
    state_dir="${fixture}/state"
    stdout="${fixture}/stdout"
    stderr="${fixture}/stderr"
    log="${fixture}/pw-link.log"
    mkdir -p "$bin" "$state_dir"

    cat >"${state_dir}/input.ports" <<'EOF'
capture.sink_node.multimedia:playback_FL
capture.sink_node.multimedia:playback_FR
capture.sink_node.work:playback_FL
capture.sink_node.work:playback_FR
capture.sink_node.music-production:playback_FL
capture.sink_node.music-production:playback_FR
capture.Mic:input_AUX0
alsa_output.usb-Focusrite_Scarlett_4i4_4th_Gen_S4ENWQ4520CE64-00.pro-output-0:playback_AUX0
alsa_output.usb-Focusrite_Scarlett_4i4_4th_Gen_S4ENWQ4520CE64-00.pro-output-0:playback_AUX1
alsa_output.pci-0000_06_00.6.analog-stereo:playback_FL
alsa_output.pci-0000_06_00.6.analog-stereo:playback_FR
bluez_output.40_E6_4B_27_3C_16.1:playback_FL
bluez_output.40_E6_4B_27_3C_16.1:playback_FR
EOF

    cat >"${state_dir}/output.ports" <<'EOF'
sink_node.multimedia:output_FL
sink_node.multimedia:output_FR
sink_node.work:output_FL
sink_node.work:output_FR
sink_node.music-production:output_FL
sink_node.music-production:output_FR
EOF

    cat >"${state_dir}/links" <<'EOF'
sink_node.multimedia:output_FL
  |-> alsa_output.pci-0000_06_00.6.analog-stereo:playback_FL
sink_node.multimedia:output_FR
  |-> alsa_output.pci-0000_06_00.6.analog-stereo:playback_FR
sink_node.work:output_FL
  |-> alsa_output.pci-0000_06_00.6.analog-stereo:playback_FL
sink_node.work:output_FR
  |-> alsa_output.pci-0000_06_00.6.analog-stereo:playback_FR
sink_node.music-production:output_FL
  |-> bluez_output.40_E6_4B_27_3C_16.1:playback_FL
sink_node.music-production:output_FR
  |-> bluez_output.40_E6_4B_27_3C_16.1:playback_FR
EOF

    printf '%s\n' "$bluetooth_sink" >"${state_dir}/default-sink"

    cat >"${bin}/pw-link" <<SH
#!/usr/bin/env sh
state_dir="\$PW_LINK_STATE_DIR"
case "\${1:-}" in
    -i)
        cat "\$state_dir/input.ports"
        ;;
    -o)
        cat "\$state_dir/output.ports"
        ;;
    -l)
        cat "\$state_dir/links" 2>/dev/null || true
        ;;
    -d)
        src=\$2
        dst=\$3
        printf 'pw-link -d %s %s\n' "\$src" "\$dst" >> "\$PW_LINK_LOG"
        awk -v s="\$src" -v d="\$dst" '
            {
                if (\$1 == "|->" && prev == s && \$2 == d) { next }
                print
                prev = \$0
            }
        ' "\$state_dir/links" > "\$state_dir/links.new"
        mv "\$state_dir/links.new" "\$state_dir/links"
        ;;
    *)
        src=\$1
        dst=\$2
        printf 'pw-link %s %s\n' "\$src" "\$dst" >> "\$PW_LINK_LOG"
        {
            cat "\$state_dir/links"
            printf '%s\\n  |-> %s\\n' "\$src" "\$dst"
        } > "\$state_dir/links.new"
        mv "\$state_dir/links.new" "\$state_dir/links"
        ;;
esac
SH
    chmod +x "${bin}/pw-link"

    cat >"${bin}/pactl" <<SH
#!/usr/bin/env sh
if [ "\${1:-}" = "get-default-sink" ]; then
    cat "\$PW_LINK_STATE_DIR/default-sink"
fi
SH
    chmod +x "${bin}/pactl"
}

run_script() {
    PATH="${bin}:$PATH" \
        PW_LINK_STATE_DIR="$state_dir" \
        PW_LINK_LOG="$log" \
        "$script" "$@" >"$stdout" 2>"$stderr"
}

case "${DOTFILES_TEST_CASE:-}" in
set-output-route-syntax)
    bash -n "$script"
    ;;
set-output-route-list-lists-physical-sinks)
    make_fixture
    run_script list
    assert_file_contains "$stdout" "$motherboard_sink"
    assert_file_contains "$stdout" "$focusrite_sink"
    assert_file_contains "$stdout" "$bluetooth_sink"
    refute rg -q 'capture\.' "$stdout"
    ;;
set-output-route-status-reports-presets-and-connections)
    make_fixture
    run_script status
    assert_file_contains "$stdout" "studio-monitors -> ${focusrite_sink}"
    assert_file_contains "$stdout" "laptop-speakers -> ${motherboard_sink}"
    assert_stdout_matches '^  default +-> bluez_output\.40_E6_4B_27_3C_16\.1$'
    assert_file_contains "$stdout" "multimedia -> ${motherboard_sink}"
    assert_file_contains "$stdout" "work -> ${motherboard_sink}"
    assert_file_contains "$stdout" "music-production -> ${bluetooth_sink}"
    ;;
set-output-route-routes-single-logical-sink)
    make_fixture
    run_script multimedia studio-monitors
    assert_file_contains "$log" "pw-link -d sink_node.multimedia:output_FL ${motherboard_sink}:playback_FL"
    assert_file_contains "$log" "pw-link -d sink_node.multimedia:output_FR ${motherboard_sink}:playback_FR"
    assert_file_contains "$log" "pw-link sink_node.multimedia:output_FL ${focusrite_sink}:playback_AUX0"
    assert_file_contains "$log" "pw-link sink_node.multimedia:output_FR ${focusrite_sink}:playback_AUX1"
    assert_file_contains "$stdout" "multimedia -> ${focusrite_sink}"
    ;;
set-output-route-routes-to-explicit-node)
    make_fixture
    run_script work "node:${motherboard_sink}"
    assert_file_contains "$log" "pw-link -d sink_node.work:output_FL ${motherboard_sink}:playback_FL"
    assert_file_contains "$log" "pw-link sink_node.work:output_FL ${motherboard_sink}:playback_FL"
    assert_file_contains "$log" "pw-link sink_node.work:output_FR ${motherboard_sink}:playback_FR"
    assert_file_contains "$stdout" "work -> ${motherboard_sink}"
    ;;
set-output-route-routes-all-to-default)
    make_fixture
    run_script all default
    assert_file_contains "$log" "pw-link sink_node.multimedia:output_FL ${bluetooth_sink}:playback_FL"
    assert_file_contains "$log" "pw-link sink_node.multimedia:output_FR ${bluetooth_sink}:playback_FR"
    assert_file_contains "$log" "pw-link sink_node.work:output_FL ${bluetooth_sink}:playback_FL"
    assert_file_contains "$log" "pw-link sink_node.work:output_FR ${bluetooth_sink}:playback_FR"
    assert_file_contains "$log" "pw-link sink_node.music-production:output_FL ${bluetooth_sink}:playback_FL"
    assert_file_contains "$log" "pw-link sink_node.music-production:output_FR ${bluetooth_sink}:playback_FR"
    assert_file_contains "$stdout" "multimedia -> ${bluetooth_sink}"
    assert_file_contains "$stdout" "work -> ${bluetooth_sink}"
    assert_file_contains "$stdout" "music-production -> ${bluetooth_sink}"
    ;;
set-output-route-unknown-target-fails)
    make_fixture
    refute run_script multimedia bogus
    assert_file_contains "$stderr" "could not resolve target: bogus"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
