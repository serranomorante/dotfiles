#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio stt screen-recording shell firejail
# dotfiles-test-case: record-screen-ffmpeg-syntax
# dotfiles-test-case: stt-dictate-transcribe-file-whisper

record_screen_script="${DOTFILES_TEST_ROOT}/audio/dot-local/bin/record-screen-ffmpeg"
stt_dictate_script="${DOTFILES_TEST_ROOT}/utilities/bin/stt-dictate"

case "${DOTFILES_TEST_CASE:-}" in
record-screen-ffmpeg-syntax)
    bash -n "$record_screen_script"
    sh -n "$stt_dictate_script"
    ;;
stt-dictate-transcribe-file-whisper)
    fixture="${DOTFILES_TEST_TMP}/stt-file"
    mkdir -p "$fixture"
    fake_whisper="${fixture}/whisper-cli"
    fake_model="${fixture}/model.bin"
    input_wav="${fixture}/input.wav"
    output_text="${fixture}/output.txt"

    : >"$fake_model"
    : >"$input_wav"
    cat >"$fake_whisper" <<'EOF'
#!/usr/bin/env sh
set -eu

output_prefix=
while [ "$#" -gt 0 ]; do
    case "$1" in
    --output-file)
        output_prefix=$2
        shift 2
        ;;
    *)
        shift
        ;;
    esac
done

[ -n "$output_prefix" ] || exit 2
printf '  hola   mundo  \n' >"${output_prefix}.txt"
EOF
    chmod +x "$fake_whisper"

    STT_DICTATE_BACKEND=whisper.cpp \
        STT_DICTATE_FIREJAIL=0 \
        STT_DICTATE_WHISPER_SERVER=0 \
        STT_DICTATE_WHISPER_BIN="$fake_whisper" \
        STT_DICTATE_WHISPER_MODEL="$fake_model" \
        STT_DICTATE_RUNTIME_DIR="${fixture}/runtime" \
        STT_DICTATE_PROJECT_DIR="${fixture}/project" \
        "$stt_dictate_script" transcribe-file --audio-file "$input_wav" --output "$output_text"

    actual=$(cat "$output_text")
    [[ "$actual" == "hola mundo" ]] || {
        printf 'unexpected transcription: %s\n' "$actual" >&2
        exit 1
    }
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
