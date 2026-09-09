# Purpose: Shared metadata store for cross-tool named marks. Source this file
# to get `marks_*` helpers for persisting per-scope key=value labels next to a
# system's own position store. Used by tmux copy-mode marks and Neovim global
# marks so label handling is implemented once.
# Notes: Each scope (tmux session name, Neovim cwd key, ...) maps to one file
# under $XDG_STATE_HOME/dotfiles/marks/<scope>.labels. Sourcing defines
# functions only and performs no side effects.

marks_state_root() {
    printf '%s\n' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/marks"
}

marks_scope_key() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# An empty scope would silently collapse every caller onto a single `.labels`
# file, so refuse it instead of storing labels nobody can look up again.
marks_meta_file() {
    key=$(marks_scope_key "$1")
    if [ -z "$key" ]; then
        printf 'marks: refusing empty scope\n' >&2
        return 1
    fi
    printf '%s\n' "$(marks_state_root)/$key.labels"
}

marks_clean_text() {
    printf '%s' "$1" | tr '\t\n' ' ' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

marks_meta_get() {
    scope=$1
    key=$2
    file=$(marks_meta_file "$scope") || return 1
    [ -f "$file" ] || return 0
    while IFS= read -r line; do
        case $line in
        "$key"=*) printf '%s\n' "${line#"$key"=}" ;;
        esac
    done <"$file"
}

marks_meta_set() {
    scope=$1
    key=$2
    value=$3
    file=$(marks_meta_file "$scope") || return 1
    dir=$(dirname "$file")
    mkdir -p "$dir" || return 0
    tmp=$(mktemp "$dir/.labels.XXXXXX") || return 0

    if [ -f "$file" ]; then
        while IFS= read -r line; do
            case $line in
            "$key"=*) ;;
            *) printf '%s\n' "$line" ;;
            esac
        done <"$file" >"$tmp"
    fi
    printf '%s=%s\n' "$key" "$value" >>"$tmp"
    mv "$tmp" "$file"
}

marks_meta_clear() {
    scope=$1
    key=$2
    file=$(marks_meta_file "$scope") || return 1
    [ -f "$file" ] || return 0
    dir=$(dirname "$file")
    tmp=$(mktemp "$dir/.labels.XXXXXX") || return 0
    while IFS= read -r line; do
        case $line in
        "$key"=*) ;;
        *) printf '%s\n' "$line" ;;
        esac
    done <"$file" >"$tmp"
    if [ -s "$tmp" ]; then
        mv "$tmp" "$file"
    else
        rm -f "$tmp" "$file"
    fi
}

marks_meta_list() {
    scope=$1
    file=$(marks_meta_file "$scope") || return 1
    [ -f "$file" ] || return 0
    while IFS= read -r line; do
        case $line in
        *=*) printf '%s\t%s\n' "${line%%=*}" "${line#*=}" ;;
        esac
    done <"$file"
}
