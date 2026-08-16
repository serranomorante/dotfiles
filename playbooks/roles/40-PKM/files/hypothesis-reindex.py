#!/usr/bin/env python3
"""Purpose: Rebuild the self-hosted h search index from Postgres using only h's native services.

Run from the h checkout root (e.g. via `tox -qe dev -- python3 .tox/hypothesis-reindex.py`)
with the h dev environment variables set. It:

1. Ensures the Elasticsearch index matches this h version's mapping, recreating it
   when it is missing, mis-mapped, or not created by `init_elasticsearch` (the
   auto-created-dynamically symptom). Recreating never touches Postgres.
2. Queues every annotation for a forced re-sync on h's own `sync_annotation` job
   queue (the same queue the admin "reindex" actions and h-periodic use).
3. Drains the queue with h's AnnotationSyncService so each annotation is
   (re)indexed from Postgres.

No direct Postgres or Elasticsearch shell access is used.

--check only inspects the index and reports what would change without modifying
anything; it is safe to run against a live instance.
"""

import argparse
import datetime
import sys

from pyramid.paster import bootstrap

from h.search import config as search_config
from h.services import AnnotationSyncService

QUEUE_NAME = "sync_annotation"
QUEUE_LIMIT = 100_000
MAX_SYNC_PASSES = 10


def _mapping_signature(properties):
    """Return the search-relevant shape of a mapping for comparison.

    ES normalizes mappings on storage (adds the implicit ``type: object`` to
    object fields, expands ``copy_to`` strings to lists), so exact equality with
    ``ANNOTATION_MAPPING`` never holds. Compare only what h's queries rely on:
    field ``type`` (except the implicit object), ``analyzer``, and nesting.
    """
    sig = {}
    for key, prop in properties.items():
        item = {}
        prop_type = prop.get("type")
        if prop_type and prop_type != "object":
            item["type"] = prop_type
        if "analyzer" in prop:
            item["analyzer"] = prop["analyzer"]
        if "properties" in prop:
            item["properties"] = _mapping_signature(prop["properties"])
        sig[key] = item
    return sig


def _index_needs_recreate(client, expected_mapping, expected_settings):
    """Return True when the search index is missing or incompatible with h."""
    if not client.conn.indices.exists(index=client.index):
        return True

    concrete = search_config.get_aliased_index(client)
    # A healthy index is an alias pointing at a differently-named concrete index
    # created by init_elasticsearch(); a bare "hypothesis" index with no alias is
    # the dynamically auto-created one.
    if concrete is None or concrete == client.index:
        return True

    actual_mapping = client.conn.indices.get_mapping(index=client.index)
    mappings = actual_mapping.get(concrete, {}).get("mappings", {})
    if str(mappings.get("dynamic", True)).lower() != "false":
        return True
    if _mapping_signature(mappings.get("properties", {})) != _mapping_signature(
        expected_mapping["properties"]
    ):
        return True

    actual_settings = client.conn.indices.get_settings(index=client.index)
    if (
        actual_settings.get(concrete, {})
        .get("settings", {})
        .get("index", {})
        .get("analysis", {})
        != expected_settings
    ):
        return True

    return False


def _ensure_index(client, settings):
    if not _index_needs_recreate(
        client, search_config.ANNOTATION_MAPPING, search_config.ANALYSIS_SETTINGS
    ):
        print("Search index is healthy", flush=True)
        return

    concrete = search_config.get_aliased_index(client)
    if concrete is not None:
        print(f"Deleting incompatible index {concrete}", flush=True)
        search_config.delete_index(client, concrete)

    search_config.init(
        client, check_icu_plugin=settings.get("es.check_icu_plugin", True)
    )
    print("Created search index with the current mapping", flush=True)


def main():
    parser = argparse.ArgumentParser(description="Rebuild the h search index")
    parser.add_argument(
        "--check",
        action="store_true",
        help="report index health without changing anything",
    )
    args = parser.parse_args()

    env = bootstrap("conf/development.ini")
    request = env["request"]

    needs_recreate = _index_needs_recreate(
        request.es, search_config.ANNOTATION_MAPPING, search_config.ANALYSIS_SETTINGS
    )
    if args.check:
        print("Index healthy" if not needs_recreate else "Index needs recreation")
        return 1 if needs_recreate else 0

    _ensure_index(request.es, env["registry"].settings)

    queue_service = request.find_service(name="queue_service")
    start = datetime.datetime(1970, 1, 1, tzinfo=datetime.timezone.utc)
    end = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1)
    queue_service.add_between_times(
        QUEUE_NAME, start, end, tag="reindex_all", force=True
    )
    request.tm.commit()
    print("Queued all annotations for a forced re-sync", flush=True)

    sync_service = request.find_service(AnnotationSyncService)
    for pass_no in range(1, MAX_SYNC_PASSES + 1):
        counts = sync_service.sync(QUEUE_LIMIT)
        request.tm.commit()
        print(f"sync pass {pass_no}: {counts}", flush=True)
        if not counts:
            print("Search index is now in sync", flush=True)
            return 0

    print(
        f"WARNING: job queue did not drain after {MAX_SYNC_PASSES} passes",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
