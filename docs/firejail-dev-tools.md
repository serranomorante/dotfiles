# Firejail Dev Tool Workflow

Use Firejail by default for tools, apps, package-manager activity, model downloaders, and runtime commands that can reasonably be sandboxed. The working assumption is that almost any newly introduced software can be affected by a supply chain attack, especially when it comes from language package registries, AUR packages, upstream binary releases, install scripts, browser automation, AI tools, or model downloaders.

Pacman-managed packages are useful because they keep ownership, upgrades, and removal reproducible, but they should not be treated as immune to compromise. Apply the same supply-chain posture to newly introduced software regardless of source. When a tool will install code, process untrusted input, or contact the network at runtime, prefer a Firejail wrapper/profile and expose only the paths and sockets the tool needs.

This matters most from Ansible, where package-manager tasks can download and execute third-party code, but it also applies to day-to-day wrappers under `utilities/bin/`, `term/bin/`, and other stowed packages.

## Supply Chain Policy

- Prefer package-manager-owned installs over ad hoc files when they satisfy the need, so ownership, upgrades, and removal stay reproducible.
- Treat newly introduced software as supply-chain-risky regardless of whether it comes from official repositories, AUR, upstream binary releases, language package registries, or installer scripts.
- If a package installs or runs tooling that does not need broad host access, add a Firejail runtime wrapper or document why that is not practical.
- Do not run `pip`, `npm`, `pnpm`, `cargo install`, Go install flows, model downloaders, browser installers, or similar third-party code directly from Ansible when an existing Firejail adapter or wrapper can express the workflow.
- For runtime commands, use the narrowest viable network mode: `offline` first, `local` for Unix-socket IPC, and `online` only when external network access is required.
- Keep clipboard, keyboard injection, audio playback, and other broad desktop actions outside the sandbox when possible. Let the sandboxed process perform only the risky parsing, inference, build, download, or package-manager work.
- If a new install or runtime path cannot be sandboxed without breaking its core purpose, add a short comment or workflow-doc note explaining the exception and the privilege boundary.

## Existing Wrappers

The `20-dev-tools` role owns the shared wrappers and profiles:

- `fj-py`: generic Python command wrapper.
- `fj-node`: generic Node command wrapper.
- `fj-php`: generic PHP and Composer command wrapper.
- `ansible-firejail-pip`: `pip`-shaped adapter for `ansible.builtin.pip`.
- `ansible-firejail-npm`: `npm`-shaped adapter for `community.general.npm`.
- `ansible-firejail-pnpm`: `pnpm`-shaped adapter for `community.general.pnpm`.
- `ansible-firejail-composer`: `composer`-shaped adapter for `community.general.composer`.
- `firejail-wrapper-common.bash`: shared path, env, and profile helpers.
- `fj-py.profile`, `fj-node.profile`, `fj-php.profile`: generic non-interactive profiles.
- `fj-py-ansible.profile`, `fj-node-ansible.profile`, `fj-php-ansible.profile`: package-install profiles used by the Ansible adapters.
- `fj-py-interactive.profile`: Python profile variant for interactive shells that need real `/dev/pts` behavior.

The wrappers use a clean environment and expose only the project root plus explicitly requested paths. Prefer expanding the existing wrappers before creating a new one.

Generic `fj-node`, `fj-py`, and `fj-php` runs preserve the caller's absolute project path as the sandbox-visible work tree, but their default XDG state does not inherit broad host roots. Unless explicitly overridden, Node writes cache/state/data under `~/.cache/firejail-wrapper/node`, `~/.local/state/firejail-wrapper/node`, and `~/.local/share/firejail-wrapper/node`; Python uses the matching `python` roots; PHP and Composer use the matching `php` roots, with `COMPOSER_HOME` defaulting to `~/.local/share/firejail-wrapper/php/composer` and `COMPOSER_CACHE_DIR` defaulting to `~/.cache/firejail-wrapper/php/composer`. Keep package-manager caches inside those wrapper-scoped roots unless a specific adapter has a narrower project-specific cache path.

When a wrapper owns the executable name that other tools call, and that executable may be launched either directly or from inside another Firejail sandbox, the wrapper itself should make the containment decision. If it is not already inside Firejail, it should start its normal sandbox. If it is already inside Firejail and intends to reuse the inherited sandbox, it must first run `fj-profile-checker` against the expected profile and fail closed if the current filesystem view does not satisfy that profile. Do this in the wrapper rather than in the parent process, so every caller of the executable gets the same safety check.

Firejail-wrapped language servers launched by Neovim should use Neovim's launch cwd as the sandbox project root, then pass the managed server install prefix, config paths, and helper runtime paths through `FJ_NODE_EXTRA_PATHS` or `FJ_PY_EXTRA_PATHS`. Child wrappers may reuse an existing sandbox only after `fj-profile-checker <profile> -- <command ...>` verifies the expected profile's basic filesystem rules: included profile fragments are readable, `whitelist` paths are visible, `whitelist-ro` paths are visible but not writable, and `blacklist` paths are hidden. Put tool-specific sensitive-path expectations in the profile as `blacklist` rules rather than in the checker. If a language-server wrapper detects that it is already inside a sandbox and the checker fails, it should fail closed instead of trying nested Firejail and relying on Firejail's existing-sandbox behavior. Neovim LSP configs for servers built on `vscode-languageserver` should set `params.processId = vim.NIL` in `before_init` when the server runs under Firejail, because the server's client watchdog may not be able to see Neovim's host PID from inside the sandbox and can otherwise exit after initialization. The Neovim sandbox profile must expose interpreter targets reached through tool shims, such as uv-managed Python runtimes used by `ansible-lint`, not only the shim directory. Prefer absolute paths for helper executables configured inside language servers because those servers may invoke helpers from an internal shell whose `PATH` differs from Neovim's launch environment.

`fj-dev-nvim` exposes Neovim runtime files read-only and appends only the current cwd's local state paths as writable. For broad roots such as `$HOME`, `$HOME/data`, `$HOME/data/repos`, and `$HOME/data/secrets`, the wrapper does not expose cwd-scoped Neovim cache/state paths, matching the editor config's rule that persistent ShaDa, undo, Fundo, and future buffer-content state stay disabled for broad or secret roots.

## Network Modes

Generic wrappers use this shape:

```sh
fj-py <online|local|offline> <project> -- <command ...>
fj-node <online|local|offline> <project> -- <command ...>
fj-php <online|local|offline> <project> -- <command ...>
```

- `online`: normal network access. Use for downloading packages, models, browser artifacts, or remote resources.
- `local`: Unix sockets only. Use for tools that need local IPC but not TCP.
- `offline`: no external networking. Firejail creates a network namespace with only loopback, which is useful for commands that must not reach the network.

Do not assume `local` is sufficient for HTTP. The repository's `local` mode allows Unix sockets only, so a `127.0.0.1` HTTP server needs either a dedicated profile/wrapper or an `offline` named sandbox where clients join the same Firejail namespace.

## Ansible Package Installs

Use the adapter executable rather than raw `pip`, `npm`, `pnpm`, or `composer`. If a package manager is not covered by an existing adapter, first look for an existing generic wrapper such as `fj-py`, `fj-node`, or `fj-php`; add a new adapter only when the workflow repeats enough to justify it.

Python:

```yaml
- name: "Ensure Python tool venv"
  ansible.builtin.pip:
    name:
      - pip
      - some-package
    executable: "{{ ansible_facts.env.HOME }}/bin/ansible-firejail-pip"
    state: present
  environment:
    ANSIBLE_FIREJAIL_PIP_VENV: "{{ ansible_facts.env.HOME }}/data/apps/example/.venv"
```

NPM:

```yaml
- name: "Ensure npm package"
  community.general.npm:
    name: some-package
    version: 1.2.3
    global: true
    state: present
    executable: "{{ ansible_firejail_npm_executable }}"
  environment:
    ANSIBLE_FIREJAIL_NPM_NODE_VERSION: "{{ node_system_default_version }}"
    ANSIBLE_FIREJAIL_NPM_PREFIX: "{{ ansible_facts.env.HOME }}/data/apps/example/.npm"
```

PNPM:

```yaml
- name: "Ensure pnpm package"
  community.general.pnpm:
    name: some-package
    version: 1.2.3
    path: "{{ ansible_facts.env.HOME }}/data/apps/example"
    state: present
    executable: "{{ ansible_firejail_pnpm_executable }}"
  environment:
    ANSIBLE_FIREJAIL_PNPM_NODE_VERSION: "{{ node_system_default_version }}"
```

Composer:

```yaml
- name: "Ensure Composer project dependencies"
  community.general.composer:
    command: install
    working_dir: "{{ project_path }}"
    composer_executable: "{{ ansible_firejail_composer_executable }}"
  environment:
    XDEBUG_MODE: "off"
    ANSIBLE_FIREJAIL_COMPOSER_EXTRA_PATHS: |
      {{ optional_readonly_helper_path }}
```

Composer auth and tokens are not exposed by default. For private registries, pass `COMPOSER_AUTH` through `FJ_PHP_FORWARD_ENV` for one command or expose a narrow project-specific Composer home through `COMPOSER_HOME` plus `FJ_PHP_WRITABLE_PATHS`; do not whitelist `~/.composer` or `~/.config/composer` broadly.

When an install needs extra writable state, create the target directories first and pass newline-delimited absolute paths through the adapter-specific writable path variable:

```yaml
environment:
  ANSIBLE_FIREJAIL_PIP_VENV: "{{ project_path }}/.venv"
  ANSIBLE_FIREJAIL_PIP_WRITABLE_PATHS: |
    {{ project_path }}/cache
```

## Running PHP Tools

For local execution after Composer install, prefer `fj-php` directly and choose the narrowest viable network mode:

```yaml
- name: "Run PHP tests offline"
  ansible.builtin.command:
    argv:
      - "{{ php_firejail_executable }}"
      - offline
      - "{{ project_path }}"
      - --
      - php
      - artisan
      - test
```

Use `online` for Composer dependency resolution or package download, then use `offline` for framework commands, test runs, autoload checks, and application scripts that do not need the internet. The Arch-owned PHP and Composer packages remain installed by the PHP language tooling task; `fj-php` only constrains package-manager execution and runtime commands. `fj-php` sets `XDEBUG_MODE=off` by default to keep ordinary sandboxed CLI runs quiet; set `XDEBUG_MODE` explicitly when debugging. The PHP profiles expose `~/dotfiles/utilities/bin` read-only because user commands such as `~/bin/composer-legacy` can be Stow symlinks whose targets live there.

## Running Python Tools

For local execution after install, prefer `fj-py` directly:

```yaml
- name: "Run Python tool offline"
  ansible.builtin.command:
    argv:
      - "{{ python_firejail_executable }}"
      - offline
      - "{{ project_path }}"
      - --
      - "{{ project_path }}/.venv/bin/python"
      - -m
      - package.module
```

Use `online` only when the command must fetch remote resources:

```yaml
- name: "Download model assets"
  ansible.builtin.command:
    argv:
      - "{{ python_firejail_executable }}"
      - online
      - "{{ project_path }}"
      - --
      - "{{ project_path }}/.venv/bin/python"
      - -m
      - package.download_assets
```

For interactive shell workflows, set `FJ_PY_PROFILE=fj-py-interactive.profile`.

For stdio MCP servers and other long-running offline Python tools that intentionally launch through `uv run`, keep the runtime path Firejailed and make startup non-resolving: pass `uv run --offline --no-sync ...` and expose only the needed uv cache path through wrapper env, such as `FJ_PY_WRITABLE_PATHS=$HOME/.cache/uv`. Do not let an offline runtime server depend on `uv run` doing a build, sync, or package fetch before stdio startup.

## Piper TTS Guidance

For Piper:

- Install `piper-tts[http]` into a managed venv with `ansible-firejail-pip`.
- Download voices with `fj-py online <piper project> -- <venv python> -m piper.download_voices ...`.
- Run the HTTP server in a named Firejail sandbox using `fj-py offline` plus a Piper-specific profile. This gives the server loopback inside the sandbox without exposing it as a normal host-network service.
- Have clients use `firejail --join=<sandbox-name>` for HTTP requests to the server's `127.0.0.1`.
- Play the generated WAV outside Firejail with `pw-play`, `paplay`, or `aplay`.

## Speech-To-Text Guidance

For Python STT and dictation tools:

- Run local recognition commands through `fj-py offline` by default.
- Keep model downloads outside the runtime command path; Ansible should fetch model assets explicitly, then runtime wrappers should use the local files.
- Expose only the model directory, a small project directory, the runtime state directory, and the local PipeWire/Pulse sockets needed for microphone input.
- Do clipboard and keyboard injection outside the Python sandbox where possible, so the recognizer only needs microphone access and local model files.
- If a microphone or PipeWire limitation forces an unsandboxed debug run, gate it behind an explicit environment override and document it in the voice workflow notes.

For GPU-backed STT such as `whisper.cpp` with CUDA, keep runtime networking disabled and whitelist only the managed binary, selected model, and runtime audio file. If CUDA requires real `/dev/nvidia*` access, document the profile's device-boundary exception and disable unrelated desktop device classes instead of dropping the sandbox entirely.

## When To Add A New Profile

Add a new Firejail profile only when an existing profile cannot express the tool's needs through project root, extra read-only paths, extra writable paths, forwarded env vars, and the three network modes.

Good reasons for a new profile:

- A long-running service needs a stable sandbox name.
- A tool needs a different device policy.
- A tool needs a narrower or different DBus policy.
- A local server needs a carefully documented network policy.
- A tool needs stable access to a nonstandard host path that should not be added to the generic Python or Node profiles.

Do not add a new profile just to install another pip/npm package into a managed venv or prefix.
