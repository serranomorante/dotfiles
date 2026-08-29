#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities aur shell
# dotfiles-test-case: aur-review-publish-keeps-review-checkout-clean
# dotfiles-test-case: aur-review-accept-restores-generated-pkgver-change
# dotfiles-test-case: aur-review-accept-rejects-non-pkgver-change
# dotfiles-test-case: aur-review-publish-applies-repo-patch
# dotfiles-test-case: aur-review-publish-fails-on-stale-patch

# Purpose: Verify aur-review builds packages outside the reviewed AUR checkout.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/aur-review"

write_fake_tools() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/makepkg" <<'SH'
#!/usr/bin/env sh
set -eu

printf '%s\n' "$PWD" >>"${DOTFILES_TEST_TMP}/makepkg.cwd"
cp PKGBUILD "${DOTFILES_TEST_TMP}/makepkg.PKGBUILD"
sed -i 's/^pkgver=.*/pkgver=mutated.by.fake.makepkg/' PKGBUILD
case " $* " in
*" --verifysource "*)
    exit 0
    ;;
esac
mkdir -p "$PKGDEST"
: >"$PKGDEST/fake-git-1-1-any.pkg.tar.zst"
SH
    chmod +x "${bin}/makepkg"
    cat >"${bin}/repo-add" <<'SH'
#!/usr/bin/env sh
set -eu

: >"$1"
shift
printf '%s\n' "$@" >>"${DOTFILES_TEST_TMP}/repo-add.packages"
SH
    chmod +x "${bin}/repo-add"
    printf '%s\n' "$bin"
}

write_fake_external_diff() {
    local bin="${DOTFILES_TEST_TMP}/external-diff"
    cat >"$bin" <<'SH'
#!/usr/bin/env sh
set -eu

printf 'external diff should be ignored by generated pkgver cleanup\n'
SH
    chmod +x "$bin"
    printf '%s\n' "$bin"
}

prepare_review_repo() {
    local review_dir=$1
    local remote="${DOTFILES_TEST_TMP}/remote/fake-git.git"
    local source="${DOTFILES_TEST_TMP}/source/fake-git"
    mkdir -p "${remote%/*}" "${source%/*}" "$review_dir"
    git -c init.defaultBranch=master init --bare "$remote" >/dev/null
    git -c init.defaultBranch=master init "$source" >/dev/null
    git -C "$source" config user.email test@example.invalid
    git -C "$source" config user.name "Dotfiles Test"
    cat >"${source}/PKGBUILD" <<'PKGBUILD'
pkgname=fake-git
pkgver=1.r1.gabcdef0
pkgrel=1
pkgdesc='Fake VCS package'
arch=('any')
source=('fake::git+https://example.invalid/fake.git')
sha256sums=('SKIP')

package() {
    :
}
PKGBUILD
    cat >"${source}/.SRCINFO" <<'SRCINFO'
pkgbase = fake-git
	pkgdesc = Fake VCS package
	pkgver = 1.r1.gabcdef0
	pkgrel = 1
	arch = any
	source = fake::git+https://example.invalid/fake.git
	sha256sums = SKIP

pkgname = fake-git
SRCINFO
    git -C "$source" add PKGBUILD .SRCINFO
    git -C "$source" commit -m "Initial fake package" >/dev/null
    git -C "$source" remote add origin "$remote"
    git -C "$source" push --quiet origin master
    git clone --quiet "$remote" "${review_dir}/fake-git"
}

write_repo_patch() {
    local review_dir=$1
    local patch_dir=$2
    mkdir -p "${patch_dir}/fake-git"
    git -C "${review_dir}/fake-git" config user.email test@example.invalid
    git -C "${review_dir}/fake-git" config user.name "Dotfiles Test"
    sed -i "s/^pkgdesc=.*/pkgdesc='Fake VCS package (patched)'/" "${review_dir}/fake-git/PKGBUILD"
    git -C "${review_dir}/fake-git" diff --no-color -- PKGBUILD >"${patch_dir}/fake-git/fix-pkgdesc.patch" || true
    git -C "${review_dir}/fake-git" checkout -- PKGBUILD
    printf '%s\n' "${patch_dir}/fake-git/fix-pkgdesc.patch"
}

case "${DOTFILES_TEST_CASE:-}" in
aur-review-publish-keeps-review-checkout-clean)
    review_dir="${DOTFILES_TEST_TMP}/review"
    build_dir="${DOTFILES_TEST_TMP}/build"
    repo_dir="${DOTFILES_TEST_TMP}/aur-local"
    fake_bin=$(write_fake_tools)
    mkdir -p "$repo_dir"
    prepare_review_repo "$review_dir"

    PATH="${fake_bin}:/usr/bin:/bin" \
        AUR_REVIEW_DIR="$review_dir" \
        AUR_REVIEW_BUILD_DIR="$build_dir" \
        AUR_REVIEW_REPO_DIR="$repo_dir" \
        AUR_REVIEW_BUILD_MODE=makepkg \
        "$script_under_test" publish fake-git >"${DOTFILES_TEST_TMP}/stdout"

    git -C "${review_dir}/fake-git" diff --quiet -- PKGBUILD
    refute rg -q 'mutated.by.fake.makepkg' "${review_dir}/fake-git/PKGBUILD"
    while IFS= read -r cwd; do
        [[ "$cwd" == "${build_dir}/fake-git/worktrees/publish."* ]]
        [[ "$cwd" != "${review_dir}/fake-git" ]]
    done <"${DOTFILES_TEST_TMP}/makepkg.cwd"
    [[ ! -e "${build_dir}/fake-git/worktrees" ]] || [[ -z "$(find "${build_dir}/fake-git/worktrees" -mindepth 1 -print -quit)" ]]
    rg -q 'fake-git-1-1-any.pkg.tar.zst' "${DOTFILES_TEST_TMP}/repo-add.packages"
    ;;
aur-review-accept-restores-generated-pkgver-change)
    review_dir="${DOTFILES_TEST_TMP}/review"
    prepare_review_repo "$review_dir"
    git -C "${review_dir}/fake-git" config diff.external "$(write_fake_external_diff)"
    sed -i 's/^pkgver=.*/pkgver=1.r2.g1234567/' "${review_dir}/fake-git/PKGBUILD"

    AUR_REVIEW_DIR="$review_dir" "$script_under_test" accept fake-git >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q 'restoring generated PKGBUILD pkgver change' "${DOTFILES_TEST_TMP}/stderr"
    git -C "${review_dir}/fake-git" diff --quiet -- PKGBUILD
    refute rg -q '1.r2.g1234567' "${review_dir}/fake-git/PKGBUILD"
    ;;
aur-review-accept-rejects-non-pkgver-change)
    review_dir="${DOTFILES_TEST_TMP}/review"
    prepare_review_repo "$review_dir"
    sed -i "s/^pkgdesc=.*/pkgdesc='Locally changed description'/" "${review_dir}/fake-git/PKGBUILD"

    if AUR_REVIEW_DIR="$review_dir" "$script_under_test" accept fake-git >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"; then
        printf 'aur-review unexpectedly accepted a non-pkgver local change\n' >&2
        exit 1
    fi

    rg -q 'refusing to accept with local worktree changes' "${DOTFILES_TEST_TMP}/stderr"
    rg -q 'Locally changed description' "${review_dir}/fake-git/PKGBUILD"
    ;;
aur-review-publish-applies-repo-patch)
    review_dir="${DOTFILES_TEST_TMP}/review"
    build_dir="${DOTFILES_TEST_TMP}/build"
    repo_dir="${DOTFILES_TEST_TMP}/aur-local"
    patch_dir="${DOTFILES_TEST_TMP}/patches/aur-review"
    fake_bin=$(write_fake_tools)
    mkdir -p "$repo_dir"
    prepare_review_repo "$review_dir"
    patch_file=$(write_repo_patch "$review_dir" "$patch_dir")
    [[ -f "$patch_file" ]]

    PATH="${fake_bin}:/usr/bin:/bin" \
        AUR_REVIEW_DIR="$review_dir" \
        AUR_REVIEW_BUILD_DIR="$build_dir" \
        AUR_REVIEW_REPO_DIR="$repo_dir" \
        AUR_REVIEW_PATCH_DIR="$patch_dir" \
        AUR_REVIEW_BUILD_MODE=makepkg \
        "$script_under_test" publish fake-git >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"

    rg -q 'Applying repo-owned patch' "${DOTFILES_TEST_TMP}/stdout"
    rg -qF 'Fake VCS package (patched)' "${DOTFILES_TEST_TMP}/makepkg.PKGBUILD"
    refute rg -qF 'Fake VCS package (patched)' "${review_dir}/fake-git/PKGBUILD"
    git -C "${review_dir}/fake-git" diff --quiet -- PKGBUILD
    rg -q 'fake-git-1-1-any.pkg.tar.zst' "${DOTFILES_TEST_TMP}/repo-add.packages"
    ;;
aur-review-publish-fails-on-stale-patch)
    review_dir="${DOTFILES_TEST_TMP}/review"
    build_dir="${DOTFILES_TEST_TMP}/build"
    repo_dir="${DOTFILES_TEST_TMP}/aur-local"
    patch_dir="${DOTFILES_TEST_TMP}/patches/aur-review"
    fake_bin=$(write_fake_tools)
    mkdir -p "$repo_dir" "${patch_dir}/fake-git"
    prepare_review_repo "$review_dir"
    cat >"${patch_dir}/fake-git/stale.patch" <<'PATCH'
diff --git a/PKGBUILD b/PKGBUILD
--- a/PKGBUILD
+++ b/PKGBUILD
@@ -4 +4 @@
-pkgdesc='this line does not exist'
+pkgdesc='Fake VCS package (patched)'
PATCH

    if PATH="${fake_bin}:/usr/bin:/bin" \
        AUR_REVIEW_DIR="$review_dir" \
        AUR_REVIEW_BUILD_DIR="$build_dir" \
        AUR_REVIEW_REPO_DIR="$repo_dir" \
        AUR_REVIEW_PATCH_DIR="$patch_dir" \
        AUR_REVIEW_BUILD_MODE=makepkg \
        "$script_under_test" publish fake-git >"${DOTFILES_TEST_TMP}/stdout" 2>"${DOTFILES_TEST_TMP}/stderr"; then
        printf 'aur-review unexpectedly published with a stale patch\n' >&2
        exit 1
    fi

    rg -q 'repo patch no longer applies' "${DOTFILES_TEST_TMP}/stderr"
    [[ ! -e "${DOTFILES_TEST_TMP}/makepkg.cwd" ]]
    refute rg -q 'fake-git-1-1-any.pkg.tar.zst' "${DOTFILES_TEST_TMP}/repo-add.packages"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
