# Voice Workflows

This document describes local voice workflows: text-to-speech for narrating terminal commands, TUIs, and AI CLIs, plus speech-to-text dictation for entering text from a global keyboard shortcut.

## Text-To-Speech Baseline

Use local, repository-managed tools:

- `piper-tts` provides the preferred high-quality local neural voice when its managed venv, voices, and Firejail-isolated HTTP server are available.
- `speech-dispatcher` provides the high-level `spd-say` interface and queues speech.
- `espeak-ng` provides a compact local synthesizer and direct fallback.
- `tts-pty` runs any interactive CLI in a pseudo-terminal and speaks the output stream.
- `tts-tui` runs any Kitty-hosted TUI while `tts-screen` speaks stable visible screen changes.

Piper is the quality path. `speech-dispatcher` plus `espeak-ng` remains the fallback because it is simple, official Arch packaging and does not depend on Python wheels, downloaded voice models, or a user service.

## Speech-To-Text Baseline

Use a local, Firejail-sandboxed dictation path:

- `stt-dictate` owns the user-facing toggle/cancel workflow.
- `whisper.cpp` provides the preferred high-accuracy local backend when its CUDA build and managed model are installed.
- `stt-vosk-transcribe` runs final transcription with `python-vosk`.
- `nerd-dictation` remains available as an explicit single-language backend.
- `pw-cat` records microphone audio through PipeWire, targeting the RNNoise source `source_filter.rnnoise` by default.
- `xclip` stores recognized text in the clipboard, and `xdotool` attempts a `Ctrl+Shift+V` paste into the focused app.

`stt-dictate` uses `STT_DICTATE_BACKEND=auto` by default. Auto mode selects `whisper.cpp` when its binary, selected profile model, and Firejail profile exist; otherwise it keeps the Vosk path so the keymap does not break before the Whisper setup has been applied. The Whisper path records a 16 kHz mono WAV take and first tries the resident `whisper-server` user service for the selected profile. If the service is unavailable, it falls back to running `whisper-cli` through the dedicated `fj-whisper-cpp.profile` sandbox. The Vosk path records raw PCM and runs final transcription through `fj-py offline`. Clipboard and keyboard injection stay outside the recognizer sandbox.

`stt-dictate transcribe-file --audio-file <wav>` is the file-input contract for tools that already have an audio snippet, such as `record-screen-ffmpeg pause-listen`. It uses the same backend selection, profiles, language settings, and Firejail boundaries as live dictation, but writes recognized text to stdout or `--output` and does not touch the clipboard or focused window.

The resident Whisper service is `stt-whisper@<profile>.service`, launched by `stt-whisper-server`. It keeps one model loaded inside a named Firejail sandbox (`stt-whisper-fast`, `stt-whisper-balanced`, or `stt-whisper-accurate`) and listens on loopback inside that sandbox. `stt-dictate` joins the same sandbox to POST the recorded WAV to `/inference`, avoiding host-network exposure while also avoiding per-dictation model load time. The `fj-whisper-cpp.profile` keeps networking disabled at runtime and exposes only the runtime audio directory, the selected model, and the managed binary. CUDA requires access to `/dev/nvidia*`, so this profile does not use Firejail's `private-dev`; it disables unrelated desktop device classes instead.

The default raw audio input is `STT_DICTATE_SOURCE=source_filter.rnnoise`, so the recognizer receives the noise-suppressed microphone signal. If that PipeWire node is not available, `stt-dictate` falls back to PipeWire's default source unless `STT_DICTATE_SOURCE_FALLBACK=0` is set.

The baseline language mode is `STT_DICTATE_LANG=auto`. For Whisper, this uses Whisper's language detection so Spanish and English can be spoken without switching configuration. For the Vosk fallback, auto mode tries both Spanish and English models against the same recording and selects the higher-scoring transcription. The managed models are:

```text
~/data/apps/dev-tools/ai-tools/whisper.cpp/models/ggml-base-q5_1.bin
~/data/apps/dev-tools/ai-tools/whisper.cpp/models/ggml-large-v3-turbo-q5_0.bin
~/data/apps/dev-tools/ai-tools/whisper.cpp/models/ggml-medium.bin
~/.local/share/vosk/vosk-model-small-es-0.42
~/.local/share/vosk/vosk-model-small-en-us-0.15
```

Whisper dictation profiles trade latency against recognition quality:

```text
fast      ggml-base-q5_1.bin            threads=8 beam-size=1 best-of=1 no-fallback
balanced  ggml-large-v3-turbo-q5_0.bin  threads=6 beam-size=2 best-of=2
accurate  ggml-medium.bin               threads=4 beam-size=5 best-of=5
```

`fast` is the default because dictation is latency-sensitive and short utterances should return quickly. Use `balanced` when the base model is not reliable enough, and `accurate` when latency matters less than transcription quality.

The keyd path is:

```text
tab+d       toggle recording
tab+shift+d cancel recording
```

On stop, recognized text is always copied to the clipboard before any paste attempt. This keeps dictation useful when the focused target cannot accept text.

## Text-To-Speech Workflow

Use the wrappers for terminal commands and agents when you want narrated output:

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

`tts-stop` is the emergency brake for the repository TTS pipeline. It writes a runtime stop marker under `${TTS_RUNTIME_DIR:-$XDG_RUNTIME_DIR/tts}`, stops active `tts-screen` pollers, terminates registered `tts-say` and `piper-say` processes, kills registered Piper audio-player PIDs, and still clears Speech Dispatcher plus direct `espeak-ng` playback. Use it from another terminal when an interactive command such as `claude` has not yet reacted to `Ctrl-C`.

The wrappers do not require Kitty, Xorg, Plasma, or dwm to be running. A login shell, local audio, and the installed TTS packages are enough, so the same commands work from a plain TTY.

Use `tts-pty` for line-oriented output. It keeps the original terminal interactive while mirroring output to speech. It records the terminal output under `$XDG_RUNTIME_DIR/tts-pty/` so a later command can inspect exactly what was spoken. It is command-agnostic and passes `<command> [args...]` through directly.

Use `tts-tui` for redraw-heavy TUIs. It starts `tts-screen`, which polls Kitty's current visible screen with `kitten @ get-text --extent screen`, waits for stable redraws, and speaks only normalized lines that have not been seen in the current run. This avoids reading text that was later erased by a TUI repaint. It is also command-agnostic; examples such as `nnn`, `lazygit`, `htop`, `codex`, and `claude` do not require per-application entries.

Screen mode is intentionally less immediate than stream mode. Tune these when needed:

```sh
TTS_SCREEN_INTERVAL=1 TTS_SCREEN_STABLE_POLLS=2 tts-tui nnn
TTS_SCREEN_MAX_CHARS=600 TTS_SCREEN_MAX_LINES=10 tts-tui lazygit
```

The default voice settings are intentionally tuned for intelligibility over speed: slower speech, shorter chunks, less pitch variation, no punctuation names, and light terminal-output normalization. Override them only when needed, for example:

```sh
TTS_SAY_LANG=en tts-pty codex
TTS_SAY_RATE=-10 TTS_STREAM_MAX_CHARS=500 tts-pty claude
```

Each TTS wrapper's `--help` output should list the environment variables it supports directly, including wrapper-selection variables such as `TTS_PTY_STREAM` and backend-specific variables such as `PIPER_TTS_VOICE`. When changing supported environment variables, update `--help` in the same patch.

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

`piper-say` sends `speaker_id=0` by default. This avoids Piper HTTP warnings for multi-speaker voices such as `es_ES-sharvard-medium`; override with `PIPER_TTS_SPEAKER_ID=1` or `PIPER_TTS_SPEAKER=F` when the Spanish female speaker is preferred.

`piper-say` also drops chunks with no alphanumeric characters before contacting Piper. Agent output often contains separators, icons, or cursor artifacts that can phonemize to zero audio and trigger Piper HTTP 500 errors.

## Speech-To-Text Workflow

Manual checks:

```sh
stt-dictate begin
stt-dictate end
stt-dictate cancel
stt-dictate status
```

Useful overrides:

```sh
STT_DICTATE_AUTO_PASTE=0 stt-dictate toggle
STT_DICTATE_BACKEND=whisper.cpp stt-dictate toggle
STT_DICTATE_BACKEND=raw-vosk stt-dictate toggle
STT_DICTATE_PROFILE=fast stt-dictate toggle
STT_DICTATE_PROFILE=balanced stt-dictate toggle
STT_DICTATE_PROFILE=accurate stt-dictate toggle
STT_DICTATE_SOURCE=source_filter.rnnoise stt-dictate toggle
STT_DICTATE_SOURCE= stt-dictate toggle
STT_DICTATE_SOURCE_FALLBACK=0 stt-dictate toggle
STT_DICTATE_LANG=es stt-dictate toggle
STT_DICTATE_LANG=en stt-dictate toggle
STT_DICTATE_FULL_SENTENCE=1 stt-dictate toggle
STT_DICTATE_NUMBERS_AS_DIGITS=1 stt-dictate toggle
STT_DICTATE_FIREJAIL=0 stt-dictate toggle
STT_DICTATE_BACKEND=nerd-dictation STT_DICTATE_LANG=es stt-dictate toggle
```

`STT_DICTATE_FIREJAIL=0` is only for debugging sandbox or audio-device issues. Do not make unsandboxed recognizer execution the default.

Manage the resident Whisper servers with systemd user units. These units should be started on demand, not enabled by default:

```sh
systemctl --user start stt-whisper@fast.service
systemctl --user start stt-whisper@balanced.service
systemctl --user stop stt-whisper@accurate.service
```

`stt-dictate` starts the selected service when recording begins if `STT_DICTATE_WHISPER_SERVER_START=1`, which is the default. The first `tab+d` after boot begins warming the model while audio is being recorded; later requests reuse the resident server for the current boot/session unless it is stopped.

## Constraints

- `tts-pty` is not a full screen reader. Full-screen terminal UIs can redraw frequently, so use `tts-tui` for Kitty-hosted TUIs when possible.
- Prefer line-oriented agent output when available.
- Keep the stack local: do not depend on cloud TTS/STT, a browser, or an AUR neural voice model for the fallback layer.
- When adding Piper, Whisper, or another TTS/STT engine, install and run it through the Firejail workflow documented in [firejail-dev-tools.md](./firejail-dev-tools.md). Document any GPU device exception at the profile boundary.
