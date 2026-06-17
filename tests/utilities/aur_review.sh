#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: utilities
# dotfiles-test-tags: utilities aur shell
# dotfiles-test-case: aur-review-publish-keeps-review-checkout-clean

# Purpose: Verify aur-review builds packages outside the reviewed AUR checkout.

script_under_test="${DOTFILES_TEST_ROOT}/utilities/bin/aur-review"

write_fake_tools() {
    local bin="${DOTFILES_TEST_TMP}/bin"
    mkdir -p "$bin"
    cat >"${bin}/makepkg" <<'SH'
#!/usr/bin/env sh
set -eu

printf '%s\n' "$PWD" >>"${DOTFILES_TEST_TMP}/makepkg.cwd"
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
    ! rg -q 'mutated.by.fake.makepkg' "${review_dir}/fake-git/PKGBUILD"
    while IFS= read -r cwd; do
        [[ "$cwd" == "${build_dir}/fake-git/worktrees/publish."* ]]
        [[ "$cwd" != "${review_dir}/fake-git" ]]
    done <"${DOTFILES_TEST_TMP}/makepkg.cwd"
    [[ ! -e "${build_dir}/fake-git/worktrees" ]] || [[ -z "$(find "${build_dir}/fake-git/worktrees" -mindepth 1 -print -quit)" ]]
    rg -q 'fake-git-1-1-any.pkg.tar.zst' "${DOTFILES_TEST_TMP}/repo-add.packages"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
