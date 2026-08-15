from collections.abc import Iterator
from pathlib import Path
import re
import sys

from promnesia.common import DbVisit, Res, Source
from promnesia.sources import auto, browser
from promnesia.sources import hypothesis
from promnesia.sources import takeout

# Make sibling modules (agent_conversations) importable from the config dir.
# ~/.config/promnesia/config.py is a symlink into ~/dotfiles, so resolve it
# before computing the parent; otherwise the sibling modules are not found.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from agent_conversations import index as agent_conversations  # noqa: E402

# Keep the index and serve commands on the same database. The serve unit passes
# --db explicitly, while `promnesia index` resolves the DB from OUTPUT_DIR;
# inside the firejail wrapper XDG_DATA_HOME points at a separate sandbox tree,
# so without this the indexer wrote to a different sqlite than the server read.
OUTPUT_DIR = Path("~/.local/share/promnesia").expanduser()

# calibre-web serves the raw PDF at /show/<id>/pdf but the reader tab shows
# /read/<id>/pdf. The hypothesis extension annotates the raw PDF URL, so
# normalize /show -> /read so the annotation shows up while reading.
_calibre_show_re = re.compile(r'^(calibre-web\.local)/show/(\d+)/([a-z]+)$')


def HOOK(visit: Res[DbVisit]) -> Iterator[Res[DbVisit]]:
    if not isinstance(visit, DbVisit):
        yield visit
        return
    m = _calibre_show_re.match(visit.norm_url)
    if m is not None:
        host, book_id, fmt = m.groups()
        yield visit._replace(norm_url=f'{host}/read/{book_id}/{fmt}')
    else:
        yield visit


"""
List of sources to use.

You can specify your own, add more sources, etc.
See https://github.com/karlicoss/promnesia#setup for more information
"""
SOURCES = [
    browser,
    Source(hypothesis.index),
    Source(takeout.index, name="google-takeout"),
    Source(
        auto.index,
        "~/data/notes/foam",
        ignored=[
            "*.html",
            "*.yaml",
            "*.yml",
            "*.out",
            "*.jira",
            "*.bib",
            "*.lock",
            "*.scss",
            "*.err",
            "*.plist",
            "*/testing",
            "*/testing/*",
            "*/tags",
            "*/Gemfile",
            "*/assets/*",
        ],
        name="notes",
    ),
    Source(
        agent_conversations,
        "~/.claude/projects",
        "~/.codex/sessions",
        "~/.gemini/tmp",
        "~/.local/share/opencode",
        name="agent-conversations",
    ),
]
