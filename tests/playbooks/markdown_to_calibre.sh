#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: playbooks
# dotfiles-test-tags: playbooks calibre markdown shell fast
# dotfiles-test-case: markdown-to-calibre-converts-and-adds
# dotfiles-test-case: markdown-to-calibre-updates-existing-book
# dotfiles-test-case: markdown-to-calibre-honors-tag-override
# dotfiles-test-case: markdown-to-calibre-honors-server-override
# dotfiles-test-case: markdown-to-calibre-falls-back-to-content-server
# dotfiles-test-case: markdown-to-calibre-rejects-non-markdown
# dotfiles-test-case: markdown-to-calibre-errors-on-missing-file
# dotfiles-test-case: markdown-to-calibre-errors-on-missing-argument
# dotfiles-test-case: markdown-to-calibre-propagates-conversion-failure
# dotfiles-test-case: markdown-to-calibre-propagates-calibredb-failure

# Purpose: Hermetic tests for the private `markdown-to-calibre` wrapper. Fake
#   `pandoc`, `ebook-convert`, and `calibredb` binaries in PATH log their
#   invocations so the real tools and the active Calibre library are never
#   touched; the pdf is asserted from the calibredb log.

wrapper="$DOTFILES_TEST_ROOT/for-my-eyes-only/bin/markdown-to-calibre"

make_fixture() {
    fixture="${DOTFILES_TEST_TMP}/fixture"
    fakebin="${fixture}/fakebin"
    pandoclog="${fixture}/pandoc.log"
    ebooklog="${fixture}/ebook-convert.log"
    calibreblog="${fixture}/calibredb.log"

    rm -rf "$fixture"
    mkdir -p "$fakebin"

    cat >"${fakebin}/pandoc" <<'SH'
#!/usr/bin/env sh
log="${MD2C_PANDOC_LOG}"
printf 'PANDOC %s\n' "$*" >>"$log"
out=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
        out="$2"
        shift 2
    else
        shift
    fi
done
printf '<html><head><title>stub</title></head><body>stub</body></html>\n' >"$out"
SH

    cat >"${fakebin}/ebook-convert" <<'SH'
#!/usr/bin/env sh
log="${MD2C_EBOOK_LOG}"
printf 'EBOOK %s\n' "$*" >>"$log"
if [ "${MD2C_EBOOK_FAIL:-0}" = 1 ]; then
    printf 'conversion failed\n' >&2
    exit 1
fi
printf '%%PDF-1.4 stub\n' >"$2"
SH

    cat >"${fakebin}/calibredb" <<'SH'
#!/usr/bin/env sh
log="${MD2C_CALIBREDB_LOG}"
printf 'CALIBREDB %s\n' "$*" >>"$log"
marker="${MD2C_CALIBREDB_FAIL_MARKER:-}"
if [ -n "$marker" ] && [ -f "$marker" ]; then
    rm -f "$marker"
    printf 'Another calibre program such as calibre-server or the main calibre program is running.\n' >&2
    exit 1
fi
if [ "${MD2C_CALIBREDB_FAIL:-0}" = 1 ]; then
    printf 'no library found\n' >&2
    exit 1
fi
if [ "${MD2C_CALIBREDB_MERGED:-0}" = 1 ]; then
    printf 'Merged book ids: 7\n'
    exit 0
fi
printf 'Added book ids: 7\n'
SH

    chmod +x "${fakebin}/pandoc" "${fakebin}/ebook-convert" "${fakebin}/calibredb"
}

run_markdown_to_calibre() {
    PATH="${fixture}/fakebin:/usr/bin:/bin" \
        MD2C_PANDOC_LOG="$pandoclog" \
        MD2C_EBOOK_LOG="$ebooklog" \
        MD2C_CALIBREDB_LOG="$calibreblog" \
        MD2C_CALIBREDB_FAIL_MARKER="${fixture}/fail-once" \
        "$wrapper" "$@"
}

slugify() {
    local data="$1"
    LC_ALL=C
    data="$(printf '%s' "$data" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
    printf '%s' "$data"
}

case "${DOTFILES_TEST_CASE:-}" in
markdown-to-calibre-converts-and-adds)
    make_fixture
    mkdir -p "${fixture}/notes"
    printf '# Hello\n\nSome *markdown*.\n' >"${fixture}/notes/My Note.md"

    out="$(run_markdown_to_calibre "${fixture}/notes/My Note.md")"

    title="$(slugify "${fixture#${HOME}/}/notes/My Note.md")"
    grep -Fq "PANDOC -f gfm -t html5 -s --metadata title=$title" "$pandoclog"
    grep -Fq 'EBOOK ' "$ebooklog"
    grep -Fq 'CALIBREDB add --automerge overwrite --tags from-markdown ' "$calibreblog"
    grep -Fq "${title}.pdf" "$calibreblog"
    grep -Fq 'Added book ids: 7' <<<"$out"
    refute grep -q '\.html' <<<"$calibreblog"
    ;;
markdown-to-calibre-updates-existing-book)
    make_fixture
    printf '# Hello\n' >"${fixture}/note.md"

    out="$(MD2C_CALIBREDB_MERGED=1 run_markdown_to_calibre "${fixture}/note.md")"

    grep -Fq 'Updated ' <<<"$out"
    grep -Fq 'Merged book ids: 7' <<<"$out"
    refute grep -q 'Added book ids' <<<"$out"
    ;;
markdown-to-calibre-honors-tag-override)
    make_fixture
    printf '# Hello\n' >"${fixture}/note.md"

    out="$(MARKDOWN_TO_CALIBRE_TAG=notes run_markdown_to_calibre "${fixture}/note.md")"

    grep -Fq 'CALIBREDB add --automerge overwrite --tags notes ' "$calibreblog"
    grep -Fq 'Added book ids: 7' <<<"$out"
    ;;
markdown-to-calibre-honors-server-override)
    make_fixture
    printf '# Hello\n' >"${fixture}/note.md"

    out="$(MARKDOWN_TO_CALIBRE_SERVER=http://127.0.0.1:9999 run_markdown_to_calibre "${fixture}/note.md")"

    grep -Fq 'Added book ids: 7' <<<"$out"
    grep -Fq 'CALIBREDB --with-library http://127.0.0.1:9999 add --automerge overwrite --tags from-markdown ' "$calibreblog"
    refute grep -q '^CALIBREDB add --automerge' "$calibreblog"
    ;;
markdown-to-calibre-falls-back-to-content-server)
    make_fixture
    printf '# Hello\n' >"${fixture}/note.md"
    : >"${fixture}/fail-once"

    out="$(run_markdown_to_calibre "${fixture}/note.md")"

    grep -Fq 'Added book ids: 7' <<<"$out"
    grep -Fq 'CALIBREDB add --automerge overwrite --tags from-markdown ' "$calibreblog"
    grep -Fq 'CALIBREDB --with-library http://127.0.0.1:8080 add --automerge overwrite --tags from-markdown ' "$calibreblog"
    ;;
markdown-to-calibre-rejects-non-markdown)
    make_fixture
    printf 'plain text\n' >"${fixture}/notes.txt"

    if run_markdown_to_calibre "${fixture}/notes.txt" >"${fixture}/out" 2>&1; then
        printf 'expected a non-markdown file to fail\n' >&2
        exit 1
    fi
    grep -Fq 'only markdown files' "${fixture}/out"
    ;;
markdown-to-calibre-errors-on-missing-file)
    make_fixture

    if run_markdown_to_calibre "${fixture}/does-not-exist.md" >"${fixture}/out" 2>&1; then
        printf 'expected a missing file to fail\n' >&2
        exit 1
    fi
    grep -Fq 'no such file' "${fixture}/out"
    ;;
markdown-to-calibre-errors-on-missing-argument)
    make_fixture

    if run_markdown_to_calibre >"${fixture}/out" 2>&1; then
        printf 'expected a missing argument to fail\n' >&2
        exit 1
    fi
    grep -Fq 'Usage: markdown-to-calibre <path>' "${fixture}/out"
    ;;
markdown-to-calibre-propagates-conversion-failure)
    make_fixture
    printf '# Hello\n' >"${fixture}/note.md"

    if MD2C_EBOOK_FAIL=1 run_markdown_to_calibre "${fixture}/note.md" >"${fixture}/out" 2>&1; then
        printf 'expected the conversion failure to propagate\n' >&2
        exit 1
    fi
    grep -Fq 'HTML to PDF conversion failed' "${fixture}/out"
    grep -Fq 'conversion failed' "${fixture}/out"
    ;;
markdown-to-calibre-propagates-calibredb-failure)
    make_fixture
    printf '# Hello\n' >"${fixture}/note.md"

    if MD2C_CALIBREDB_FAIL=1 run_markdown_to_calibre "${fixture}/note.md" >"${fixture}/out" 2>&1; then
        printf 'expected the calibredb failure to propagate\n' >&2
        exit 1
    fi
    grep -Fq 'calibredb add failed' "${fixture}/out"
    grep -Fq 'no library found' "${fixture}/out"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
