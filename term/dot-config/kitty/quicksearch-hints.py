"""Kitty hints processor for quicksearch comments."""

import re


QUICKSEARCH_RE = re.compile(
    r"(?m)(?P<prefix>[^\w\s]+)\s*quicksearch(?:\s+(?P<filters>[^\0\r\n:]+?))?\s*:\s*(?P<pattern>[^\0\r\n]+)"
)


def mark(text, args, Mark, extra_cli_args, *a):
    """Mark only the search pattern while passing filters as action payload."""
    for idx, match in enumerate(QUICKSEARCH_RE.finditer(text)):
        pattern_start, pattern_end = match.span("pattern")
        pattern = match.group("pattern").replace("\n", "").replace("\0", "")
        filters = (match.group("filters") or "").strip()
        mark_text = f"{filters}: {pattern}" if filters else pattern
        yield Mark(idx, pattern_start, pattern_end, mark_text, {})
