#!/usr/bin/env bash

sleep 1

warn() {
  printf 'setup-displays: %s\n' "$1" >&2
}

if ! command -v xrandr >/dev/null 2>&1; then
  warn "xrandr no esta instalado"
  exit 1
fi

if ! xrandr --query >/dev/null 2>&1; then
  warn "no hay servidor X disponible (DISPLAY=${DISPLAY:-unset}); se omite configuracion"
  exit 0
fi

xr_output="$(xrandr --query)"

first_connected_output() {
  printf '%s\n' "$xr_output" | awk '/ connected/{print $1; exit}'
}

first_connected_output_except() {
  local ignored="$1"
  printf '%s\n' "$xr_output" | awk -v ignored="$ignored" '/ connected/ && $1 != ignored {print $1; exit}'
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

external="$(printf '%s\n' "$xr_output" | awk -v internal="$internal" '/^HDMI[^ ]* connected/ && $1 != internal {print $1; exit}')"

if [[ -z "$external" ]]; then
  # In case USB-C is connected via another DP output.
  external="$(printf '%s\n' "$xr_output" | awk -v internal="$internal" '/^DP[^ ]* connected/{if ($1 != internal) {print $1; exit}}')"
fi
if [[ -z "$external" ]]; then
  external="$(first_connected_output_except "$internal")"
fi

if [[ -z "$internal" ]]; then
  warn "no se detecto ningun monitor conectado"
  exit 0
fi

if ! xrandr --query | grep -qE '^[[:space:]]+1920x1080f'; then
  xrandr --newmode "1920x1080f" 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync >/dev/null 2>&1 || true
fi

xrandr --addmode "$internal" "1920x1080f" >/dev/null 2>&1 || true
xrandr --output "$internal" --primary --mode "1920x1080f" --rate 120.21 >/dev/null 2>&1 || \
  xrandr --output "$internal" --primary --auto >/dev/null 2>&1 || true

if [[ -n "$external" ]]; then
  xrandr --output "$external" --mode 3440x1440 --rate 59.97 --right-of "$internal" >/dev/null 2>&1 || \
    xrandr --output "$external" --auto --right-of "$internal" >/dev/null 2>&1 || true

  if command -v notify-send >/dev/null 2>&1; then
    /usr/bin/notify-send "[external] $external connected"
  fi
else
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
  warn "wacom-config.sh no esta disponible; se omite"
fi
