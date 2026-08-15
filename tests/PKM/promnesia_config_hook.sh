#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: PKM
# dotfiles-test-tags: promnesia calibre-web hypothesis hook
# dotfiles-test-readonly: /home/aaaa/data/apps/PKM/.venv
# dotfiles-test-case: promnesia-hook-normalizes-calibre-show-to-read
# dotfiles-test-case: promnesia-hook-leaves-other-urls-untouched
# dotfiles-test-case: promnesia-hook-config-imports
# dotfiles-test-case: promnesia-config-imports-from-symlink

# Purpose: Verify the promnesia config HOOK rewrites calibre-web PDF URLs from
# /show/<id>/pdf (the raw PDF served to the hypothesis extension) to
# /read/<id>/pdf (the reader tab the user actually visits).

config_file="${DOTFILES_TEST_ROOT}/PKM/dot-config/promnesia/config.py"
venv_python=/home/aaaa/data/apps/PKM/.venv/bin/python

run_hook() {
    # Import the config module in-process and call its HOOK on the given
    # norm_url, printing the resulting norm_url(s).
    "$venv_python" - "$config_file" "$1" <<'PY'
import importlib.util
import sys

config_path, norm_url = sys.argv[1], sys.argv[2]

spec = importlib.util.spec_from_file_location("promnesia_test_config", config_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

from collections import namedtuple

# Reuse the real DbVisit via its class so _replace keeps working.
from promnesia.common import DbVisit, Loc
from datetime import datetime

visit = DbVisit(
    norm_url=norm_url,
    orig_url="https://" + norm_url,
    dt=datetime(2026, 8, 15),
    locator=Loc.make(title="t", href="h"),
    src="hypothesis",
    context=None,
    duration=None,
)

for v in module.HOOK(visit):
    print(v.norm_url)
PY
}

case "${DOTFILES_TEST_CASE:-}" in
promnesia-hook-normalizes-calibre-show-to-read)
    out=$(run_hook "calibre-web.local/show/22/pdf")
    [[ "$out" == "calibre-web.local/read/22/pdf" ]]
    ;;
promnesia-hook-leaves-other-urls-untouched)
    out=$(run_hook "github.com/Yan-Yu-Lin/claude-code-renderpatch")
    [[ "$out" == "github.com/Yan-Yu-Lin/claude-code-renderpatch" ]]
    ;;
promnesia-hook-config-imports)
    "$venv_python" - "$config_file" <<'PY'
import importlib.util
import sys

config_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("promnesia_test_config", config_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert callable(module.HOOK)
assert hasattr(module, "OUTPUT_DIR")
assert hasattr(module, "SOURCES")

# The sibling agent-conversations module must be importable through the
# config's sys.path setup and registered as a promnesia source.
from promnesia.config import Config

cfg = Config(SOURCES=module.SOURCES)
names = [s.name for s in cfg.sources if not isinstance(s, Exception)]
assert "agent-conversations" in names, names
PY
    ;;
promnesia-config-imports-from-symlink)
    # The deployed ~/.config/promnesia/config.py is a symlink into the repo.
    # Loading through the symlink must still find the sibling
    # agent_conversations module (config.py resolves the symlink before adding
    # its directory to sys.path) and register the source.
    linked_dir="${DOTFILES_TEST_TMP}/promnesia-config"
    mkdir -p "$linked_dir"
    ln -s "$config_file" "$linked_dir/config.py"

    "$venv_python" - "$linked_dir/config.py" <<'PY'
import importlib.util
import sys

config_path = sys.argv[1]
spec = importlib.util.spec_from_file_location("promnesia_test_config", config_path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

from promnesia.config import Config

cfg = Config(SOURCES=module.SOURCES)
names = [s.name for s in cfg.sources if not isinstance(s, Exception)]
assert "agent-conversations" in names, names
PY
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
