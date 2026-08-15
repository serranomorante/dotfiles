#!/usr/bin/env bash

uri="${1:-}"
case "$uri" in
editor:///agent_conversation/*)
    rest=${uri#editor:///agent_conversation/}
    session_id=${rest##*/}
    cwd=${rest%/*}
    [ -n "$cwd" ] && cwd="/$cwd"
    cwd=$(printf '%s' "$cwd" | python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))')
    open_in_nvim --cwd "$cwd" agent_conversation "$session_id"
    exit $?
    ;;
esac

FILENAME="/$(echo $* | cut -d / -f 4-)"
kitty-open-in-editor $FILENAME
