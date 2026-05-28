#!/usr/bin/env bash
# Purpose: Apply the local X11 display layout after monitor power changes or manual invocation.
# Notes: DDC/CI decides whether the external monitor is powered on; XRandR is only used to apply the selected output layout.

sleep 1

warn() {
  printf 'setup-displays: %s\n' "$1" >&2
}

if ! command -v xrandr >/dev/null 2>&1; then
  warn "xrandr is not installed"
  exit 1
fi

if ! xrandr --query >/dev/null 2>&1; then
  warn "no X server is available (DISPLAY=${DISPLAY:-unset}); skipping display configuration"
  exit 0
fi

xr_output="$(xrandr --query)"

first_connected_output() {
  printf '%s\n' "$xr_output" | awk '/ connected/{print $1; exit}'
}

connected_output_except() {
  local ignored="$1"
  local pattern="${2:-.*}"
  printf '%s\n' "$xr_output" | awk -v ignored="$ignored" -v pattern="$pattern" '
    $1 != ignored && $1 ~ pattern && / connected/ {
      print $1
      exit
    }'
}

x_output_to_drm_connectors() {
  local output="$1"
  local rest stripped

  case "$output" in
    HDMI-*)
      rest="${output#HDMI-}"
      printf 'HDMI-A-%s\n' "$rest"
      stripped="${rest%-*}"
      if [[ "$stripped" != "$rest" ]]; then
        printf 'HDMI-A-%s\n' "$stripped"
      fi
      ;;
    *)
      printf '%s\n' "$output"
      stripped="${output%-*}"
      if [[ "$stripped" != "$output" ]]; then
        printf '%s\n' "$stripped"
      fi
      ;;
  esac
}

ddc_bus_for_output() {
  local output="$1"
  local connector bus

  while read -r connector; do
    [[ -n "$connector" ]] || continue
    bus="$(ddcutil detect --brief 2>/dev/null | awk -v connector="$connector" '
      /I2C bus:/ {
        bus = $NF
        sub("^.*/i2c-", "", bus)
      }
      /DRM connector:/ && $NF ~ ("card[0-9]+-" connector "$") {
        print bus
        exit
      }')"
    if [[ -n "$bus" ]]; then
      printf '%s\n' "$bus"
      return 0
    fi
  done < <(x_output_to_drm_connectors "$output")

  ddcutil detect --brief 2>/dev/null | awk '
    function flush() {
      if (bus != "" && connector == "" && monitor != "" && monitor !~ /AUO/) {
        print bus
        found = 1
        exit
      }
      bus = ""
      connector = ""
      monitor = ""
    }
    /^(Display|Invalid display)/ {
      flush()
    }
    /I2C bus:/ {
      bus = $NF
      sub("^.*/i2c-", "", bus)
    }
    /DRM connector:/ {
      connector = $NF
    }
    /Monitor:/ {
      monitor = $0
    }
    END {
      if (!found) {
        flush()
      }
    }'
}

output_powered_on() {
  local output="$1"
  local bus power

  command -v ddcutil >/dev/null 2>&1 || return 0
  bus="$(ddc_bus_for_output "$output")"
  [[ -n "$bus" ]] || return 1

  power="$(ddcutil --bus "$bus" getvcp D6 2>/dev/null || true)"
  [[ "$power" == *"DPM: On"* || "$power" == *"sl=0x01"* ]]
}

# Prefer laptop panel names first (eDP/LVDS). Some setups expose only DP-*
# names, so fall back to DP if needed. In VMs the output can be named
# Virtual-1, VGA-1, or similar, so use the first connected output as the final
# fallback.
internal="$(printf '%s\n' "$xr_output" | awk '/^(eDP|LVDS)[^ ]* connected/{print $1; exit}')"
if [[ -z "$internal" ]]; then
  internal="$(printf '%s\n' "$xr_output" | awk '/^DP[^ ]* connected/{print $1; exit}')"
fi
if [[ -z "$internal" ]]; then
  internal="$(first_connected_output)"
fi

external="$(connected_output_except "$internal" '^HDMI')"

if [[ -z "$external" ]]; then
  # In case USB-C is connected via another DP output.
  external="$(connected_output_except "$internal" '^DP')"
fi
if [[ -z "$external" ]]; then
  external="$(connected_output_except "$internal")"
fi

if [[ -z "$internal" ]]; then
  warn "no connected monitor was detected"
  exit 0
fi

configure_internal() {
  if ! xrandr --query | grep -qE '^[[:space:]]+1920x1080f'; then
    xrandr --newmode "1920x1080f" 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync >/dev/null 2>&1 || true
  fi

  xrandr --addmode "$internal" "1920x1080f" >/dev/null 2>&1 || true
  xrandr --output "$internal" --primary --mode "1920x1080f" --rate 120.21 >/dev/null 2>&1 || \
    xrandr --output "$internal" --primary --auto >/dev/null 2>&1 || true
}

configure_external() {
  local output="$1"
  xrandr --output "$output" --primary --mode 3440x1440 --rate 59.97 --right-of "$internal" >/dev/null 2>&1 || \
    xrandr --output "$output" --primary --auto --right-of "$internal" >/dev/null 2>&1
}

finalize_external_only() {
  local output="$1"
  xrandr --output "$internal" --off --output "$output" --primary --mode 3440x1440 --rate 59.97 --pos 0x0 >/dev/null 2>&1 || \
    xrandr --output "$internal" --off --output "$output" --primary --auto --pos 0x0 >/dev/null 2>&1 || true
}

wait_for_output_powered_on() {
  local output="$1"
  local _attempt

  for _attempt in 1 2 3 4 5 6 7 8 9 10; do
    output_powered_on "$output" && return 0
    sleep 0.2
  done

  return 1
}

if [[ -n "$external" ]]; then
  if configure_external "$external" && wait_for_output_powered_on "$external"; then
    finalize_external_only "$external"
    if command -v notify-send >/dev/null 2>&1; then
      /usr/bin/notify-send "[external] $external connected"
    fi
  else
    warn "external monitor $external is not powered on; keeping $internal active"
    configure_internal
    xrandr --output "$external" --off >/dev/null 2>&1 || true
  fi
else
  configure_internal

  external="$(xrandr --listmonitors | awk -v internal="$internal" 'NR>1 { if ($4 != internal) { print $4; exit } }')"
  if [[ -n "$external" ]]; then
    if command -v notify-send >/dev/null 2>&1; then
      /usr/bin/notify-send "[external] $external disconnected"
    fi
    xrandr --output "$external" --off >/dev/null 2>&1 || true
  fi
fi

# Reset wallpaper only when feh is available.
if command -v feh >/dev/null 2>&1; then
  /usr/bin/feh --bg-scale --recursive --verbose --randomize ~/.wallpapers/
fi

# Re-apply wacom config only when helper exists.
if command -v wacom-config.sh >/dev/null 2>&1; then
  wacom-config.sh
else
  warn "wacom-config.sh is not available; skipping"
fi
