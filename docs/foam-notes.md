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

Related dotfiles-owned documentation and tooling:

- `docs/foam-crypt-sync.md`
- `docs/system-health.md`
- `playbooks/roles/40-PKM/`
- `PKM/`
