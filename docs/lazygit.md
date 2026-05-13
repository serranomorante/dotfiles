# Lazygit Setup

This repository keeps lazygit configuration in the `lazygit/` Stow package and
the related Git defaults in `home/dot-gitconfig`.

## Diff Pagers

The lazygit config uses `git.pagers` rather than the older single
`git.paging` field. Lazygit can cycle configured pagers with its native `|`
binding.

Current pager roles:

- Delta is selected through `useExternalDiffGitConfig: true`, which makes
  lazygit use Git's `diff.external` config.
- Difftastic is selected through `externalDiffCommand: difft --color=always`.

The `difftastic` and `git-delta` packages are declared in:

```text
playbooks/roles/20-dev-tools/tasks/90-setup-git-tools.archlinux.yml
```

## Lazygit Focus And Editor Handoff

Lazygit is launched through Kitty's quick-access-terminal kitten. The panel
settings live in `term/dot-config/kitty/quick-access-terminal.conf`. Every
toggle goes through the shared `term/bin/kitty-lazygit-quick-access` wrapper,
which invokes the kitten with
`--instance-group="$KITTY_OS_INSTANCE_ID"` so each Kitty OS window owns an
independent panel.

The bindings wired around lazygit:

- `kitty_mod+s` in Kitty is the single toggle for the lazygit quick-access
  panel. It runs the wrapper via `launch --type=background`. Neovim
  intentionally has no keymap for this — the binding lives only in Kitty.
- `q` inside lazygit fires a custom command that re-runs the wrapper, letting
  the kitten hide the panel. Lazygit's universal `quit` is `<disabled>` so the
  custom binding owns `q`.
- Lazygit editor callbacks (`lazygit_edit`, `lazygit_open`, etc.) send remote
  edit requests to the target Neovim through nvr. Neovim's remote-edit autocmd
  focuses its own Kitty window after the buffer is displayed, and
  quick-access-terminal's `hide_on_focus_loss yes` hides the lazygit panel when
  focus leaves it.

See [nvim-kitty-integration.md](./nvim-kitty-integration.md) for the
per-window Neovim server socket, Kitty window matching, and helper internals
that the lazygit handoff builds on.

## Delta External Diff Adapter

Do not point `diff.external` directly at `delta`.

Delta is normally configured as a pager: it expects unified diff text on stdin,
as with `git diff | delta`. Git's `diff.external` contract is different: Git
calls the configured command once per path and passes the repository path,
temporary old/new blob files, object hashes, and modes as arguments.

The adapter script lives at:

```text
lazygit/dot-config/lazygit/delta-theme-external-diff
```

It accepts Git's external-diff arguments, regenerates a plain patch with
`git diff --no-index --no-ext-diff`, rewrites temporary paths back to the
selected repository path, and then pipes the patch into:

```text
lazygit/dot-config/lazygit/delta-theme-pager
```

The `--no-ext-diff` flag is important because the adapter is itself invoked by
`diff.external`; omitting it would risk recursive external-diff calls.

Keep the adapter's shell control flow simple. Lazygit may abandon an in-flight
external diff when the selected file or pager changes, so avoid `EXIT` cleanup
traps and long-lived temporary patch files in this script. Prefer streaming
`git diff` through the path rewrite and pager, and keep the internal `git diff`
invocation isolated from `diff.external` and `GIT_EXTERNAL_DIFF`.

Rewrite temporary and working-tree paths to the repository path only, without
adding `a/` or `b/` labels. The internal `git diff --no-index` output already
adds diff-side prefixes where they belong; adding them in the replacement makes
delta treat `b/<path>` as the real file path for hyperlinks.

## Validation

For lazygit config changes, use the smallest checks that match the edit:

```sh
ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0)); puts "ok"' lazygit/dot-config/lazygit/config.yml
bash -n lazygit/dot-config/lazygit/delta-theme-external-diff
```

For pager behavior, test with a temporary repository and exercise modified,
added, and deleted files. Avoid running lazygit interactively as a validation
requirement unless the change specifically needs UI confirmation.
