# AUR Supply Chain Workflow

This workstation treats AUR updates as a separate trust decision from normal Arch repository upgrades. Do not use a plain `yay` run as the routine full-system update path, because `yay` defaults to `yay -Syu` and mixes official repository upgrades with AUR fetch, build, and install.

Normal daily upgrades should use `pacman -Syu` for official repositories and leave AUR updates for an explicit review batch. The review batch must inspect changed AUR Git commits before any build or install step runs.

The `aur-review` helper maintains local AUR Git checkouts under `~/data/aur-review` by default. In each checkout, local `master` is the last reviewed state and `origin/master` is the current AUR remote state. Review the diff `master..origin/master` with the normal Neovim, Diffview, or lazygit workflow, then run `aur-review accept <package>` only after the change is approved.

Useful review commands:

```sh
aur-review list-updates
aur-review status brave-bin
aur-review baseline-installed brave-bin
aur-review diff brave-bin
aur-review diffview brave-bin
aur-review lazygit brave-bin
aur-review accept brave-bin
```

Use `aur-review baseline-installed <package>` when adopting an already-installed AUR package into this workflow or when `aur-review diff <package>` is empty even though pacman/AUR reports an available update. That command moves the local reviewed baseline to the AUR commit whose `.SRCINFO` version matches the package version currently installed by pacman, so the next diff shows only the unreviewed update.

Use `aur-review list-updates` to build the review queue. It scans installed foreign packages plus installed packages published by `[aur-local]`, skips debug split packages, compares normal packages against the latest AUR `.SRCINFO`, and checks movable VCS Git sources for upstream commit movement. Git sources pinned to `#tag=` or `#commit=` are treated as normal AUR package sources rather than moving upstreams, so they only appear when the AUR package metadata changes. In an interactive terminal it prints an aligned, colorized table; use `aur-review list-updates --plain` when a tab-separated machine-readable stream is more useful. Lines beginning with `aur` need the normal AUR diff review; lines beginning with `vcs` need the upstream diff review; `unknown` means the helper could not infer the installed upstream commit from known VCS package version patterns such as `.g<hash>` or `.r<count>.<hash>`, and the package needs an explicit `--from <commit>` for deeper review. The `ACCEPTED` column means the local AUR checkout has no pending `master..origin/master` commits, so the packaging metadata has been accepted. The `PUBLISHED` column means `[aur-local]` already contains the target package version, or for movable VCS packages a package whose version embeds the target upstream commit, even when that package has not been installed yet.

For VCS packages such as `*-git`, the AUR `PKGBUILD` may not change even when upstream code has moved. Review the AUR diff first, then use `aur-review upstream-diff <package>` or `aur-review upstream-diffview <package>` to clone/fetch the upstream Git source declared in `.SRCINFO` under `~/data/aur-review-upstream` and compare the installed commit inferred from versions like `1.3.0.r6.g73ff5cf-1` against the target ref that the PKGBUILD will build. If the package has multiple Git sources, pass `--source <alias>`; for example, `aur-review upstream-diffview --source patchance patchance-git`. If the installed commit cannot be inferred, pass `--from <commit>` explicitly, and use `--to <ref>` when the default PKGBUILD target is not the ref you want to review.

After accepting a package, publish it to the local pacman repository with the same helper:

```sh
aur-review publish brave-bin
```

`aur-review publish` refuses to run when `origin/master` has unreviewed commits, verifies sources with `makepkg --verifysource`, builds with `makechrootpkg` in a clean chroot by default, copies the resulting `.pkg.tar*` files into `/var/cache/pacman/aur-local`, and updates the `[aur-local]` package database with `repo-add`. Clean-chroot builds can resolve already-published local AUR dependencies from `[aur-local]`, but those dependencies must be reviewed and published first; for example, publish `python-sabctools` before publishing `sabnzbd`.

Use `aur-review publish --nocheck <package>` only when the diff has been reviewed and the PKGBUILD `check()` failure is an environmental precondition of the clean chroot rather than a failed upstream test or integrity check. If the build also needs PHP extensions during `package()`, add `--php-extension <extension>` so the helper exports a temporary `PHP_INI_SCAN_DIR` for the build. For example, `phpactor` checks that PHP has the `iconv` extension enabled and Composer also requires `ext-iconv`, so publish it with `aur-review publish --nocheck --php-extension iconv phpactor`.

Ansible owns the local repository configuration through the `10-20` tag. Normal Ansible package tasks must not build AUR packages or call AUR helpers; they install official packages with pacman and install approved AUR packages from `[aur-local]` with `community.general.pacman`. If an AUR package has not been reviewed and published yet, Ansible reports it as skipped and continues instead of fetching from AUR, building during the run, or failing the whole playbook.

The daily workflow is:

```sh
sudo pacman -Syu
aur-review list-updates
aur-review diffview sabnzbd
aur-review accept sabnzbd
aur-review publish sabnzbd
aur-review diffview patchance-git
aur-review upstream-diffview patchance-git
aur-review accept patchance-git
aur-review publish patchance-git
cd ~/dotfiles/playbooks
ansible-playbook -K tools.yml -l localhost --tags 10-20,10-170 2>&1 | tee /tmp/ansible-10-20_10-170.log
```

Use the narrowest relevant Ansible tags for the package group being reconciled, but include `10-20` whenever local AUR packages are involved so `[aur-local]`, `devtools`, and the repo directories exist before package installation.
