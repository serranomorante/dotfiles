# System Health Workflow

`dotfiles-health` writes a compact Markdown report into the private Foam notes tree at `~/data/notes/foam/ops/system-health/system-health.md`.

The report is intentionally an index and runbook, not a raw log archive. It stores counts, current failed units, stable links to issue pages, and runnable `journalctl`/`systemctl` snippets so the editor can jump to related detail without filling the notes tree with large generated files.

The main report preserves the section between `dotfiles-health:manual-reminders:start` and `dotfiles-health:manual-reminders:end`. Put Markdown TODOs with indented `remind` fences there when the review cadence should create Remind notifications. Add indented `@id` metadata to reminders that should be linkable from other Foam notes with `[[system-health#^todo-id]]`.

Those `remind` blocks may use `@run dotfiles-health update` so the same reminder both notifies the user and queues a Markdown report refresh. Remind does not execute arbitrary note text directly: generated `RUN` lines call `~/bin/remind-run`, whose shell `case` statement is the allowlist for commands that notes are permitted to trigger. Valid allowlisted commands are queued as transient user systemd units so the normal reminder notification is not delayed by the helper.

Runtime files are grouped as:

```text
ops/system-health/
  system-health.md
  rules.md
  runbook.md
  units/
  spikes/
    system-spikes.md
    sources/
    reports/YYYY/system-spikes-YYYY-MM.md
  reports/YYYY/YYYY-MM.md
```

The user timer `dotfiles-health.timer` runs with low priority and updates the same current report plus a monthly digest. It avoids long unbounded journal queries by default; detailed investigation stays as executable snippets in the Markdown report. Journal-backed detectors read only the latest `DOTFILES_HEALTH_JOURNAL_LINES` service entries, default `1000`, and `DOTFILES_HEALTH_KERNEL_JOURNAL_LINES` kernel entries, default `5000`, so a noisy driver or service cannot make the hourly timer crawl a whole day of logs. Each `update` run caches those bounded journal snapshots in a temporary directory and reuses them for counts, source pages, and the monthly digest, then removes the cache on exit.

CPU spike reporting is split into an always-on sampler and a periodic Foam generator. `system-spike-watch.service` runs `system-spike-watch run` with low priority; `system-spike-watch` is a shell wrapper that compiles and `exec`s a cached Go binary from `utilities/dot-local/share/dotfiles/system-spike-watch/`. The sampler reads `/proc` once per second and only enters short burst capture when an interactive-path process crosses its type-specific threshold. Burst capture samples every 200 ms by default to keep monitor overhead bounded while still catching multi-second freezes. It stores compact JSONL events under `~/.local/state/dotfiles/system-spikes/events/`; it does not write Markdown or query journals while watching.

During burst capture only, the sampler may collect deeper context for known ambiguous scopes. When `DISPLAY` and `xdotool` are available, it records the active X11 window title, PID, unit, cwd, and command line so Xorg spikes can be tied back to the focused client when possible. `kitty-*` units are enriched with top process/cwd/cmdline evidence and, when the predictable Kitty socket is available, `kitten @ ls` foreground window context. Brave and Chromium browser scopes are enriched with renderer process evidence and local DevTools tab candidates; Chromium uses port `9222`, Brave uses port `9223`, and tabs can be marked as the probable active tab when their title matches the active X11 window. The watcher also reads fresh snapshots from the local `browser-task-snapshotd.service`, which receives `chrome.processes` Task Manager updates from the `Dotfiles Browser Task Sampler` extension and can rank tabs by browser-reported task CPU percentage when the browser exposes that API. If no fresh task snapshot is available, the watcher falls back to bounded Chrome DevTools Protocol probes that rank tabs by recent `TaskDuration`, `ScriptDuration`, layout/style work, focus, and visibility, then stores only the top probable candidates. Task-sampler CPU uses the browser's own single-core percentage scale; CDP score remains correlation evidence, not proven per-renderer PID causality. `docker-*.scope` units are enriched by extracting the container ID from the unit name and running a bounded `docker inspect` to record the container name, image, status, and Compose labels when Docker is reachable; concurrent Docker CPU during an interactive-path victim is reported as system pressure unless stronger causal evidence exists. Audio spikes are enriched with bounded `pw-top` and `pw-dump` snapshots so the report can list PipeWire nodes, sinks, sources, filters, node load evidence, and related application/client metadata; this node evidence is PipeWire graph/quantum context, not the same metric as Linux process CPU percentage.

`dotfiles-spikes.timer` runs `dotfiles-spikes update` hourly to turn those JSONL events into `ops/system-health/spikes/system-spikes.md`, source pages, a coverage note, and a monthly digest. `system-spike-notify.service` is a separate notification layer: it watches the JSONL event directory with `inotifywait` when available, runs `dotfiles-spikes update`, and only then sends clickable `notification-action` notifications for new Xorg events that open the `@id system-spikes-report` block in the refreshed Foam report. `system-spike-notify` is a matching shell wrapper that compiles and `exec`s a cached Go helper from `utilities/dot-local/share/dotfiles/system-spike-notify/`, with the runtime binary cached under `~/.cache/dotfiles/system-spike-notify/`. `dotfiles-health` only reads the current day's event count and links to `[[system-spikes]]`, so the main health report remains cheap.

Spike attribution is best-effort. The report should identify likely causes by comparing the victim process, top processes, systemd cgroups/units, command lines, focused-window evidence, and timing within the same capture burst. For example, an Xorg spike caused by a display health timer should appear as victim `Xorg` with the timer or its `xrandr` command as the likely suspect when both are visible in the burst window. `sddm.service` is treated as Xorg's host unit rather than a primary suspect unless a separate helper process provides evidence.
