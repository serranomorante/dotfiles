from promnesia.common import Source, DbVisit, get_logger
from promnesia.sources import auto, browser
from promnesia.sources import hypothesis

"""
List of sources to use.

You can specify your own, add more sources, etc.
See https://github.com/karlicoss/promnesia#setup for more information
"""
SOURCES = [
    browser,
    Source(hypothesis.index),
    Source(
        auto.index,
        "~/external/notes/foam",
        ignored=[
            "*.html",
            "*.yaml",
            "*.yml",
            "*.out",
            "*.jira",
            "*.bib",
            "*.lock",
            "*.scss",
            "*/tags",
            "*/mermaid-filter.err",
            "*/Gemfile",
            "*/assets/*",
        ],
        name="notes",
    ),
]

# https://github.com/karlicoss/promnesia/blob/master/doc/config.py
FILTERS = [
    "developer.wikimedia.org"  # exclude my own default new tab page
]


# https://github.com/karlicoss/promnesia/blob/master/doc/config.py
def HOOK(v: DbVisit):
    logger = get_logger()

    logger.info("{}".format(v))

    if hasattr(v, "orig_url") and "developer.wikimedia.org" in v.orig_url:
        logger.info("Match! {}".format(v.orig_url))
        return
    yield v
