# Containing App Resource Spikes

Notes on how to hard-contain resource-heavy desktop apps (Brave, Chromium, and similar) so their CPU/memory spikes stop hurting the rest of the desktop session. This is reference material, not an agent convention; it does not need to be linked from `AGENTS.md`.

## Why soft caps are not enough

The existing browser caps in `app-resources.vars.yml` use `CPUQuota`, `CPUWeight`, `Nice`, and `MemoryHigh`/`MemoryMax` applied through transient user scopes created by `app-cgroup-launch`. Spike history (`ops/system-health/spikes` in the Foam notes) shows capped `browser-chromium-*` scopes still burst far above their quota (e.g. up to ~900% with a `CPUQuota=250%`), so those limits are not acting as a hard ceiling.

Reasons a `CPUQuota` on a user scope can fail to contain spikes:

- `CPUQuota` on the cgroup v2 unified hierarchy maps to `cpu.max`, which is a *bandwidth* limit averaged over a period (default 100 ms). Within one period the unit can still light up many cores, so fine-grained samplers see bursts well above the average cap.
- For a non-root user, the `cpu` and `cpuset` controllers must be *delegated* to the user manager, otherwise systemd silently drops `CPUQuota`/`AllowedCPUs` on user scopes and slices.
- Processes already running before the cap was applied (or launched outside the scope) do not inherit it; Chromium-family browsers also keep long-lived helper processes.

## Recommended method on Arch Linux

Use the systemd resource-control knobs that the kernel enforces as hard ceilings, combined in a dedicated user slice:

- `AllowedCPUs=` (cpuset controller): pins the app to a fixed set of physical cores. The scheduler simply cannot run the unit outside those cores, so it is the only mechanism that makes over-utilization *impossible* rather than throttled. This is the key knob for hard CPU containment.
- `CPUQuota=` (cpu controller): still useful on top of `AllowedCPUs` to also cap the average CPU time, keeping the app slow even within its pinned cores.
- `MemoryHigh=` + `MemoryMax=`: `MemoryMax` is the hard memory rail (OOM-kill inside the unit); `MemoryHigh` throttles/reclaims first. Memory spikes hurt the desktop via swap thrash, so these matter as much as CPU limits.
- `TasksMax=`: bounds the number of threads/processes the unit may spawn, preventing runaway tab/spawn storms.
- `IOWeight=` / `IOWriteBandwidthMax=`: keeps the app from saturating disk I/O.

Enable `systemd-oomd` as a system-wide safety net: when memory pressure rises, it kills the largest consumer instead of letting the whole session thrash.

Optionally add `ananicy-cpp` (or similar) for automatic niceness, and give Xorg/the compositor a higher `CPUWeight` so interactive work still wins while a capped app burns its budget.

## Delegation check

Before trusting user-level CPU/cpuset limits, confirm the controllers are delegated and visible:

```sh
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/cgroup.controllers
systemctl cat user@$(id -u).service | rg -i delegate
```

If `cpu` and `cpuset` are missing, add a system drop-in (requires root) and reboot:

```ini
# /etc/systemd/system/user@$(id -u).service.d/delegate.conf
[Service]
Delegate=cpu cpuset io
```

## Example slice

```ini
# ~/.config/systemd/user/app-browser.slice
[Unit]
Description=Hard budget for resource-heavy browser sessions

[Slice]
CPUAccounting=yes
MemoryAccounting=yes
IOAccounting=yes
AllowedCPUs=0-3
CPUQuota=200%
CPUWeight=10
IOWeight=10
MemoryHigh=6G
MemoryMax=8G
TasksMax=4096
```

Launch the app inside the slice rather than in a bare scope:

```sh
systemd-run --user --slice=app-browser.slice --scope <launcher>
```

## Verification

After applying a cap, check what is actually enforced and restart the app from the capped launcher so all processes land in the scope/slice:

```sh
systemctl --user cat 'browser-*.scope' | rg -i 'CPUQuota|AllowedCPUs'
systemd-cgtop --batch --iterations=1 --raw --cpu=percentage
cat /sys/fs/cgroup/user.slice/user-$(id -u).slice/.../browser-*/cpu.max 2>/dev/null
systemctl status systemd-oomd
```
