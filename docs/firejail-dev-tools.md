# Firejail Dev Tool Workflow

Use Firejail by default for language package-manager activity and for running
Python or Node tooling that does not need full host access. This matters most
from Ansible, where package-manager tasks can download and execute third-party
code.

## Existing Wrappers

The `20-dev-tools` role owns the shared wrappers and profiles:

- `fj-py`: generic Python command wrapper.
- `fj-node`: generic Node command wrapper.
- `ansible-firejail-pip`: `pip`-shaped adapter for `ansible.builtin.pip`.
- `ansible-firejail-npm`: `npm`-shaped adapter for `community.general.npm`.
- `ansible-firejail-pnpm`: `pnpm`-shaped adapter for `community.general.pnpm`.
- `firejail-wrapper-common.bash`: shared path, env, and profile helpers.
- `fj-py.profile`, `fj-node.profile`: generic non-interactive profiles.
- `fj-py-ansible.profile`, `fj-node-ansible.profile`: package-install
  profiles used by the Ansible adapters.
- `fj-py-interactive.profile`: Python profile variant for interactive shells
  that need real `/dev/pts` behavior.

The wrappers use a clean environment and expose only the project root plus
explicitly requested paths. Prefer expanding the existing wrappers before
creating a new one.

## Network Modes

Generic wrappers use this shape:

```sh
fj-py <online|local|offline> <project> -- <command ...>
fj-node <online|local|offline> <project> -- <command ...>
```

- `online`: normal network access. Use for downloading packages, models,
  browser artifacts, or remote resources.
- `local`: Unix sockets only. Use for tools that need local IPC but not TCP.
- `offline`: no external networking. Firejail creates a network namespace with
  only loopback, which is useful for commands that must not reach the network.

Do not assume `local` is sufficient for HTTP. The repository's `local` mode
allows Unix sockets only, so a `127.0.0.1` HTTP server needs either a dedicated
profile/wrapper or an `offline` named sandbox where clients join the same
Firejail namespace.

## Ansible Package Installs

Use the adapter executable rather than raw `pip`, `npm`, or `pnpm`.

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

When an install needs extra writable state, create the target directories first
and pass newline-delimited absolute paths through the adapter-specific writable
path variable:

```yaml
environment:
  ANSIBLE_FIREJAIL_PIP_VENV: "{{ project_path }}/.venv"
  ANSIBLE_FIREJAIL_PIP_WRITABLE_PATHS: |
    {{ project_path }}/cache
```

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

## Piper TTS Guidance

For Piper:

- Install `piper-tts[http]` into a managed venv with
  `ansible-firejail-pip`.
- Download voices with `fj-py online <piper project> -- <venv python> -m
  piper.download_voices ...`.
- Run the HTTP server in a named Firejail sandbox using `fj-py offline` plus a
  Piper-specific profile. This gives the server loopback inside the sandbox
  without exposing it as a normal host-network service.
- Have clients use `firejail --join=<sandbox-name>` for HTTP requests to the
  server's `127.0.0.1`.
- Play the generated WAV outside Firejail with `pw-play`, `paplay`, or `aplay`.

## Speech-To-Text Guidance

For Python STT and dictation tools:

- Run local recognition commands through `fj-py offline` by default.
- Keep model downloads outside the runtime command path; Ansible should fetch
  model assets explicitly, then runtime wrappers should use the local files.
- Expose only the model directory, a small project directory, the runtime state
  directory, and the local PipeWire/Pulse sockets needed for microphone input.
- Do clipboard and keyboard injection outside the Python sandbox where possible,
  so the recognizer only needs microphone access and local model files.
- If a microphone or PipeWire limitation forces an unsandboxed debug run, gate
  it behind an explicit environment override and document it in the voice
  workflow notes.

## When To Add A New Profile

Add a new Firejail profile only when an existing profile cannot express the
tool's needs through project root, extra read-only paths, extra writable paths,
forwarded env vars, and the three network modes.

Good reasons for a new profile:

- A long-running service needs a stable sandbox name.
- A tool needs a different device policy.
- A tool needs a narrower or different DBus policy.
- A local server needs a carefully documented network policy.
- A tool needs stable access to a nonstandard host path that should not be
  added to the generic Python or Node profiles.

Do not add a new profile just to install another pip/npm package into a managed
venv or prefix.
