#!/bin/bash

set -euo pipefail

HOME_DIR="${HOME}"
SAVE_DIR="${HOME_DIR}/PKM/data/browsing"

mkdir -p "$SAVE_DIR"

browserexport save -b "brave" --to "$SAVE_DIR"
browserexport save -b "chrome" --to "$SAVE_DIR"
browserexport save -b "chromium" --to "$SAVE_DIR"
