# Self-hosted hypothesis: search index and reindex

The self-hosted h app stores annotations in Postgres but serves searches from Elasticsearch. When the ES index is missing or has the wrong mapping, annotations are invisible in the UI (and newly created ones "disappear" on refresh) even though they exist in Postgres.

## How the index can break

- The h repo's `docker-compose.yml` gives Elasticsearch an anonymous volume, so `docker compose down` (or a compose change that recreates the container) wipes the index and its data.
- On the next write, Elasticsearch auto-creates a `hypothesis` index with dynamic mappings: fields such as `user_raw` and `group` become `text`+`.keyword` instead of `keyword`.
- h's search filters (`h/search/query.py`) run term queries on those fields, which return zero hits on analyzed `text` fields. The admin "reindex" pages and `h.tasks.indexer.sync_annotations` keep indexing into the broken index, so nothing shows.

The durable fix is a named `esdata` volume so the correctly-mapped index survives `docker compose down`. It is applied by the `hypothesis_h.patch` template (`playbooks/roles/40-PKM/templates/hypothesis_h.patch`), gated by the `h-setup` marker contract (`h-patches-v3`).

## Rebuild the index

`playbooks/hypothesis-reindex.yml` rebuilds the search index from Postgres using only h's own services (its job queue and `AnnotationSyncService`); it never touches Postgres directly. The helper is `playbooks/roles/40-PKM/files/hypothesis-reindex.py`.

It deletes and recreates the index only when the mapping is missing or incompatible, then queues every annotation with `force=True` and drains the queue, so a run is safe even when the index is healthy (e.g. after restoring a backup).

Apply the durable volume fix first, then rebuild:

```sh
cd ~/dotfiles/playbooks && ansible-playbook tools.yml --tags 40-PKM -l localhost 2>&1 | tee /tmp/ansible-hpi.log
cd ~/dotfiles/playbooks && ansible-playbook hypothesis-reindex.yml -l localhost 2>&1 | tee /tmp/ansible-h-reindex.log
```

The 40-PKM tag re-clones h (marker bump), re-applies the patches, and recreates the ES container with the new named volume; the reindex playbook then repopulates the index. To only inspect health without changing anything, run the helper directly in the h checkout:

```sh
cd ~/data/repos/h && PYTHONPATH=$PWD TOX_TESTENV_PASSENV=PYTHONPATH pyenv exec tox -qe dev -- python3 .tox/hypothesis-reindex.py --check
```

## Ownership

- Patch/volume fix: `playbooks/roles/40-PKM/templates/hypothesis_h.patch`, marker contract in `playbooks/roles/40-PKM/tasks/20-setup-HPI.archlinux.yml`.
- Reindex helper: `playbooks/roles/40-PKM/files/hypothesis-reindex.py`.
- Reindex playbook: `playbooks/hypothesis-reindex.yml`.
