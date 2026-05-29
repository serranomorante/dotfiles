# {{ ansible_managed }}
# Shared host editor and shell support used by interactive dev sandboxes.
# Keep top-level hardening, D-Bus policy, and language-specific runtime access
# in the concrete dev profiles so their intent stays readable.

# Read-only editor config, shell config, and host-side helper content.
whitelist-ro ${HOME}/.config/nvim
whitelist-ro ${HOME}/.fzfrc
whitelist-ro ${HOME}/.config/kdeglobals
whitelist-ro ${HOME}/.gitconfig
whitelist-ro ${HOME}/.config/git
whitelist-ro ${HOME}/.local/share/uv/tools
whitelist-ro ${HOME}/.local/share/uv/python
whitelist-ro ${HOME}/.local/share/nvim/runtime
whitelist-ro ${HOME}/.local/share/nvim/site
whitelist-ro ${HOME}/.local/kitty.app
whitelist-ro ${HOME}/dotfiles/term/bin
whitelist-ro ${HOME}/dotfiles/nvim/bin
whitelist-ro ${HOME}/dotfiles/nvim/dot-config/nvim
whitelist-ro ${HOME}/dotfiles/for-my-eyes-only/dot-config/nvim
whitelist-ro ${HOME}/dotfiles/playbooks
whitelist-ro ${HOME}/dotfiles/for-my-eyes-only/playbooks
whitelist-ro ${HOME}/.local/bin
whitelist-ro ${HOME}/bin
whitelist-ro ${HOME}/data/apps

# Writable editor and shell state that should persist on the host.
whitelist ${HOME}/.fzf_history
