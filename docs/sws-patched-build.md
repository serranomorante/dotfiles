# SWS (native Linux) patched build

The native Linux REAPER SWS extension is built from source with repo-owned
patches instead of the distro `sws` package, so we can change SWS behavior and
keep those changes under version control. The distro package is removed and the
patched build is installed into REAPER's native resource path.

## Ownership

- Patches: `assets/patches/sws/*.patch`
- Build tasks: `playbooks/roles/10-system-tools/tasks/wine-tools/sws-patched-linux.task.yml`
- Pin/config: `arch_sws_patched_setup` in `playbooks/roles/10-system-tools/defaults/main/music-production.vars.yml`

Built artifacts land in `~/.config/REAPER/UserPlugins/reaper_sws-x86_64.so` and
`~/.config/REAPER/Scripts/sws_python64.py`. Restart REAPER to load a rebuilt
extension.

## Build gating

The build is idempotent via a dotfiles marker keyed on `version` plus
`patch_set_version`:

- Bump `version` to track a new upstream SWS release (re-clone, re-patch, rebuild, reinstall).
- Bump `patch_set_version` after adding or editing a patch (same flow against the current source).
- Otherwise the playbook leaves the installed extension untouched.

Patch application has no fallback: if a patch no longer applies against the new
source, the playbook fails at the patch step so the patch can be refreshed.
Never add `ignore_errors` to the patch step.

## Adding or updating a patch

1. Check out upstream at the pinned tag (matches `arch_sws_patched_setup.version`):
   ```
   git clone --depth 1 --branch v2.14.0.7 https://github.com/reaper-oss/sws /tmp/sws
   ```
2. Make the change, then generate a plain unified diff (the repo's git pager is
   `delta`/external, so bypass it):
   ```
   cd /tmp/sws && GIT_PAGER=cat git diff --no-ext-diff --no-color -- <changed files> > notes-<name>.patch
   ```
3. Save it as `assets/patches/sws/<descriptive-name>.patch` and append the name
   to `patches:` in `arch_sws_patched_setup`.
4. Bump `patch_set_version` (v1 -> v2).
5. Apply with tag `10-120` and restart REAPER.

## Bumping SWS

`arch_sws_patched_setup.version` is tracked by Renovate (`github-tags` on
`reaper-oss/sws`), so a new upstream release is proposed automatically through
`dotfiles-renovate-apply`. After accepting the version bump and applying, if a
patch conflicts, regenerate it against the new tag and bump `patch_set_version`.

## Build notes

- The build pins `CMAKE_CXX_STANDARD=17`. SWS only declares `cxx_std_11` (a
  minimum), so GCC 16 defaults to C++20, where a struct with a deleted copy
  constructor is no longer an aggregate (P1008) and `BR_ContextualToolbars.cpp`
  stops compiling. Keep the pin unless a future SWS release raises its own
  standard requirement.
- Only `vendor/WDL` and `vendor/reaper-sdk` submodules are initialized;
  `vendor/taglib` is skipped because the build links system taglib.

## Current patches

- `notes-alt-shift-shortcuts-while-editing.patch` — lets Alt+Shift keymap chords
  (e.g. Shift+Alt+F bound to `SWS/S&M: Open/close Notes window`) reach REAPER's
  main window even while the Notes editor has focus, so the Notes window can be
  toggled without locking it first. See `NotesWnd::OnKey` in `SnM/SnM_Notes.cpp`.
