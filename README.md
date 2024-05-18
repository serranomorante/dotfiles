# dotfiles

Main technologies:

- [kitty](https://github.com/kovidgoyal/kitty). Terminal emulator
- [neovim](https://neovim.io/). Text editor
- [fish](https://fishshell.com/docs/current/tutorial.html). Shell
- [tmux](https://github.com/tmux/tmux). Terminal multiplexer
- [i3](https://i3wm.org/). Window tiling manager
- [m2i](https://gitlab.com/enetheru/midi2input). Use midi to control your system
- [gromit-mpx](https://github.com/bk138/gromit-mpx). Draw on top of your screen
- [keyd](https://github.com/rvaiya/keyd). A key remapping daemon for linux
- [pipewire](https://github.com/rvaiya/keyd). Multimedia processing graphs
- [wireplumber](https://gitlab.freedesktop.org/pipewire/wireplumber). Session manager for Pipewire

## Requirements

Necesary dependencies for my workflow

- [IosevkaTerm Nerd Font](https://github.com/ryanoasis/nerd-fonts/tree/master/patched-fonts/IosevkaTerm)
- [feh](https://wiki.archlinux.org/title/feh). Set your system wallpaper programatically
- [jq](https://man.archlinux.org/man/jq.1.en). Command-line JSON processor
- [xgetres](https://aur.archlinux.org/packages/xgetres). Get entries from .Xresources
- [veikk-tablet-bin](https://aur.archlinux.org/packages/veikk-tablet-bin). Driver for my graphic tablet

## Workflow

## Plans

- **Add m2i's config files**. Still in progress
- **Add wireplumber's config files**. :white_check_mark: ~Still in progress~
- **Add pipewire's config files**. :white_check_mark: ~Still in progress~

## Some guides to my self

- [Python development setup with Neovim](./docs/python-dev-setup.md)
- [keyd special chars setup](./docs/keyd-setup.md)
- [disable internal keyboard with libinput and keyd](./docs/disable-internal-keyboard.md)
- [migrate from optimus-manager to official NVIDIA prime](./docs/nvidia-setup.md)
- [nvim-dap and node cli app written in typescript](./docs/nvim-dap-node-cli.md)
- [Comments on neovim plugins journey](/docs/nvim-plugins.md)

## Past tools

Tools I used to use

- [wezterm](https://wezfurlong.org/wezterm/index.html). Terminal emulator. I stopped using it due to CPU performance consumption.
- [optimus-manager](https://github.com/Askannz/optimus-manager). GPU switching on Optimus laptops. Migrated from it to official NVIDIA prime method.
- [zellij](https://github.com/zellij-org/zellij). Terminal multiplexer. Still in early staging, not so much cutomizability
- [autorandr](https://github.com/phillipberndt/autorandr). Automate display configuration. Not necessary anymore
