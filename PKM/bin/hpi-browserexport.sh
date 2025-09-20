#!/usr/bin/env bash

set -o pipefail
set -ex

SAVE_DIR="${HOME}/PKM/data/browsing"

mkdir -p "$SAVE_DIR"

save_database() {
  local BROWSER="${1:?Must provide browser to backup}"
  browserexport save -b "${BROWSER}" --to "${SAVE_DIR}" || {
    grep -q "$BROWSER" <<<'chrome' || {
      send-error "browserexport: failed to backup ${BROWSER} database..."
    }
  }
}

save_database brave
save_database chrome
save_database chromium
