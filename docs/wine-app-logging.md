# Wine App Logging

Wine desktop launchers should use `wwine` as the shared launcher and should keep normal desktop startup terminal-free.

## Wrapper Ownership

Do not create a second generic Wine launcher such as `wine-app-run`.

`~/bin/wwine` already owns managed Wine launching: prefix aliases, pinned Wine environment, virtual desktop behavior, sandbox setup, and `wwine-wine-loader` compatibility. Launcher logging and log rotation should be an optional launcher-scoped feature of `wwine`, not a parallel wrapper that repeats those responsibilities.

If an app needs pre-launch work unrelated to Wine itself, such as connecting REAPER audio routing, keep a narrow app-specific launcher script for that setup. That script should still delegate the Wine process to `wwine`.

## Desktop Entries

Desktop files for normal Wine app launchers must use `Terminal=false` and must not launch `kitty`.

Use `wwine` with a stable log id when the desktop entry can launch the app directly:

```ini
Exec=wwine --prefix reaper --use-sandbox --log-id reaper wine "C:/Program Files/REAPER (x64)/REAPER.exe"
Terminal=false
Type=Application
```

When an app-specific launcher is still needed, keep the `.desktop` pointed at that launcher and make the launcher call `wwine --log-id <app-id>`:

```ini
Exec=/home/aaaa/.local/bin/launch-reaper-wine
Terminal=false
Type=Application
```

Do not keep a separate live-terminal debug launcher by default. If temporary live debugging is needed, run the launcher or the underlying `wwine` command manually from a terminal instead of making the regular desktop launcher open a terminal.

## App Ids

App ids are lowercase kebab-case identifiers passed through `wwine --log-id <app-id>`.

Use short stable names such as `vienna`, `reaper`, or `plugin-host`, and keep the id consistent across desktop files, wrapper configuration, log paths, and logrotate rules.

## Log Paths

Write stdout and stderr for each app to a per-app log under `~/.local/state/wine-apps/`.

Use this path pattern:

```text
~/.local/state/wine-apps/<app-id>/<app-id>.log
```

Examples:

```text
~/.local/state/wine-apps/vienna/vienna.log
~/.local/state/wine-apps/reaper/reaper.log
```

When `--log-id <app-id>` is used, `wwine` should create the state directory before launch and append stdout and stderr to the current log file.

## Rotation

Run log rotation before launching the app so the desktop entry never needs a terminal and logs cannot grow forever.

Use per-user logrotate state and configuration, not system-wide root-owned logrotate state.

Preferred state path:

```text
~/.local/state/wine-apps/logrotate.status
```

Preferred active config path:

```text
~/.config/logrotate/wine-apps.conf
```

The logrotate policy should rotate by size, keep a small number of old logs, compress rotated logs, tolerate missing logs, and skip empty logs.

Recommended baseline:

```text
~/.local/state/wine-apps/*/*.log {
    size 20M
    rotate 5
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
```

Use `copytruncate` because GUI Wine apps can keep stdout and stderr open for the lifetime of the process; renaming the log alone may not move future writes into the new file.

For sandboxed launches, the outer `wwine` invocation should set up rotation and redirection before Firejail re-exec so Firejail startup messages and the Wine process both land in the same app log.

## Viewing Logs

Viewing logs is a separate action from launching the app.

For quick inspection, read the log file directly or use `tail` manually:

```sh
tail -n 200 -f ~/.local/state/wine-apps/vienna/vienna.log
```

Do not make normal launchers open `kitty` just to expose logs. A terminal may be used manually when investigating a problem, but normal desktop startup should remain terminal-free.

## Source Ownership

Implement the wrapper behavior in `playbooks/roles/10-system-tools/templates/wwine`.

Implement the logrotate config through `playbooks/roles/10-system-tools/templates/wine-apps.logrotate`, installed by the Wine tools task as `~/.config/logrotate/wine-apps.conf`.

Implement normal Wine desktop launchers through the owning Ansible templates and tasks, such as `playbooks/roles/10-system-tools/templates/launch-reaper-wine` and `playbooks/roles/10-system-tools/templates/reaper.desktop`.

Do not patch installed active-system files directly under `~/.local/bin`, `~/bin`, `~/.local/share/applications`, or `~/.config/logrotate`; update the dotfiles source and apply it through Stow or Ansible when active-system application is requested.
