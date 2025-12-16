from os import environ, path
from pathlib import Path
from typing import List

from my.core.common import PathIsh, Paths


# if the HPIDATA environment variable is set (which points to my data)
# use that. Else, just default to ~/data
PREFIX: Path = Path(environ.get("HPIDATA", path.expanduser("~/data/PKM/data")))


def data(p: PathIsh) -> Path:
    """prepend my data directory onto this path"""
    return PREFIX / p


live_dbs: List[Path] = []
try:
    from browserexport.browsers.brave import Brave

    live_dbs.append(Brave.locate_database())
except Exception:
    pass


class browser:
    """
    uses browserexport https://github.com/purarue/browserexport
    """

    class export:
        export_path: Paths = data("browsing")

    class active_browser:
        export_path: Paths = tuple(live_dbs)


class hypothesis:
    export_path: Paths = data("highlights/hypothesis.*.json")
