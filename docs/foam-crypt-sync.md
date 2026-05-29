# Foam Crypt Sync

This workstation keeps the private Foam notes tree plaintext on the host and uses a local `rclone crypt` mirror for phone sync. Syncthing should sync only the encrypted mirror directory.

Default paths used by `foam-crypt`:

```text
~/data/notes/foam
~/data/sync/foam-rclone-crypt
```

Initialize the local rclone remotes once:

```sh
foam-crypt init
```

Push the current plaintext tree into the encrypted mirror and initialize `rclone bisync` state:

```sh
foam-crypt resync-from-plain
```

Normal host-side reconciliation after Syncthing has exchanged encrypted files with the phone:

```sh
foam-crypt bisync
```

The automated host workflow is managed by:

```text
foam-crypt-local-watch.service
foam-crypt-watch.service
foam-crypt-auto.service
```

`foam-crypt-local-watch.service` is a long-running user service. It watches the plaintext Foam tree with inotify and triggers `foam-crypt-auto.service` after local edits settle for a short quiet window.

`foam-crypt-watch.service` is also long-running. It listens to Syncthing's REST event stream for the encrypted mirror and triggers `foam-crypt-auto.service` after phone-side encrypted changes arrive.

`foam-crypt-auto.service` is a guarded one-shot worker. It debounces events, waits until Syncthing reports `foam-rclone-crypt` as idle with no pending items or pull errors, refuses to run if `*sync-conflict*` files exist, skips reflected events when the relevant tree metadata is unchanged, ignores symlink metadata because the rclone workflow does not copy symlinks, and then runs `foam-crypt bisync` under a lock so only one reconciliation can run at a time.

After a successful `syncthing`-reason bisync, `foam-crypt-auto` runs `foam-ai-autotrigger`. That parser only reads `misc/todos/ai-autotrigger.todos.md`, selects unchecked TODOs with both `@id` and `@tags #autotrigger`, passes a `foam-ai-autotrigger.v1` JSON payload to `agent-local-execution`, and marks successful TODOs complete. Failures are left unchecked, recorded in `~/.local/state/foam-ai-autotrigger/state.json`, and logged by `foam-crypt-auto.service`.

Generate a phone-side rclone config snippet for RSAF by passing the Android path where Syncthing stores the encrypted mirror:

```sh
foam-crypt rsaf-config /storage/emulated/0/Syncthing/foam-rclone-crypt
```

`foam-crypt s3drive-config` is kept as an alias for the same generic Android rclone config snippet.

The generated snippet embeds rclone's obscured crypt password. Treat it as a secret: rclone obfuscation protects only against accidental reading of the config, not against a local attacker with access to the file.
