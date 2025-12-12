from promnesia.common import Source
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
            "*.err",
            "*/tags",
            "*/Gemfile",
            "*/assets/*",
        ],
        name="notes",
    ),
]
