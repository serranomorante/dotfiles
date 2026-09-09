"""Kitty hints processor for nvim. evidence references."""

import re


# A long reference does not reach the terminal intact: the agent's own renderer
# hard-wraps its output, so a newline plus the next line's indentation can land
# anywhere inside the path, the locator, or even the prefix. Those breaks become
# a NUL sentinel before matching, padding included. The pattern lets the
# sentinel through every part of a reference, while the surrounding lookarounds
# still read it as a boundary, so a wrap never glues a reference to unrelated
# neighbouring text.
JOIN = "\x00"

# Both sides of the break are stripped: a TUI pads its lines to the render
# width, so the whitespace before the newline is padding, not content.
WRAP_RE = re.compile(r"[ \t]*\n[ \t]*")

_SEP = r"\x00?"
_PATH = r"/[^\s:]+"  # the sentinel is neither whitespace nor ':', so wraps pass
_LINE = r"[0-9](?:\x00?[0-9])*"
_HASH = r"[0-9a-fA-F](?:\x00?[0-9a-fA-F]){6,39}"


def _wrappable(literal):
    """Allow a wrap between any two characters of a literal."""
    return _SEP.join(re.escape(char) for char in literal)


NVIM_REF_RE = re.compile(
    r"(?<![\w.:/-])(?:"
    + _wrappable("nvim.file:") + _SEP + _PATH + _SEP + ":" + _SEP + _LINE
    + r"|"
    + _wrappable("nvim.commit:") + _SEP + _PATH + _SEP + ":" + _SEP + _HASH
    + r")(?![0-9A-Za-z_-])"
)


def _unwrap(text):
    """Return text with wraps replaced by the sentinel, plus an index map back."""
    chunks = []
    index_map = []
    pos = 0

    for wrap in WRAP_RE.finditer(text):
        chunks.append(text[pos:wrap.start()])
        index_map.extend(range(pos, wrap.start()))
        chunks.append(JOIN)
        index_map.append(wrap.start())
        pos = wrap.end()

    chunks.append(text[pos:])
    index_map.extend(range(pos, len(text)))
    return "".join(chunks), index_map


def mark(text, args, Mark, extra_cli_args, *a):
    """Mark whole nvim. references so the action gets the kind and its target."""
    unwrapped, index_map = _unwrap(text)

    for idx, match in enumerate(NVIM_REF_RE.finditer(unwrapped)):
        start = index_map[match.start()]
        end = index_map[match.end() - 1] + 1

        # Keep the highlight on a single screen line, and off the padding that
        # the wrap left behind. A wrapped reference is still opened whole; only
        # the visible mark stops at the line break.
        line_end = text.find("\n", start, end)
        if line_end != -1:
            end = start + len(text[start:line_end].rstrip())

        yield Mark(idx, start, end, match.group(0).replace(JOIN, ""), {})
