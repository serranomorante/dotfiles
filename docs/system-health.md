# System Health Workflow

`dotfiles-health` writes a compact Markdown report into the private Foam notes tree at `~/data/notes/foam/ops/system-health/system-health.md`.

The report is intentionally an index and runbook, not a raw log archive. It stores counts, current failed units, stable links to issue pages, and runnable `journalctl`/`systemctl` snippets so the editor can jump to related detail without filling the notes tree with large generated files.

The main report preserves the section between `dotfiles-health:manual-reminders:start` and `dotfiles-health:manual-reminders:end`. Put Markdown TODOs with indented `remind` fences there when the review cadence should create Remind notifications. Add indented `@id` metadata to reminders that should be linkable from other Foam notes with `[[system-health#^todo-id]]`.

Those `remind` blocks may use `@run dotfiles-health update` so the same reminder both notifies the user and refreshes the Markdown report. Remind does not execute arbitrary note text directly: generated `RUN` lines call `~/bin/remind-run`, whose shell `case` statement is the allowlist for commands that notes are permitted to trigger.

Runtime files are grouped as:

```text
ops/system-health/
  system-health.md
  rules.md
  runbook.md
  units/
  reports/YYYY/YYYY-MM.md
```

The user timer `dotfiles-health.timer` runs with low priority and updates the same current report plus a monthly digest. It avoids long unbounded journal queries by default; detailed investigation stays as executable snippets in the Markdown report.
