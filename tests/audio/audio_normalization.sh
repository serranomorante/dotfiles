#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio pipewire wireplumber routing
# dotfiles-test-case: audio-normalization-only-brave
# dotfiles-test-case: audio-normalization-config-consistent
# dotfiles-test-case: audio-normalization-plugin-wired
# dotfiles-test-case: audio-normalization-plugin-ports-declared
# dotfiles-test-case: audio-normalization-plugin-builds-clean
# dotfiles-test-case: audio-normalization-plugin-hard-caps-output
# dotfiles-test-case: audio-normalization-plugin-survives-nan-controls
# dotfiles-test-case: audio-normalization-agc-levels-quiet-passages
# dotfiles-test-case: audio-normalization-filter-chains-are-nofail
# dotfiles-test-case: audio-normalization-rebuild-restarts-pipewire
# dotfiles-test-case: audio-normalization-lua-syntax

# Purpose: Verify Brave is the only stream routed through the EBU R128
# normalizer sink and that the normalizer output rejoins the multimedia
# logical sink, so Chromium, Firefox, and other applications are untouched.
# Also verify the agc_ceiling plugin declares well-formed ports and really
# hard-caps its output, because a silent regression there is a loudness
# hazard rather than a cosmetic bug.

lua_script="${DOTFILES_TEST_ROOT}/audio/dot-local/share/wireplumber/scripts/linking/auto-connect-ports.lua"
conf="${DOTFILES_TEST_ROOT}/audio/dot-config/pipewire/pipewire.conf.d/35-source-filter-ebur128-normalization.conf"
plugin_src="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/files/ladspa-agc-ceiling.c"
audio_playbook="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/tasks/210-setup-audio-tools.archlinux.yml"
handlers="${DOTFILES_TEST_ROOT}/playbooks/roles/10-system-tools/handlers/main.yml"

assert_contains() {
    local file=$1 pattern=$2
    rg -q --fixed-strings -- "$pattern" "$file" || {
        printf 'expected %s to contain: %s\n' "$file" "$pattern" >&2
        exit 1
    }
}

refute_contains() {
    local file=$1 pattern=$2
    refute rg -q --fixed-strings -- "$pattern" "$file"
}

# Emits the PORT_* enum members of the plugin, excluding the PORT_COUNT
# sentinel, in declaration order.
plugin_port_enum() {
    sed -n '/^enum {/,/^};/p' "$plugin_src" |
        sed -n 's/^[[:space:]]*\(PORT_[A-Z0-9_]*\).*/\1/p' |
        grep -v '^PORT_COUNT$'
}

# Emits the body of one PORT_COUNT-sized table from the plugin source.
plugin_table_body() {
    local table=$1
    sed -n "/^static const .*[^a-z_]${table}\[PORT_COUNT\] = {/,/^};/p" "$plugin_src"
}

build_plugin() {
    local out=$1
    gcc -O2 -shared -fPIC -Wall -Wextra -Werror "$plugin_src" -o "$out" -lebur128 -lm
}

require_plugin_toolchain() {
    command -v gcc >/dev/null 2>&1 || exit 77
    [[ -e /usr/include/ladspa.h ]] || exit 77
    [[ -e /usr/include/ebur128.h ]] || exit 77
}

# Builds a minimal LADSPA host that wires the plugin the way PipeWire's filter
# chain does and drives it through a near-silence -> fortissimo transition.
# Prints, for one quantum: output peak, non-finite sample count, steady-state
# L/R balance in dB, and the boost the AGC had wound on before the transition.
build_harness() {
    local src=$1 bin=$2
    cat >"$src" <<'HARNESS'
#include <dlfcn.h>
#include <ladspa.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXQ 4096
static float inl[MAXQ], inr[MAXQ], outl[MAXQ], outr[MAXQ];
static float ctl[32], notify[32];
static const LADSPA_Descriptor *d;
static long gain_notify = -1;

static void wire(LADSPA_Handle h)
{
	unsigned long audio_in = 0, audio_out = 0, ci = 0, ni = 0, i;
	for (i = 0; i < d->PortCount; i++) {
		LADSPA_PortDescriptor p = d->PortDescriptors[i];
		if (LADSPA_IS_PORT_AUDIO(p)) {
			if (LADSPA_IS_PORT_INPUT(p))
				d->connect_port(h, i, audio_in++ ? inr : inl);
			else
				d->connect_port(h, i, audio_out++ ? outr : outl);
		} else if (LADSPA_IS_PORT_CONTROL(p)) {
			if (LADSPA_IS_PORT_INPUT(p)) {
				d->connect_port(h, i, &ctl[ci++]);
			} else {
				if (strcmp(d->PortNames[i], "Gain (dB)") == 0)
					gain_notify = (long)ni;
				d->connect_port(h, i, &notify[ni++]);
			}
		}
	}
}

static long port_index(const char *name)
{
	unsigned long i;
	for (i = 0; i < d->PortCount; i++)
		if (strcmp(d->PortNames[i], name) == 0)
			return (long)i;
	return -1;
}

/* Sets a control the way the filter chain does: by name, and only if the
 * plugin really exposes it as a control input. */
static int set_control(const char *name, float value)
{
	long p = port_index(name), i;
	unsigned long ci = 0;
	if (p < 0)
		return 0;
	if (!(LADSPA_IS_PORT_CONTROL(d->PortDescriptors[p]) &&
	      LADSPA_IS_PORT_INPUT(d->PortDescriptors[p])))
		return 0;
	for (i = 0; i < p; i++)
		if (LADSPA_IS_PORT_CONTROL(d->PortDescriptors[i]) &&
		    LADSPA_IS_PORT_INPUT(d->PortDescriptors[i]))
			ci++;
	ctl[ci] = value;
	return 1;
}

int main(int argc, char **argv)
{
	const char *controls[] = { "Target LUFS", "Floor LUFS", "Knee (dB)",
				   "Max Gain (dB)", "Attack (ms)", "Release (ms)",
				   "Ceiling (dB)", "Limiter Release (ms)" };
	float values[] = { -28.f, -58.f, 14.f, 34.f, 20.f, 500.f, -1.f, 200.f };
	int q = argc > 2 ? atoi(argv[2]) : 256;
	void *lib;
	LADSPA_Handle h;
	double ph = 0.0, w, amp, peak = 0.0, el = 0.0, er = 0.0, windup = 0.0;
	long b, i, blocks, switch_at;
	int nonfinite = 0, k;

	if (q < 1 || q > MAXQ)
		return 2;
	lib = dlopen(argv[1], RTLD_NOW);
	if (lib == NULL) {
		fprintf(stderr, "%s\n", dlerror());
		return 2;
	}
	d = ((LADSPA_Descriptor_Function)dlsym(lib, "ladspa_descriptor"))(0);
	h = d->instantiate(d, 48000);
	wire(h);
	for (k = 0; k < (int)(sizeof(values) / sizeof(values[0])); k++) {
		if (!set_control(controls[k], values[k])) {
			fprintf(stderr, "control not settable: %s\n", controls[k]);
			return 3;
		}
	}
	if (gain_notify < 0) {
		fprintf(stderr, "plugin exposes no \"Gain (dB)\" notify port\n");
		return 3;
	}
	/* A non-finite ceiling must not be able to switch the limiter off: every
	 * comparison against NaN is false, so an unsanitized read would let the
	 * raw AGC gain through unbounded. */
	if (argc > 3 && strcmp(argv[3], "nan-ceiling") == 0)
		set_control("Ceiling (dB)", (float)NAN);
	d->activate(h);

	w = 2.0 * M_PI * 440.0 / 48000.0;
	blocks = 900000L / q;
	switch_at = 700000L / q;
	/* Hard-panned so a per-channel AGC or limiter would be visible: L sits
	 * 24 dB above R throughout. */
	amp = pow(10.0, -58.0 / 20.0);
	for (b = 0; b < blocks; b++) {
		if (b == switch_at) {
			windup = notify[gain_notify];
			amp = 0.9; /* sudden fortissimo */
		}
		for (i = 0; i < q; i++) {
			double s = sin(ph);
			ph += w;
			inl[i] = (float)(amp * s);
			inr[i] = (float)(amp * s * 0.0631); /* -24 dB */
		}
		d->run(h, (unsigned long)q);
		for (i = 0; i < q; i++) {
			if (!isfinite(outl[i]) || !isfinite(outr[i]))
				nonfinite++;
			if (fabs(outl[i]) > peak)
				peak = fabs(outl[i]);
			if (fabs(outr[i]) > peak)
				peak = fabs(outr[i]);
			if (b > 800000L / q) {
				el += outl[i] * (double)outl[i];
				er += outr[i] * (double)outr[i];
			}
		}
	}
	printf("%.9f %d %.4f %.4f\n", peak, nonfinite,
	       er > 0.0 ? 10.0 * log10(el / er) : 999.0, windup);
	d->cleanup(h);
	return 0;
}
HARNESS
    gcc -O2 -o "$bin" "$src" -ldl -lm
}

case "${DOTFILES_TEST_CASE:-}" in
audio-normalization-only-brave)
    assert_contains "$lua_script" '["Brave"] = { node = "capture.source_filter.ebur128_normalize" }'
    assert_contains "$lua_script" '["source_filter.ebur128_normalize"] = { logical_sink = "multimedia" }'
    # Brave no longer goes straight to the multimedia sink.
    refute_contains "$lua_script" '["Brave"] = { logical_sink = "multimedia" }'
    # Other applications keep their existing routing and never hit the normalizer.
    assert_contains "$lua_script" '["Firefox"] = { logical_sink = "multimedia" }'
    assert_contains "$lua_script" '["Chromium"] = { logical_sink = "work" }'
    assert_contains "$lua_script" '["YouTube Music Desktop App"] = { logical_sink = "multimedia" }'
    assert_contains "$lua_script" '["ALSA plug-in [plexamp]"] = { logical_sink = "multimedia" }'
    ;;
audio-normalization-config-consistent)
    # PipeWire fragment defines both sides of the filter chain sink.
    assert_contains "$conf" 'node.name        = "capture.source_filter.ebur128_normalize"'
    assert_contains "$conf" 'media.class      = Audio/Sink'
    assert_contains "$conf" 'node.name      = "source_filter.ebur128_normalize"'
    # The Lua routes Brave into the capture side and the playback side back to multimedia.
    assert_contains "$lua_script" '["Brave"] = { node = "capture.source_filter.ebur128_normalize" }'
    assert_contains "$lua_script" '["source_filter.ebur128_normalize"] = { logical_sink = "multimedia" }'
    # The filter uses the repo-built AGC plugin with a bounded boost.
    assert_contains "$conf" 'plugin = /usr/lib/ladspa/libdotfiles-agc-ceiling.so'
    assert_contains "$conf" 'label = agc_ceiling'
    assert_contains "$conf" '"Target LUFS" = -28.0'
    assert_contains "$conf" '"Floor LUFS" = -58.0'
    assert_contains "$conf" '"Knee (dB)" = 14.0'
    assert_contains "$conf" '"Max Gain (dB)" = 34.0'
    assert_contains "$conf" '"Ceiling (dB)" = -1.0'
    assert_contains "$conf" '"Limiter Release (ms)" = 200.0'
    # One stereo instance, not two mono ones: L and R must share a single gain
    # and a single limiter or the stereo image collapses on panned material.
    assert_contains "$conf" 'name  = agc'
    assert_contains "$conf" 'inputs  = [ "agc:In L" "agc:In R" ]'
    assert_contains "$conf" 'outputs = [ "agc:Out L" "agc:Out R" ]'
    refute_contains "$conf" 'name  = agcL'
    refute_contains "$conf" 'name  = agcR'
    instances="$(rg -c --fixed-strings 'label = agc_ceiling' "$conf")"
    [[ "$instances" = 1 ]] || {
        printf 'expected exactly one agc_ceiling instance, found: %s\n' "$instances" >&2
        exit 1
    }
    # No unbounded lufs2gain measurement chain should come back.
    refute_contains "$conf" 'ebur128:Global LUFS'
    refute_contains "$conf" '{ output = "ebur128:Momentary LUFS"'
    refute_contains "$conf" 'ebur128:In FL'
    # Only Brave (no other application entry) may target the normalizer sink.
    normalizer_targets="$(rg -c --fixed-strings '= { node = "capture.source_filter.ebur128_normalize" }' "$lua_script")"
    [[ "$normalizer_targets" = 1 ]] || {
        printf 'expected exactly one app routed to the normalizer, found: %s\n' "$normalizer_targets" >&2
        exit 1
    }
    ;;
audio-normalization-plugin-wired)
    # The conf references a plugin that the audio tools role compiles and the
    # source really declares the agc_ceiling ports the conf controls.
    test -f "$plugin_src"
    assert_contains "$plugin_src" '#define AGC_LABEL "agc_ceiling"'
    assert_contains "$plugin_src" '"Max Gain (dB)"'
    assert_contains "$plugin_src" '"Target LUFS"'
    assert_contains "$plugin_src" '"Ceiling (dB)"'
    assert_contains "$plugin_src" '"Limiter Release (ms)"'
    assert_contains "$conf" '/usr/lib/ladspa/libdotfiles-agc-ceiling.so'
    assert_contains "$audio_playbook" 'libdotfiles-agc-ceiling.so'
    assert_contains "$audio_playbook" 'ladspa-agc-ceiling.c'
    # Every control the conf sets must exist as a control in the source.
    while read -r control; do
        assert_contains "$plugin_src" "\"${control}\""
    done < <(rg -o --replace '$1' '^\s+"([^"]+)" = -?[0-9]' "$conf")
    ;;
audio-normalization-plugin-ports-declared)
    # Regression guard: the port tables were once positional, and a table that
    # was one entry short silently turned "Limiter Release (ms)" into an output
    # port (so the conf value was discarded) and left "Gain (dB)" declared as
    # neither input nor output. Every PORT_* member must appear exactly once as
    # a designated initializer in every PORT_COUNT-sized table.
    mapfile -t ports < <(plugin_port_enum)
    [[ "${#ports[@]}" -ge 4 ]] || {
        printf 'could not parse the PORT_* enum from %s\n' "$plugin_src" >&2
        exit 1
    }
    for table in port_descriptors port_names port_range_hints; do
        body="$(plugin_table_body "$table")"
        [[ -n "$body" ]] || {
            printf 'could not find table %s[PORT_COUNT] in %s\n' "$table" "$plugin_src" >&2
            exit 1
        }
        for port in "${ports[@]}"; do
            found="$(grep -c -- "\[${port}\] =" <<<"$body" || true)"
            [[ "$found" = 1 ]] || {
                printf 'table %s must initialize %s exactly once, found %s\n' \
                    "$table" "$port" "$found" >&2
                exit 1
            }
        done
    done
    # Directions, so a table can never be well-formed but wrong.
    descriptors="$(plugin_table_body port_descriptors)"
    for port in PORT_IN_L PORT_IN_R; do
        grep -q -- "\[${port}\] = LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO," <<<"$descriptors" || {
            printf '%s must be an audio input\n' "$port" >&2
            exit 1
        }
    done
    for port in PORT_OUT_L PORT_OUT_R; do
        grep -q -- "\[${port}\] = LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO," <<<"$descriptors" || {
            printf '%s must be an audio output\n' "$port" >&2
            exit 1
        }
    done
    for port in PORT_TARGET_LUFS PORT_FLOOR_LUFS PORT_KNEE_DB PORT_MAX_GAIN_DB \
        PORT_ATTACK_MS PORT_RELEASE_MS PORT_CEILING_DB PORT_LIM_RELEASE_MS; do
        grep -q -- "\[${port}\] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL," <<<"$descriptors" || {
            printf '%s must be a control input or the conf value is silently ignored\n' "$port" >&2
            exit 1
        }
    done
    grep -q -- '\[PORT_GAIN_OUT\] = LADSPA_PORT_OUTPUT | LADSPA_PORT_CONTROL,' <<<"$descriptors" || {
        printf 'PORT_GAIN_OUT must be a control output\n' >&2
        exit 1
    }
    # Exactly one control output: the gain meter.
    control_outputs="$(grep -c -- 'LADSPA_PORT_OUTPUT | LADSPA_PORT_CONTROL,' <<<"$descriptors" || true)"
    [[ "$control_outputs" = 1 ]] || {
        printf 'expected exactly one control output port, found %s\n' "$control_outputs" >&2
        exit 1
    }
    ;;
audio-normalization-plugin-builds-clean)
    require_plugin_toolchain
    command -v analyseplugin >/dev/null 2>&1 || exit 77
    so="${DOTFILES_TEST_TMP}/agc-ceiling.so"
    report="${DOTFILES_TEST_TMP}/agc-ceiling.txt"
    build_plugin "$so"
    analyseplugin "$so" >"$report"
    # analyseplugin flags any port that is neither input nor output, or neither
    # control nor audio. That is the exact failure the positional tables caused.
    refute rg -q --fixed-strings 'ERROR' "$report"
    assert_contains "$report" 'Plugin Label: "agc_ceiling"'
    assert_contains "$report" '"In L" input, audio'
    assert_contains "$report" '"In R" input, audio'
    assert_contains "$report" '"Out L" output, audio'
    assert_contains "$report" '"Out R" output, audio'
    assert_contains "$report" '"Ceiling (dB)" input, control'
    assert_contains "$report" '"Limiter Release (ms)" input, control'
    assert_contains "$report" '"Gain (dB)" output, control'
    # The ceiling range must never allow a value above 0 dBFS.
    assert_contains "$report" '"Ceiling (dB)" input, control, -40 to 0'
    # An unconfigured host must get no boost at all.
    assert_contains "$report" '"Max Gain (dB)" input, control, 0 to 60, default 0'
    ;;
audio-normalization-plugin-hard-caps-output)
    # The safety property, asserted on real DSP output rather than on comments:
    # after the AGC has wound a large boost onto a near-silent passage, a sudden
    # fortissimo must still not produce a sample above the configured ceiling,
    # at any block size PipeWire may negotiate. Before the limiter existed this
    # transition peaked above +20 dBFS at small quanta.
    require_plugin_toolchain
    so="${DOTFILES_TEST_TMP}/agc-ceiling.so"
    build_plugin "$so"
    build_harness "${DOTFILES_TEST_TMP}/agc-harness.c" "${DOTFILES_TEST_TMP}/agc-harness"
    harness="${DOTFILES_TEST_TMP}/agc-harness"

    # 10^(-1/20) plus a rounding margin: the configured ceiling is -1 dBFS.
    ceiling_limit=0.8913
    for q in 32 64 128 256 512 1024 2048; do
        read -r peak nonfinite balance windup < <("$harness" "$so" "$q")
        awk -v p="$peak" -v c="$ceiling_limit" -v q="$q" \
            'BEGIN { if (p > c + 1e-6) { printf "quantum %s: output peak %s exceeds the -1 dBFS ceiling (%s)\n", q, p, c > "/dev/stderr"; exit 1 } }'
        [[ "$nonfinite" = 0 ]] || {
            printf 'quantum %s: %s non-finite output samples\n' "$q" "$nonfinite" >&2
            exit 1
        }
        # The cap is only meaningful if the AGC really had a large boost wound
        # on when the fortissimo hit; otherwise this asserts nothing.
        awk -v g="$windup" -v q="$q" \
            'BEGIN { if (g < 20.0) { printf "quantum %s: AGC had only %s dB of boost wound on, the ceiling assertion is vacuous\n", q, g > "/dev/stderr"; exit 1 } }'
        # A single shared gain and a single shared limiter must preserve the
        # 24 dB L/R balance of the input. Two independent mono instances
        # collapsed it to ~1.5 dB.
        awk -v b="$balance" -v q="$q" \
            'BEGIN { if (b < 18.0) { printf "quantum %s: stereo balance collapsed to %s dB, expected ~24 dB\n", q, b > "/dev/stderr"; exit 1 } }'
    done
    ;;
audio-normalization-plugin-survives-nan-controls)
    # Every comparison against NaN is false, so an unsanitized ceiling read
    # makes the limiter's "is this sample too loud" test never fire and the
    # hard cap disappears entirely. A non-finite control must fall back to its
    # default instead, leaving the ceiling in force.
    require_plugin_toolchain
    so="${DOTFILES_TEST_TMP}/agc-ceiling.so"
    build_plugin "$so"
    build_harness "${DOTFILES_TEST_TMP}/agc-harness.c" "${DOTFILES_TEST_TMP}/agc-harness"
    harness="${DOTFILES_TEST_TMP}/agc-harness"

    ceiling_limit=0.8913
    for q in 32 256 1024; do
        read -r peak nonfinite balance windup < <("$harness" "$so" "$q" nan-ceiling)
        awk -v p="$peak" -v c="$ceiling_limit" -v q="$q" \
            'BEGIN { if (p > c + 1e-6) { printf "quantum %s: a NaN ceiling disabled the limiter, peak reached %s\n", q, p > "/dev/stderr"; exit 1 } }'
        [[ "$nonfinite" = 0 ]] || {
            printf 'quantum %s: %s non-finite output samples with a NaN ceiling\n' "$q" "$nonfinite" >&2
            exit 1
        }
        awk -v g="$windup" -v q="$q" \
            'BEGIN { if (g < 20.0) { printf "quantum %s: AGC had only %s dB of boost wound on, the assertion is vacuous\n", q, g > "/dev/stderr"; exit 1 } }'
    done
    ;;
audio-normalization-agc-levels-quiet-passages)
    # The leveler must actually level. An unconditional snap-to-unity deadzone
    # once pinned the gain at 0 dB whenever a single block moved it by less
    # than the threshold, which silently disabled the whole normalizer at small
    # quanta and at slow Release settings while leaving every routing and port
    # assertion green.
    require_plugin_toolchain
    so="${DOTFILES_TEST_TMP}/agc-ceiling.so"
    build_plugin "$so"
    build_harness "${DOTFILES_TEST_TMP}/agc-harness.c" "${DOTFILES_TEST_TMP}/agc-harness"
    harness="${DOTFILES_TEST_TMP}/agc-harness"

    for q in 32 64 128 256 512 1024; do
        read -r peak nonfinite balance windup < <("$harness" "$so" "$q")
        # A -58 dBFS passage against a -28 LUFS target must draw a large boost
        # at every quantum, not just the large ones.
        awk -v g="$windup" -v q="$q" \
            'BEGIN { if (g < 20.0) { printf "quantum %s: AGC boosted a -58 dBFS passage by only %s dB; the leveler is frozen\n", q, g > "/dev/stderr"; exit 1 } }'
        # And it must stay inside the documented Max Gain safety bound.
        awk -v g="$windup" -v q="$q" \
            'BEGIN { if (g > 34.0 + 1e-3) { printf "quantum %s: AGC boost %s dB exceeds Max Gain 34 dB\n", q, g > "/dev/stderr"; exit 1 } }'
    done
    ;;
audio-normalization-filter-chains-are-nofail)
    # libpipewire-module-filter-chain is a mandatory context module: if a
    # fragment names a LADSPA plugin that cannot be loaded, PipeWire does not
    # merely skip that chain, it fails to create its context and the daemon
    # exits, taking the whole audio stack down. On 2026-09-03 this fragment was
    # deployed ahead of the compiled plugin and the workstation booted with no
    # audio at all, which in turn left Chromium on the ALSA fallback path.
    # Every filter chain that loads an external plugin must be nofail.
    for fragment in "${DOTFILES_TEST_ROOT}"/audio/dot-config/pipewire/pipewire.conf.d/*.conf; do
        rg -q --fixed-strings 'libpipewire-module-filter-chain' "$fragment" || continue
        assert_contains "$fragment" 'flags = [ ifexists nofail ]'
    done
    # And the two known chains must actually be present, so the loop above can
    # never pass vacuously.
    assert_contains "$conf" 'flags = [ ifexists nofail ]'
    assert_contains "${DOTFILES_TEST_ROOT}/audio/dot-config/pipewire/pipewire.conf.d/99-source-filter-rnnoise.conf" 'flags = [ ifexists nofail ]'
    ;;
audio-normalization-rebuild-restarts-pipewire)
    # A rebuilt plugin stays inert until PipeWire re-maps the .so, so the build
    # task must notify a restart. This once left a limiter fix on disk while the
    # running graph kept the unlimited build.
    assert_contains "$audio_playbook" 'notify:'
    assert_contains "$audio_playbook" '- handler_restart_pipewire'
    assert_contains "$audio_playbook" '- handler_restart_pipewire_pulse'
    assert_contains "$handlers" '- name: handler_restart_pipewire'
    assert_contains "$handlers" '- name: handler_restart_pipewire_pulse'
    assert_contains "$handlers" '    name: pipewire.service'
    assert_contains "$handlers" '    name: pipewire-pulse.service'
    # The build must fail loudly on any warning rather than ship a broken plugin.
    assert_contains "$audio_playbook" '      - -Wextra'
    assert_contains "$audio_playbook" '      - -Werror'
    ;;
audio-normalization-lua-syntax)
    luac -p "$lua_script"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
