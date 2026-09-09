/*
 * ladspa-agc-ceiling: EBU R128 automatic gain leveler for the Brave normalizer.
 *
 * Drives gain from libebur128 momentary loudness toward "Target LUFS" like
 * PipeWire's lufs2gain, but it levels aggressively: content above the noise
 * floor is normalized all the way to the target (quiet musical passages get a
 * large boost, loud ones duck fast with the "Attack (ms)" time and recover
 * with "Release (ms)"). "Max Gain (dB)" only bounds the boost as a safety
 * ceiling.
 *
 * Noise-floor handling: the boost is faded in linearly across a knee that runs
 * from "Floor LUFS" - "Knee (dB)" (no boost at all) up to "Floor LUFS" (full
 * boost). "Floor LUFS" is therefore the point where boosting becomes complete,
 * not the point where it starts; with the defaults (-58 LUFS floor, 14 dB
 * knee) nothing below -72 LUFS is lifted, so base mic/room hiss is never
 * raised into audibility. Lowering "Floor LUFS" ignores more near-silent
 * content.
 *
 * Stereo: this is a single 2-in/2-out plugin, not two mono instances. One
 * libebur128 state measures the stereo program, one gain is applied to both
 * channels and one limiter gain is shared between them. Leveling each channel
 * on its own would normalize L and R independently and collapse the stereo
 * image on any panned material.
 *
 * The AGC is feedforward (loudness is measured on the input), so a quiet
 * passage held at a large boost can still overshoot when a sudden fortissimo
 * arrives before the momentary window catches up. A sample-peak limiter is
 * therefore the final stage: it reduces gain instantly so no output sample
 * ever exceeds "Ceiling (dB)" (hard-capped at 0 dBFS), then recovers over
 * "Limiter Release (ms)". This is the hard output ceiling the AGC "Max Gain"
 * cannot provide on its own, and a final unconditional clamp enforces it
 * independently of every gain computation above.
 *
 * Every control is sanitized on read: a non-finite value falls back to its
 * documented default and is then clamped to the published port range, so no
 * control value can disable the ceiling.
 *
 * The block gain is ramped sample by sample from the previous block's gain to
 * the new one, so a fast Attack cannot produce a gain step at a block boundary.
 *
 * Linked against libebur128.
 */

#include <math.h>
#include <stdlib.h>

#include <ebur128.h>
#include <ladspa.h>

#define AGC_LABEL "agc_ceiling"
#define AGC_UID 1146172486UL /* 'DOTF' in hex */
#define AGC_COPYRIGHT "GPL"

#define AGC_CHANNELS 2u
/* Interleave scratch is preallocated so run() never allocates: HARD_RT_CAPABLE. */
#define AGC_CHUNK 1024u

enum {
	PORT_IN_L = 0,
	PORT_IN_R,
	PORT_OUT_L,
	PORT_OUT_R,
	PORT_TARGET_LUFS,
	PORT_FLOOR_LUFS,
	PORT_KNEE_DB,
	PORT_MAX_GAIN_DB,
	PORT_ATTACK_MS,
	PORT_RELEASE_MS,
	PORT_CEILING_DB,
	PORT_LIM_RELEASE_MS,
	PORT_GAIN_OUT,
	PORT_COUNT
};

typedef struct {
	unsigned long rate;
	ebur128_state *st;

	LADSPA_Data *in[AGC_CHANNELS];
	LADSPA_Data *out[AGC_CHANNELS];
	const LADSPA_Data *target_lufs;
	const LADSPA_Data *floor_lufs;
	const LADSPA_Data *knee_db;
	const LADSPA_Data *max_gain_db;
	const LADSPA_Data *attack_ms;
	const LADSPA_Data *release_ms;
	const LADSPA_Data *ceiling_db;
	const LADSPA_Data *lim_release_ms;
	LADSPA_Data *gain_out;

	float ilv[AGC_CHUNK * AGC_CHANNELS];

	double current_db;
	double prev_gain;
	double lim_gain;
} agc_state_t;

static LADSPA_Handle agc_instantiate(const LADSPA_Descriptor *desc, unsigned long rate)
{
	(void)desc;
	agc_state_t *s = calloc(1, sizeof(*s));
	if (s == NULL)
		return NULL;
	s->rate = rate ? rate : 48000;
	s->current_db = 0.0;
	s->prev_gain = 1.0;
	s->lim_gain = 1.0;
	return s;
}

static void agc_connect_port(LADSPA_Handle h, unsigned long port, LADSPA_Data *data)
{
	agc_state_t *s = (agc_state_t *)h;
	switch (port) {
	case PORT_IN_L: s->in[0] = data; break;
	case PORT_IN_R: s->in[1] = data; break;
	case PORT_OUT_L: s->out[0] = data; break;
	case PORT_OUT_R: s->out[1] = data; break;
	case PORT_TARGET_LUFS: s->target_lufs = data; break;
	case PORT_FLOOR_LUFS: s->floor_lufs = data; break;
	case PORT_KNEE_DB: s->knee_db = data; break;
	case PORT_MAX_GAIN_DB: s->max_gain_db = data; break;
	case PORT_ATTACK_MS: s->attack_ms = data; break;
	case PORT_RELEASE_MS: s->release_ms = data; break;
	case PORT_CEILING_DB: s->ceiling_db = data; break;
	case PORT_LIM_RELEASE_MS: s->lim_release_ms = data; break;
	case PORT_GAIN_OUT: s->gain_out = data; break;
	}
}

static void agc_activate(LADSPA_Handle h)
{
	agc_state_t *s = (agc_state_t *)h;
	if (s->st != NULL)
		ebur128_destroy(&s->st);
	s->st = ebur128_init(AGC_CHANNELS, s->rate, EBUR128_MODE_M);
	s->current_db = 0.0;
	s->prev_gain = 1.0;
	s->lim_gain = 1.0;
	if (s->gain_out)
		*s->gain_out = (LADSPA_Data)s->current_db;
}

static double agc_clampd(double v, double lo, double hi)
{
	return v < lo ? lo : (v > hi ? hi : v);
}

/* Reads a control, substituting the default for a non-finite value. Callers
 * clamp the result to the port range; agc_clampd would pass NaN straight
 * through, so the isfinite test has to happen here. */
static double agc_read(const LADSPA_Data *ptr, double def)
{
	double v = ptr ? (double)*ptr : def;
	return isfinite(v) ? v : def;
}

static void agc_run(LADSPA_Handle h, unsigned long n)
{
	agc_state_t *s = (agc_state_t *)h;
	unsigned long i, done;
	unsigned c;

	for (c = 0; c < AGC_CHANNELS; c++) {
		if (s->in[c] == NULL || s->out[c] == NULL)
			return;
	}
	if (n == 0)
		return;

	double target = agc_clampd(agc_read(s->target_lufs, -28.0), -70.0, 0.0);
	double floor_lufs = agc_clampd(agc_read(s->floor_lufs, -58.0), -90.0, -20.0);
	double knee = agc_clampd(agc_read(s->knee_db, 14.0), 0.5, 40.0);
	double max_gain = agc_clampd(agc_read(s->max_gain_db, 34.0), 0.0, 60.0);
	double attack_ms = agc_clampd(agc_read(s->attack_ms, 20.0), 1.0, 1000.0);
	double release_ms = agc_clampd(agc_read(s->release_ms, 500.0), 10.0, 5000.0);
	/* Clamped to at most 0 dBFS: the ceiling can never be raised above full scale. */
	double ceiling_db = agc_clampd(agc_read(s->ceiling_db, -1.0), -40.0, 0.0);
	double lim_release_ms = agc_clampd(agc_read(s->lim_release_ms, 200.0), 1.0, 5000.0);

	double desired_db = 0.0;
	if (s->st != NULL) {
		double m;
		for (done = 0; done < n;) {
			unsigned long k = n - done;
			if (k > AGC_CHUNK)
				k = AGC_CHUNK;
			for (i = 0; i < k; i++) {
				s->ilv[i * AGC_CHANNELS + 0] = s->in[0][done + i];
				s->ilv[i * AGC_CHANNELS + 1] = s->in[1][done + i];
			}
			if (ebur128_add_frames_float(s->st, s->ilv, (size_t)k) != EBUR128_SUCCESS)
				break;
			done += k;
		}
		if (ebur128_loudness_momentary(s->st, &m) == EBUR128_SUCCESS && isfinite(m)) {
			desired_db = target - m;             /* normalize to target */
			if (desired_db > max_gain)
				desired_db = max_gain;           /* safety ceiling on boost */
			if (desired_db > 0.0) {
				/* Fade the boost in over the knee: none at (floor - knee),
				 * full at floor. */
				double w = (m - floor_lufs + knee) / knee;
				desired_db *= agc_clampd(w, 0.0, 1.0);
			}
		}
	}

	/* Duck and floor-fade moves are fast; recovery is slow. */
	double ms = (desired_db < s->current_db) ? attack_ms : release_ms;
	double coeff = 1.0 - exp(-(double)n / ((double)s->rate * ms / 1000.0));
	s->current_db += (desired_db - s->current_db) * coeff;
	/* Snap to unity only when unity is also where the gain is heading. An
	 * unconditional snap pins the gain at 0 dB whenever one block moves it
	 * by less than the threshold, which froze the AGC outright at small
	 * quanta or slow Release settings. */
	if (fabs(s->current_db) < 0.05 && fabs(desired_db) < 0.05)
		s->current_db = 0.0;

	double gain = pow(10.0, s->current_db / 20.0);
	double g0 = s->prev_gain;
	double gstep = (gain - g0) / (double)n;
	double ceiling = pow(10.0, ceiling_db / 20.0);
	double lim_rel = 1.0 - exp(-1.0 / ((double)s->rate * lim_release_ms / 1000.0));

	for (i = 0; i < n; i++) {
		double g = g0 + gstep * (double)(i + 1);
		double y[AGC_CHANNELS];
		double peak = 0.0;

		for (c = 0; c < AGC_CHANNELS; c++) {
			y[c] = (double)s->in[c][i] * g;
			if (!isfinite(y[c]))
				y[c] = 0.0;
			if (fabs(y[c]) > peak)
				peak = fabs(y[c]);
		}
		/* One limiter gain shared by both channels: a per-channel limiter
		 * would pan the mix on every peak. */
		if (peak * s->lim_gain > ceiling)
			s->lim_gain = ceiling / peak;
		for (c = 0; c < AGC_CHANNELS; c++) {
			/* Unconditional clamp: the ceiling holds even if the gain
			 * arithmetic above ever misbehaves. */
			s->out[c][i] = (LADSPA_Data)agc_clampd(y[c] * s->lim_gain, -ceiling, ceiling);
		}
		s->lim_gain += (1.0 - s->lim_gain) * lim_rel;
	}
	s->prev_gain = gain;

	if (s->gain_out)
		*s->gain_out = (LADSPA_Data)s->current_db;
}

static void agc_cleanup(LADSPA_Handle h)
{
	agc_state_t *s = (agc_state_t *)h;
	if (s == NULL)
		return;
	if (s->st != NULL)
		ebur128_destroy(&s->st);
	free(s);
}

/* Designated initializers keyed on the port enum: adding or reordering a port
 * can no longer shift the rest of a table by one. */
static const LADSPA_PortDescriptor port_descriptors[PORT_COUNT] = {
	[PORT_IN_L] = LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO,
	[PORT_IN_R] = LADSPA_PORT_INPUT | LADSPA_PORT_AUDIO,
	[PORT_OUT_L] = LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO,
	[PORT_OUT_R] = LADSPA_PORT_OUTPUT | LADSPA_PORT_AUDIO,
	[PORT_TARGET_LUFS] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	[PORT_FLOOR_LUFS] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	[PORT_KNEE_DB] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	[PORT_MAX_GAIN_DB] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	[PORT_ATTACK_MS] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	[PORT_RELEASE_MS] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	[PORT_CEILING_DB] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	[PORT_LIM_RELEASE_MS] = LADSPA_PORT_INPUT | LADSPA_PORT_CONTROL,
	[PORT_GAIN_OUT] = LADSPA_PORT_OUTPUT | LADSPA_PORT_CONTROL,
};

static const char *const port_names[PORT_COUNT] = {
	[PORT_IN_L] = "In L",
	[PORT_IN_R] = "In R",
	[PORT_OUT_L] = "Out L",
	[PORT_OUT_R] = "Out R",
	[PORT_TARGET_LUFS] = "Target LUFS",
	[PORT_FLOOR_LUFS] = "Floor LUFS",
	[PORT_KNEE_DB] = "Knee (dB)",
	[PORT_MAX_GAIN_DB] = "Max Gain (dB)",
	[PORT_ATTACK_MS] = "Attack (ms)",
	[PORT_RELEASE_MS] = "Release (ms)",
	[PORT_CEILING_DB] = "Ceiling (dB)",
	[PORT_LIM_RELEASE_MS] = "Limiter Release (ms)",
	[PORT_GAIN_OUT] = "Gain (dB)",
};

/* Defaults for hosts other than the repo filter chain (which sets every
 * control explicitly). "Max Gain" defaults to its minimum, so an unconfigured
 * instance applies no boost at all, and "Ceiling" to 0 dBFS. */
static const LADSPA_PortRangeHint port_range_hints[PORT_COUNT] = {
	[PORT_IN_L] = { 0, 0.0f, 0.0f },
	[PORT_IN_R] = { 0, 0.0f, 0.0f },
	[PORT_OUT_L] = { 0, 0.0f, 0.0f },
	[PORT_OUT_R] = { 0, 0.0f, 0.0f },
	[PORT_TARGET_LUFS] = { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
			       LADSPA_HINT_DEFAULT_MIDDLE, -70.0f, 0.0f },
	[PORT_FLOOR_LUFS] = { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
			      LADSPA_HINT_DEFAULT_MIDDLE, -90.0f, -20.0f },
	[PORT_KNEE_DB] = { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
			   LADSPA_HINT_DEFAULT_MIDDLE, 0.5f, 40.0f },
	[PORT_MAX_GAIN_DB] = { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
			       LADSPA_HINT_DEFAULT_MINIMUM, 0.0f, 60.0f },
	[PORT_ATTACK_MS] = { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
			     LADSPA_HINT_DEFAULT_LOW, 1.0f, 1000.0f },
	[PORT_RELEASE_MS] = { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
			      LADSPA_HINT_DEFAULT_LOW, 10.0f, 5000.0f },
	[PORT_CEILING_DB] = { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
			      LADSPA_HINT_DEFAULT_MAXIMUM, -40.0f, 0.0f },
	[PORT_LIM_RELEASE_MS] = { LADSPA_HINT_BOUNDED_BELOW | LADSPA_HINT_BOUNDED_ABOVE |
				  LADSPA_HINT_DEFAULT_LOW, 1.0f, 5000.0f },
	[PORT_GAIN_OUT] = { 0, 0.0f, 0.0f },
};

static const LADSPA_Descriptor agc_descriptor = {
	.UniqueID = AGC_UID,
	.Label = AGC_LABEL,
	.Properties = LADSPA_PROPERTY_HARD_RT_CAPABLE,
	.Name = "Dotfiles stereo AGC leveler with noise floor and peak limiter",
	.Maker = "dotfiles",
	.Copyright = AGC_COPYRIGHT,
	.PortCount = PORT_COUNT,
	.PortDescriptors = port_descriptors,
	.PortNames = port_names,
	.PortRangeHints = port_range_hints,
	.instantiate = agc_instantiate,
	.connect_port = agc_connect_port,
	.activate = agc_activate,
	.run = agc_run,
	.cleanup = agc_cleanup,
};

const LADSPA_Descriptor *ladspa_descriptor(unsigned long index)
{
	return index == 0 ? &agc_descriptor : NULL;
}
