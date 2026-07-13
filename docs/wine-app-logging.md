# Wine App Logging

Wine desktop launchers should use `wwine` as the shared launcher and should keep normal desktop startup terminal-free.

## Wrapper Ownership

Do not create a second generic Wine launcher such as `wine-app-run`.

`~/bin/wwine` already owns managed Wine launching: prefix aliases, pinned Wine environment, standalone virtual desktop forcing, sandbox setup, and `wwine-wine-loader` compatibility. Launcher logging and log rotation should be an optional launcher-scoped feature of `wwine`, not a parallel wrapper that repeats those responsibilities.

If an app needs pre-launch work unrelated to Wine itself, such as connecting REAPER audio routing, keep a narrow app-specific launcher script for that setup. That script should still delegate the Wine process to `wwine`.

## Prefix Cleanup

Use `wwine --prefix <alias-or-path> kill-prefix` when Ansible handlers or maintenance commands need to close a Wine prefix after installers, registry changes, or stuck GUI sessions. The wrapper resolves the same prefix aliases and pinned Wine environment as normal launches, asks the matching `wineserver` to stop, then only escalates to Unix signals for remaining Wine-looking processes whose `WINEPREFIX` matches that prefix.

Do not use `ps | grep wine` fallbacks in handlers or tasks. Those are process-name scoped instead of prefix scoped and can kill unrelated Wine applications from other prefixes.

## Installer Tasks

Ansible tasks that run GUI Wine installers through `wine start /wait` must not treat the command return code as an install result. Wine and the Windows launcher can return noisy nonzero statuses after the installer has already completed, so these tasks should set `failed_when: false` and rely on `creates`, a follow-up `stat`/`assert`, a marker, or another concrete installed artifact to decide whether the installer still needs to run or whether the expected state exists.

## Wine Profiles

`wwine` defaults to the `legacy` Wine profile, which points at the portable Kron4ek Wine staging build declared by `arch_wine_staging_version`. Keep this as the default for existing prefixes unless a prefix explicitly needs a different runtime.

Per-prefix Wine selection is owned by `wwine_prefix_aliases` in `playbooks/roles/10-system-tools/defaults/main/music-production.vars.yml`. Add `wine_profile: <profile>` to an alias when every command for that prefix should use a non-default Wine environment.

Wine executable environments are owned by `wine_env_profiles` in `playbooks/roles/10-system-tools/defaults/main/main.vars.yml`. The `system` profile uses the pacman-managed `/usr/bin/wine` and `/usr/bin/wineserver`, while `legacy` uses the portable pinned build. `wine-staging` must not be listed in the desktop `IgnorePkg` block because the system profile is expected to track the current pacman package.

The `musicproduction` prefix is mapped to the `system` profile, so `wwine --prefix musicproduction ...` runs with the current pacman-managed Wine staging build. Existing aliases without a `wine_profile` continue to use `legacy`.

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

Do not make app launchers select, clear, or retry Wine virtual desktop mode. Use `wwine --prefix <alias-or-path> force-desktop [WxH]` as a separate manual or Ansible action when a prefix should be forced to Wine's virtual desktop registry setting.

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

When `--use-sandbox` is used with a raw prefix path instead of a configured alias, pass `--sandbox-profile` explicitly; `wwine` must preserve that profile across its Firejail re-exec so the inner process can validate the inherited sandbox.

Use `wwine --wine-debug <WINEDEBUG-spec>` for app-scoped verbose Wine logging. The wrapper should export that value as `WINEDEBUG`, preserve it across Firejail re-exec, and include it in `prepare-env` output so loader-style integrations can inherit the same verbosity without bypassing `wwine`.

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
