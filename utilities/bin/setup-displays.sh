#!/usr/bin/env bash
# Purpose: Apply or toggle the local X11 display layout.
# Usage: setup-displays.sh [--toggle]
# Notes: XRandR applies the selected laptop-only or external-only layout.

mode="${1:-auto}"

warn() {
    printf 'setup-displays: %s\n' "$1" >&2
}

state_dir="${XDG_RUNTIME_DIR:-/tmp}/setup-displays"
internal_brightness_state="$state_dir/internal-brightness"
sysfs_root="${SETUP_DISPLAYS_SYSFS_ROOT:-/sys}"
compositor_service="${SETUP_DISPLAYS_COMPOSITOR_SERVICE:-compositor.service}"

usage() {
    printf '%s\n' 'usage: setup-displays.sh [--toggle]'
}

case "$mode" in
auto | --auto | --toggle | toggle)
    ;;
--help | -h)
    usage
    exit 0
    ;;
*)
    usage >&2
    exit 2
    ;;
esac

case "$mode" in
auto | --auto)
    sleep 1
    ;;
esac

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

output_active() {
    local output="$1"

    printf '%s\n' "$xr_output" | awk -v output="$output" '
    $1 == output && / connected/ && /[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/ {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }'
}

screen_has_mode() {
    local mode="$1"

    printf '%s\n' "$xr_output" | awk -v mode="$mode" '$1 == mode { found = 1 } END { exit(found ? 0 : 1) }'
}

output_has_mode() {
    local output="$1"
    local mode="$2"

    printf '%s\n' "$xr_output" | awk -v output="$output" -v mode="$mode" '
    $1 == output && / connected/ {
      inside = 1
      next
    }
    inside && /^[^[:space:]]/ {
      inside = 0
    }
    inside && $1 == mode {
      found = 1
    }
    END {
      exit(found ? 0 : 1)
    }'
}

current_mode_rate() {
    local output="$1"
    local output_state="$2"

    awk -v output="$output" '
    $1 == output && $2 == "connected" {
      inside = 1
      next
    }
    inside && /^[^[:space:]]/ {
      inside = 0
    }
    inside && /\*/ {
      mode = $1
      for (i = 2; i <= NF; i++) {
        if ($i ~ /\*/) {
          rate = $i
          gsub(/[+*]/, "", rate)
          print mode, rate
          exit
        }
      }
    }' <<<"$output_state"
}

rate_for_mode_except() {
    local output="$1"
    local mode="$2"
    local current_rate="$3"
    local output_state="$4"

    awk -v output="$output" -v mode="$mode" -v current_rate="$current_rate" '
    $1 == output && $2 == "connected" {
      inside = 1
      next
    }
    inside && /^[^[:space:]]/ {
      inside = 0
    }
    inside && $1 == mode {
      for (i = 2; i <= NF; i++) {
        rate = $i
        gsub(/[+*]/, "", rate)
        if (rate != current_rate) {
          print rate
          exit
        }
      }
    }' <<<"$output_state"
}

drm_path_for_output() {
    local output="$1"
    local connector path first_path

    while read -r connector; do
        [[ -n "$connector" ]] || continue
        for path in "$sysfs_root"/class/drm/card*-"$connector"; do
            [[ -d "$path" ]] || continue
            [[ -z "${first_path:-}" ]] && first_path="$path"

            if [[ -r "$path/status" && "$(sed -n '1p' "$path/status")" == "connected" ]]; then
                printf '%s\n' "$path"
                return 0
            fi
        done
    done < <(x_output_to_drm_connectors "$output")

    [[ -n "${first_path:-}" ]] && printf '%s\n' "$first_path"
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

ensure_internal_mode() {
    if ! screen_has_mode "1920x1080f"; then
        xrandr --newmode "1920x1080f" 285.00 1920 2028 2076 2076 1080 1090 1100 1142 -hsync -vsync >/dev/null 2>&1 || true
    fi

    if ! output_has_mode "$internal" "1920x1080f"; then
        xrandr --addmode "$internal" "1920x1080f" >/dev/null 2>&1 || true
    fi
}

force_internal_scanout() {
    command -v xset >/dev/null 2>&1 || return 0
    xset dpms force on >/dev/null 2>&1 || true
}

refresh_output_mode() {
    local output="$1"
    local output_state current mode current_rate alt_mode alt_rate base_mode

    output_state="$(xrandr --query 2>/dev/null)" || return 0
    current="$(current_mode_rate "$output" "$output_state")"
    [[ -n "$current" ]] || return 0

    read -r mode current_rate <<<"$current"
    alt_mode="$mode"
    alt_rate="$(rate_for_mode_except "$output" "$mode" "$current_rate" "$output_state")"

    if [[ -z "$alt_rate" && "$mode" == *f ]]; then
        base_mode="${mode%f}"
        alt_rate="$(rate_for_mode_except "$output" "$base_mode" "$current_rate" "$output_state")"
        [[ -n "$alt_rate" ]] && alt_mode="$base_mode"
    fi

    force_internal_scanout

    if [[ -n "$alt_rate" ]]; then
        xrandr --output "$output" --mode "$alt_mode" --rate "$alt_rate" >/dev/null 2>&1 || true
    fi
    xrandr --output "$output" --mode "$mode" --rate "$current_rate" >/dev/null 2>&1 ||
        xrandr --output "$output" --auto >/dev/null 2>&1 || true
}

output_scanout_is_stale() {
    local output="$1"
    local output_state current
    local drm_path enabled dpms

    output_state="$(xrandr --query 2>/dev/null)" || return 1
    current="$(current_mode_rate "$output" "$output_state")"
    [[ -n "$current" ]] || return 1

    drm_path="$(drm_path_for_output "$output")"
    [[ -n "$drm_path" ]] || return 1

    enabled="$(sed -n '1p' "$drm_path/enabled" 2>/dev/null || true)"
    dpms="$(sed -n '1p' "$drm_path/dpms" 2>/dev/null || true)"

    [[ -n "$enabled" && "$enabled" != "enabled" ]] && return 0
    [[ -n "$dpms" && "$dpms" != "On" ]] && return 0
    return 1
}

refresh_compositor() {
    # A laptop/external layout change can leave the X compositor (picom) holding
    # a stale black overlay over the new geometry: the panel is lit and
    # XRandR/DRM report an active output, yet nothing is painted. This is a
    # compositor-layer wedge that no GPU mode or DPMS refresh can clear, so
    # rebuild the overlay by restarting the user compositor service. Only act
    # when the unit is already active so this stays off the boot/auto path.
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl --user is-active --quiet "$compositor_service" 2>/dev/null || return 0
    systemctl --user restart "$compositor_service" >/dev/null 2>&1 || true
}

internal_backlight_dir() {
    local connector candidate

    while read -r connector; do
        [[ -n "$connector" ]] || continue
        for candidate in "$sysfs_root"/class/drm/card*-"$connector"/amdgpu_bl*; do
            [[ -d "$candidate" && -r "$candidate/max_brightness" && -w "$candidate/brightness" ]] || continue
            printf '%s\n' "$candidate"
            return 0
        done
    done < <(x_output_to_drm_connectors "$internal")

    return 1
}

current_internal_brightness() {
    local backlight

    backlight="$(internal_backlight_dir)" || return 1
    [[ -r "$backlight/brightness" ]] || return 1
    sed -n '1p' "$backlight/brightness"
}

save_internal_brightness() {
    local brightness

    brightness="$(current_internal_brightness)" || return 0
    mkdir -p "$state_dir" || return 0
    printf '%s\n' "$brightness" >"$internal_brightness_state" || true
}

restore_internal_brightness() {
    local backlight brightness max fallback bogus_threshold

    backlight="$(internal_backlight_dir)" || return 0
    [[ -r "$backlight/max_brightness" && -w "$backlight/brightness" ]] || return 0

    max="$(sed -n '1p' "$backlight/max_brightness")"
    [[ "$max" =~ ^[0-9]+$ && "$max" -gt 0 ]] || return 0

    fallback=$((max / 2))
    [[ "$fallback" -gt 0 ]] || fallback=1
    bogus_threshold=$((max / 100))
    [[ "$bogus_threshold" -gt 0 ]] || bogus_threshold=1
    if [[ "$max" -gt 1000 && "$bogus_threshold" -lt 100 ]]; then
        bogus_threshold=100
    fi

    if [[ -r "$internal_brightness_state" ]]; then
        brightness="$(sed -n '1p' "$internal_brightness_state")"
    else
        brightness="$fallback"
    fi

    [[ "$brightness" =~ ^[0-9]+$ ]] || brightness="$fallback"
    if [[ "$brightness" -le "$bogus_threshold" ]]; then
        brightness="$fallback"
    elif [[ "$brightness" -gt "$max" ]]; then
        brightness="$max"
    fi

    printf '%s\n' "$brightness" >"$backlight/brightness" 2>/dev/null || true
}

switch_to_external_only() {
    local output="$1"

    save_internal_brightness
    xrandr --output "$internal" --off --output "$output" --primary --mode 3440x1440 --rate 59.97 --pos 0x0 >/dev/null 2>&1 ||
        xrandr --output "$internal" --off --output "$output" --primary --auto --pos 0x0 >/dev/null 2>&1 || true
}

switch_to_internal_only() {
    local output="${1:-}"
    local returned_from_external=0

    if [[ -n "$output" ]]; then
        returned_from_external=1
        ensure_internal_mode
        xrandr --output "$internal" --primary --mode "1920x1080f" --rate 120.21 --pos 0x0 --output "$output" --off >/dev/null 2>&1 ||
            xrandr --output "$internal" --primary --auto --pos 0x0 --output "$output" --off >/dev/null 2>&1 || true
    else
        ensure_internal_mode
        xrandr --output "$internal" --primary --mode "1920x1080f" --rate 120.21 --pos 0x0 >/dev/null 2>&1 ||
            xrandr --output "$internal" --primary --auto --pos 0x0 >/dev/null 2>&1 || true
    fi

    force_internal_scanout
    if [[ "$returned_from_external" -eq 1 ]]; then
        if output_scanout_is_stale "$internal"; then
            warn "$internal scanout looks stale after layout toggle; refreshing mode"
        fi
        refresh_output_mode "$internal"
    fi
    restore_internal_brightness
}

case "$mode" in
--toggle | toggle)
    if [[ -z "$external" ]]; then
        warn "no external monitor was detected; keeping $internal active"
        switch_to_internal_only
    elif output_active "$external" && ! output_active "$internal"; then
        switch_to_internal_only "$external"
    else
        switch_to_external_only "$external"
    fi
    refresh_compositor
    ;;
*)
    if [[ -n "$external" ]]; then
        switch_to_external_only "$external"
    else
        external="$(xrandr --listmonitors | awk -v internal="$internal" 'NR>1 { if ($4 != internal) { print $4; exit } }')"
        switch_to_internal_only "$external"
    fi
    ;;
esac

# Reset the root pixmap after XRandR changes so it matches the current screen geometry.
if command -v apply-wallpaper >/dev/null 2>&1; then
    apply-wallpaper
else
    warn "apply-wallpaper is not available; skipping wallpaper reset"
fi

# Re-apply wacom config only when helper exists.
if command -v wacom-config.sh >/dev/null 2>&1; then
    wacom-config.sh
else
    warn "wacom-config.sh is not available; skipping"
fi
