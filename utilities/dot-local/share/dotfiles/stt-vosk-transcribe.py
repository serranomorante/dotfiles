#!/usr/bin/env python3

"""Transcribe raw mono PCM audio with one or more Vosk models."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any


def parse_model(value: str) -> tuple[str, Path]:
    if ":" not in value:
        raise argparse.ArgumentTypeError("model must be LANG:PATH")
    lang, path = value.split(":", 1)
    if not lang:
        raise argparse.ArgumentTypeError("model language is empty")
    model_path = Path(path).expanduser()
    if not model_path.is_dir():
        raise argparse.ArgumentTypeError(f"missing model directory: {model_path}")
    return lang, model_path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audio-file", required=True, type=Path)
    parser.add_argument("--sample-rate", required=True, type=int)
    parser.add_argument(
        "--model",
        action="append",
        required=True,
        type=parse_model,
        help="Language and Vosk model path, formatted as LANG:PATH.",
    )
    parser.add_argument(
        "--language",
        default="auto",
        help="Language to emit, or auto to select the highest-scoring model.",
    )
    parser.add_argument("--chunk-size", default=16000, type=int)
    return parser.parse_args()


def transcribe_model(model_path: Path, audio_file: Path, sample_rate: int, chunk_size: int) -> dict[str, Any]:
    import vosk  # type: ignore

    model = vosk.Model(str(model_path))
    recognizer = vosk.KaldiRecognizer(model, sample_rate)
    recognizer.SetWords(True)

    parts: list[str] = []
    words: list[dict[str, Any]] = []

    with audio_file.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            if recognizer.AcceptWaveform(chunk):
                result = json.loads(recognizer.Result())
                text = result.get("text", "")
                if text:
                    parts.append(text)
                words.extend(result.get("result", []))

    final = json.loads(recognizer.FinalResult())
    final_text = final.get("text", "")
    if final_text:
        parts.append(final_text)
    words.extend(final.get("result", []))

    text = " ".join(parts).strip()
    confidences = [float(word["conf"]) for word in words if "conf" in word]
    avg_confidence = sum(confidences) / len(confidences) if confidences else 0.0
    word_count = len(text.split())

    # Confidence is not perfectly comparable across language models. Weight it
    # lightly by recognized length so a one-word false positive does not beat a
    # complete sentence with similar confidence.
    score = avg_confidence * math.log2(word_count + 1) if text else 0.0

    return {
        "text": text,
        "word_count": word_count,
        "avg_confidence": avg_confidence,
        "score": score,
    }


def main() -> int:
    args = parse_args()
    audio_file = args.audio_file.expanduser()
    if not audio_file.is_file():
        print(f"missing audio file: {audio_file}", file=sys.stderr)
        return 2

    requested_language = args.language
    models = dict(args.model)
    if requested_language != "auto":
        if requested_language not in models:
            print(f"missing model for language: {requested_language}", file=sys.stderr)
            return 2
        selected_models = [(requested_language, models[requested_language])]
    else:
        selected_models = args.model

    results: list[tuple[str, dict[str, Any]]] = []
    for lang, model_path in selected_models:
        result = transcribe_model(model_path, audio_file, args.sample_rate, args.chunk_size)
        results.append((lang, result))
        print(
            "model=%s words=%d avg_confidence=%.3f score=%.3f"
            % (lang, result["word_count"], result["avg_confidence"], result["score"]),
            file=sys.stderr,
        )

    lang, best = max(results, key=lambda item: item[1]["score"])
    text = best["text"].strip()
    if not text:
        print("no text recognized", file=sys.stderr)
        return 1

    print(f"selected={lang}", file=sys.stderr)
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
