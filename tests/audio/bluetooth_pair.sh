#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio bluetooth shell fast firejail
# dotfiles-test-case: bluetooth-pair-syntax
# dotfiles-test-case: bluetooth-pair-does-not-require-persistent-default-agent
# dotfiles-test-case: bluetooth-pair-picker-pairs-selected-device
# dotfiles-test-case: bluetooth-pair-skips-already-paired-device
# dotfiles-test-case: bluetooth-pair-reports-bluez-action-error
# dotfiles-test-case: bluetooth-pair-repairs-stale-pairing-timeout
# dotfiles-test-case: bluetooth-pair-waits-after-removing-stale-pairing

# Purpose: Verify the terminal Bluetooth pairing helper without touching the real BlueZ daemon.

script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/bluetooth-pair"

assert_file_contains() {
    local file=$1 pattern=$2
    rg -q --fixed-strings -- "$pattern" "$file" || {
        printf 'expected %s to contain: %s\n' "$file" "$pattern" >&2
        printf '%s\n' "--- ${file} ---" >&2
        cat "$file" >&2
        exit 1
    }
}

assert_file_not_contains() {
    local file=$1 pattern=$2
    ! rg -q --fixed-strings -- "$pattern" "$file" || {
        printf 'expected %s not to contain: %s\n' "$file" "$pattern" >&2
        printf '%s\n' "--- ${file} ---" >&2
        cat "$file" >&2
        exit 1
    }
}

assert_file_lacks_line() {
    local file=$1 line=$2
    ! awk -v expected="$line" '$0 == expected { found = 1 } END { exit found ? 0 : 1 }' "$file" || {
        printf 'expected %s not to contain line: %s\n' "$file" "$line" >&2
        printf '%s\n' "--- ${file} ---" >&2
        cat "$file" >&2
        exit 1
    }
}

make_fixture() {
    fixture="${DOTFILES_TEST_TMP}/bluetooth-pair"
    bin="${fixture}/bin"
    log="${fixture}/bluetoothctl.log"
    mkdir -p "$bin"
    : >"$log"

    cat >"${bin}/sleep" <<'SH'
#!/usr/bin/env sh
exit 0
SH
    chmod +x "${bin}/sleep"
}

write_fake_fzf() {
    local selected_mac=$1
    cat >"${bin}/fzf" <<SH
#!/usr/bin/env bash
set -euo pipefail
rows="\${BLUETOOTH_PAIR_TEST_FZF_ROWS}"
cat >"\$rows"
awk -F '\t' -v selected="$selected_mac" '\$1 == selected { print; found = 1; exit } END { exit found ? 0 : 1 }' "\$rows"
SH
    chmod +x "${bin}/fzf"
}

write_fake_bluetoothctl() {
    local pair_state=$1 trust_state=$2 connect_state=$3 pair_failure=${4:-}
    cat >"${bin}/bluetoothctl" <<SH
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "\$*" >>"${log}"

if [ "\$#" -eq 0 ]; then
  while IFS= read -r command; do
    printf 'interactive:%s\n' "\$command" >>"${log}"
  done
  exit 0
fi

case "\$*" in
  "agent on"|"default-agent")
    printf 'No agent is registered\n'
    exit 1
    ;;
  "power on"|"scan on"|"scan off")
    printf 'Changing %s succeeded\n' "\$1"
    ;;
  "devices")
    printf 'Device 88:C9:E8:E7:C6:FC WF-1000XM4\n'
    printf 'Device 44:55:66:77:88:99 LE_WF-1000XM4\n'
    ;;
  "info 88:C9:E8:E7:C6:FC")
    cat <<'EOF'
Device 88:C9:E8:E7:C6:FC (public)
	Name: WF-1000XM4
	Paired: ${pair_state}
	Trusted: ${trust_state}
	Connected: ${connect_state}
EOF
    ;;
  "info 44:55:66:77:88:99")
    cat <<'EOF'
Device 44:55:66:77:88:99 (public)
	Name: LE_WF-1000XM4
	Paired: no
	Trusted: no
	Connected: no
EOF
    ;;
  "--agent NoInputNoOutput pair 88:C9:E8:E7:C6:FC")
    if [ -n "${pair_failure}" ]; then
      printf '%s\n' "${pair_failure}"
      exit 1
    fi
    printf 'Pairing successful\n'
    ;;
  "trust 88:C9:E8:E7:C6:FC")
    printf 'Changing 88:C9:E8:E7:C6:FC trust succeeded\n'
    ;;
  "connect 88:C9:E8:E7:C6:FC")
    printf 'Connection successful\n'
    ;;
  *)
    printf 'unexpected bluetoothctl command: %s\n' "\$*" >&2
    exit 2
    ;;
esac
SH
    chmod +x "${bin}/bluetoothctl"
}

write_fake_bluetoothctl_with_stale_pairing() {
    local state="${fixture}/state"
    printf 'paired=yes\ntrusted=yes\nconnected=no\nconnect_attempts=0\nrepaired=no\ndiscovery_checks=0\n' >"$state"

    cat >"${bin}/bluetoothctl" <<SH
#!/usr/bin/env bash
set -euo pipefail

state="${state}"
. "\$state"
printf '%s\n' "\$*" >>"${log}"

write_state() {
  {
    printf 'paired=%s\n' "\$paired"
    printf 'trusted=%s\n' "\$trusted"
    printf 'connected=%s\n' "\$connected"
    printf 'connect_attempts=%s\n' "\$connect_attempts"
    printf 'repaired=%s\n' "\$repaired"
    printf 'discovery_checks=%s\n' "\$discovery_checks"
  } >"\$state"
}

case "\$*" in
  "agent on"|"default-agent")
    printf 'No agent is registered\n'
    exit 1
    ;;
  "power on"|"scan on"|"scan off")
    printf 'Changing %s succeeded\n' "\$1"
    ;;
  "devices")
    if [ "\$repaired" = "yes" ]; then
      discovery_checks=\$((discovery_checks + 1))
      write_state
      if [ "\$discovery_checks" -eq 1 ]; then
        exit 0
      fi
    fi
    printf 'Device 88:C9:E8:E7:C6:FC WF-1000XM4\n'
    ;;
  "info 88:C9:E8:E7:C6:FC")
    cat <<EOF
Device 88:C9:E8:E7:C6:FC (public)
	Name: WF-1000XM4
	RSSI: -49
	Paired: \$paired
	Trusted: \$trusted
	Connected: \$connected
EOF
    ;;
  "connect 88:C9:E8:E7:C6:FC")
    connect_attempts=\$((connect_attempts + 1))
    if [ "\$paired" = "yes" ] && [ "\$repaired" = "no" ] && [ "\$connect_attempts" -le 2 ]; then
      write_state
      printf 'Attempting to connect to 88:C9:E8:E7:C6:FC\n'
      printf 'Failed to connect: org.bluez.Error.Failed br-connection-page-timeout\n'
      exit 1
    fi
    connected=yes
    write_state
    printf 'Connection successful\n'
    ;;
  "remove 88:C9:E8:E7:C6:FC")
    paired=no
    trusted=no
    connected=no
    connect_attempts=0
    repaired=yes
    write_state
    printf 'Device has been removed\n'
    ;;
  "--agent NoInputNoOutput pair 88:C9:E8:E7:C6:FC")
    paired=yes
    connected=no
    write_state
    printf 'Pairing successful\n'
    ;;
  "trust 88:C9:E8:E7:C6:FC")
    trusted=yes
    write_state
    printf 'Changing 88:C9:E8:E7:C6:FC trust succeeded\n'
    ;;
  *)
    printf 'unexpected bluetoothctl command: %s\n' "\$*" >&2
    exit 2
    ;;
esac
SH
    chmod +x "${bin}/bluetoothctl"
}

run_bluetooth_pair() {
    BLUETOOTH_PAIR_TEST_FZF_ROWS="${fixture}/fzf-rows.tsv" \
        PATH="${bin}:/usr/bin:/bin" \
        "$script" --scan-seconds 1 "$@"
}

case "${DOTFILES_TEST_CASE:-}" in
bluetooth-pair-syntax)
    bash -n "$script"
    ;;
bluetooth-pair-does-not-require-persistent-default-agent)
    make_fixture
    write_fake_fzf "88:C9:E8:E7:C6:FC"
    write_fake_bluetoothctl no no no

    run_bluetooth_pair >"${fixture}/out" 2>"${fixture}/err"

    assert_file_not_contains "$log" "agent on"
    assert_file_not_contains "$log" "default-agent"
    assert_file_contains "$log" "--agent NoInputNoOutput pair 88:C9:E8:E7:C6:FC"
    assert_file_contains "${fixture}/out" "Pairing successful"
    ;;
bluetooth-pair-picker-pairs-selected-device)
    make_fixture
    write_fake_fzf "88:C9:E8:E7:C6:FC"
    write_fake_bluetoothctl no no no

    run_bluetooth_pair >"${fixture}/out" 2>"${fixture}/err"

    assert_file_contains "${fixture}/fzf-rows.tsv" $'88:C9:E8:E7:C6:FC\tWF-1000XM4\tseen=no paired=no trusted=no connected=no'
    assert_file_contains "${fixture}/out" "Using 88:C9:E8:E7:C6:FC  WF-1000XM4"
    assert_file_contains "${fixture}/out" "Pairing successful"
    assert_file_contains "${fixture}/out" "Changing 88:C9:E8:E7:C6:FC trust succeeded"
    assert_file_contains "${fixture}/out" "Connection successful"
    assert_file_contains "$log" "interactive:scan on"
    assert_file_contains "$log" "interactive:scan off"
    assert_file_lacks_line "${fixture}/out" "unknown"
    assert_file_contains "$log" "--agent NoInputNoOutput pair 88:C9:E8:E7:C6:FC"
    assert_file_contains "$log" "trust 88:C9:E8:E7:C6:FC"
    assert_file_contains "$log" "connect 88:C9:E8:E7:C6:FC"
    ;;
bluetooth-pair-skips-already-paired-device)
    make_fixture
    write_fake_fzf "88:C9:E8:E7:C6:FC"
    write_fake_bluetoothctl yes yes no

    run_bluetooth_pair >"${fixture}/out" 2>"${fixture}/err"

    assert_file_contains "${fixture}/out" "Already paired 88:C9:E8:E7:C6:FC"
    assert_file_contains "${fixture}/out" "Already trusted 88:C9:E8:E7:C6:FC"
    assert_file_contains "${fixture}/out" "Connection successful"
    assert_file_lacks_line "${fixture}/out" "unknown"
    assert_file_not_contains "$log" "pair 88:C9:E8:E7:C6:FC"
    assert_file_not_contains "$log" "trust 88:C9:E8:E7:C6:FC"
    assert_file_contains "$log" "connect 88:C9:E8:E7:C6:FC"
    ;;
bluetooth-pair-reports-bluez-action-error)
    make_fixture
    write_fake_fzf "88:C9:E8:E7:C6:FC"
    write_fake_bluetoothctl no no no "Failed to pair: org.bluez.Error.AuthenticationFailed"

    if run_bluetooth_pair >"${fixture}/out" 2>"${fixture}/err"; then
        printf 'expected bluetooth-pair to fail when BlueZ pair fails\n' >&2
        exit 1
    fi

    assert_file_contains "${fixture}/out" "Failed to pair: org.bluez.Error.AuthenticationFailed"
    assert_file_contains "${fixture}/err" "bluetooth-pair: pair for 88:C9:E8:E7:C6:FC failed"
    assert_file_not_contains "$log" "trust 88:C9:E8:E7:C6:FC"
    assert_file_not_contains "$log" "connect 88:C9:E8:E7:C6:FC"
    ;;
bluetooth-pair-repairs-stale-pairing-timeout)
    make_fixture
    write_fake_fzf "88:C9:E8:E7:C6:FC"
    write_fake_bluetoothctl_with_stale_pairing

    run_bluetooth_pair --connect-attempts 2 >"${fixture}/out" 2>"${fixture}/err"

    assert_file_contains "${fixture}/fzf-rows.tsv" $'88:C9:E8:E7:C6:FC\tWF-1000XM4\tseen=yes rssi=-49 paired=yes trusted=yes connected=no'
    assert_file_contains "${fixture}/out" "Already paired 88:C9:E8:E7:C6:FC"
    assert_file_contains "${fixture}/out" "Already trusted 88:C9:E8:E7:C6:FC"
    assert_file_contains "${fixture}/out" "Failed to connect: org.bluez.Error.Failed br-connection-page-timeout"
    assert_file_contains "${fixture}/out" "Connection timed out for existing pairing; removing and pairing 88:C9:E8:E7:C6:FC again"
    assert_file_contains "${fixture}/out" "Device has been removed"
    assert_file_contains "${fixture}/out" "Pairing successful"
    assert_file_contains "${fixture}/out" "Connection successful"
    assert_file_lacks_line "${fixture}/out" "unknown"
    [[ $(rg -c '^connect 88:C9:E8:E7:C6:FC$' "$log") -eq 3 ]]
    assert_file_contains "$log" "remove 88:C9:E8:E7:C6:FC"
    assert_file_contains "$log" "--agent NoInputNoOutput pair 88:C9:E8:E7:C6:FC"
    assert_file_contains "$log" "trust 88:C9:E8:E7:C6:FC"
    ;;
bluetooth-pair-waits-after-removing-stale-pairing)
    make_fixture
    write_fake_fzf "88:C9:E8:E7:C6:FC"
    write_fake_bluetoothctl_with_stale_pairing

    run_bluetooth_pair --connect-attempts 2 --timeout 3 >"${fixture}/out" 2>"${fixture}/err"

    assert_file_contains "${fixture}/err" "Waiting up to 3 seconds for 88:C9:E8:E7:C6:FC to become discoverable again"
    assert_file_contains "$log" "remove 88:C9:E8:E7:C6:FC"
    assert_file_contains "$log" "--agent NoInputNoOutput pair 88:C9:E8:E7:C6:FC"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
