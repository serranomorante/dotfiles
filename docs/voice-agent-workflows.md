# Voice TTS Workflows

This document describes text-to-speech paths for narrating terminal commands,
TUIs, and AI CLIs from a local, repository-managed stack.

## Baseline

Use local, repository-managed tools:

- `piper-tts` provides the preferred high-quality local neural voice when its
  managed venv, voices, and Firejail-isolated HTTP server are available.
- `speech-dispatcher` provides the high-level `spd-say` interface and queues
  speech.
- `espeak-ng` provides a compact local synthesizer and direct fallback.
- `tts-pty` runs any interactive CLI in a pseudo-terminal and speaks the
  output stream.
- `tts-tui` runs any Kitty-hosted TUI while `tts-screen` speaks stable visible
  screen changes.

Piper is the quality path. `speech-dispatcher` plus `espeak-ng` remains the
fallback because it is simple, official Arch packaging and does not depend on
Python wheels, downloaded voice models, or a user service.

## Workflow

Use the wrappers for terminal commands and agents when you want narrated
output:

```sh
tts-pty bash
tts-pty codex
tts-tui nnn
tts-tui lazygit
TTS_SAY_LANG=en tts-pty codex
```

Verify speech end-to-end with:

```sh
tts-say "audio operativo"
```

Stop runaway speech with:

```sh
tts-stop
```

`tts-stop` is the emergency brake for the repository TTS pipeline. It writes a
runtime stop marker under `${TTS_RUNTIME_DIR:-$XDG_RUNTIME_DIR/tts}`, stops
active `tts-screen` pollers, terminates registered `tts-say` and `piper-say`
processes, kills registered Piper audio-player PIDs, and still clears Speech
Dispatcher plus direct `espeak-ng` playback. Use it from another terminal when
an interactive command such as `claude` has not yet reacted to `Ctrl-C`.

The wrappers do not require Kitty, Xorg, Plasma, or dwm to be running. A login
shell, local audio, and the installed TTS packages are enough, so the same
commands work from a plain TTY.

Use `tts-pty` for line-oriented output. It keeps the original terminal
interactive while mirroring output to speech. It records the terminal output
under `$XDG_RUNTIME_DIR/tts-pty/` so a later command can inspect exactly what
was spoken. It is command-agnostic and passes `<command> [args...]` through
directly.

Use `tts-tui` for redraw-heavy TUIs. It starts `tts-screen`, which polls
Kitty's current visible screen with `kitten @ get-text --extent screen`, waits
for stable redraws, and speaks only normalized lines that have not been seen in
the current run. This avoids reading text that was later erased by a TUI
repaint. It is also command-agnostic; examples such as `nnn`, `lazygit`,
`htop`, `codex`, and `claude` do not require per-application entries.

Screen mode is intentionally less immediate than stream mode. Tune these when
needed:

```sh
TTS_SCREEN_INTERVAL=1 TTS_SCREEN_STABLE_POLLS=2 tts-tui nnn
TTS_SCREEN_MAX_CHARS=600 TTS_SCREEN_MAX_LINES=10 tts-tui lazygit
```

The default voice settings are intentionally tuned for intelligibility over
speed: slower speech, shorter chunks, less pitch variation, no punctuation
names, and light terminal-output normalization. Override them only when needed,
for example:

```sh
TTS_SAY_LANG=en tts-pty codex
TTS_SAY_RATE=-10 TTS_STREAM_MAX_CHARS=500 tts-pty claude
```

Each TTS wrapper's `--help` output should list the environment variables it
supports directly, including wrapper-selection variables such as
`TTS_PTY_STREAM` and backend-specific variables such as `PIPER_TTS_VOICE`. When
changing supported environment variables, update `--help` in the same patch.

`tts-say` tries backends in this order:

1. Piper through `piper-say`.
1. Speech Dispatcher through `spd-say`.
1. Direct `espeak-ng`.

Use an explicit backend for tests:

```sh
TTS_SAY_BACKEND=piper tts-say "voz neuronal local"
TTS_SAY_BACKEND=espeak-ng tts-say "fallback local"
```

Piper uses these managed defaults:

```text
python: pyenv 3.11.3
venv:   ~/data/apps/dev-tools/ai-tools/piper-tts/.venv
voices: ~/data/apps/dev-tools/ai-tools/piper-tts/voices
server: Firejail sandbox piper-tts, 127.0.0.1:10200 inside the sandbox
English voice/default: en_US-lessac-medium
Spanish voice: es_ES-sharvard-medium, speakers M=0 and F=1
```

`piper-say` sends `speaker_id=0` by default. This avoids Piper HTTP warnings
for multi-speaker voices such as `es_ES-sharvard-medium`; override with
`PIPER_TTS_SPEAKER_ID=1` or `PIPER_TTS_SPEAKER=F` when the Spanish female
speaker is preferred.

`piper-say` also drops chunks with no alphanumeric characters before contacting
Piper. Agent output often contains separators, icons, or cursor artifacts that
can phonemize to zero audio and trigger Piper HTTP 500 errors.

## Constraints

- `tts-pty` is not a full screen reader. Full-screen terminal UIs can redraw
  frequently, so use `tts-tui` for Kitty-hosted TUIs when possible.
- Prefer line-oriented agent output when available.
- Keep the stack local: do not depend on cloud TTS, a browser, or an AUR
  neural voice model.
- When adding Piper or another Python TTS engine, install and run it through
  the Firejail workflow documented in
  [firejail-dev-tools.md](./firejail-dev-tools.md).
