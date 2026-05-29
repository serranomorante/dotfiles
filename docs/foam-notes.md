# Foam Notes

In this workstation context, `foam` means the private personal notes workspace at:

```text
~/data/notes/foam
```

It is the user's PKM workspace. It stores personal notes, TODOs, Remind-backed reminders, operational notes, system error reports, and generated workstation health reports. It is private user content, not a public dotfiles package.

The dotfiles repository owns tooling around Foam, such as PKM scripts, Remind helpers, systemd units, sync helpers, and generated agent-context symlinks. The notes themselves live outside `~/dotfiles` and should only be inspected or edited when the user explicitly grants permission for that task.

When working in the Foam tree:

- Read `~/data/notes/foam/AGENTS.md` first.
- Follow the Foam workspace conventions for tags, wikilinks, reminders, and note filenames.
- Prefer unique file stems for notes that may be linked with wikilinks.
- Keep durable workstation setup behavior in `~/dotfiles`; use Foam for private planning, notes, runbooks, TODOs, and reports.

Neovim Markdown buffers add a local `@id` metadata convention for paragraph- or list-item-level anchors that should not become headings. An `@id` line must be directly attached to the preceding block, with no blank line between the block's contiguous metadata lines and the `@id`; detached IDs are ignored. `gd` delegates normal links to Marksman, but intercepts Markdown links and wikilinks whose fragment is a block target such as `[[note-stem#^decision-sync]]` or `[text](note.md#^decision-sync)` and jumps to a matching attached `@id decision-sync`. The Marksman diagnostics handler filters only the false-positive missing-heading diagnostics for those `#^id` fragments; normal broken-heading diagnostics remain visible. On save, Neovim warns about duplicate attached `@id` values within the current Markdown file.

Remind-backed TODOs may use `@run agent` inside an indented `remind` fence to run the attached `@id` through the local Codex agent at the scheduled reminder time. The generated Remind `RUN` command goes through the `remind-run` allowlist, resolves the TODO by id, writes the full result under `misc/agent-runs/YYYY-MM/`, logs through the `foam-remind-agent` journal tag, and sends a short completion notification.

Related dotfiles-owned documentation and tooling:

- `docs/foam-crypt-sync.md`
- `docs/system-health.md`
- `playbooks/roles/40-PKM/`
- `PKM/`
