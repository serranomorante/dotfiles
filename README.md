# .dotfiles

This are my personal config files that might only make sense for my particular workflow.

Main technologies:

- [kitty](https://github.com/kovidgoyal/kitty). Terminal emulator
- [neovim](https://neovim.io/). (**Neovim >=0.10.0 only**) My text editor
- [fish](https://fishshell.com/docs/current/tutorial.html). Shell
- [zellij](https://github.com/zellij-org/zellij). (**Nightly only**) Terminal multiplexer
- [autorandr](https://github.com/phillipberndt/autorandr). Automate display configuration
- [i3](https://i3wm.org/). Window tiling manager
- [m2i](https://gitlab.com/enetheru/midi2input). Use midi to control your system
- [gromit-mpx](https://github.com/bk138/gromit-mpx). Draw on top of your screen
- [keyd](https://github.com/rvaiya/keyd). A key remapping daemon for linux
- [pipewire](https://github.com/rvaiya/keyd). Multimedia processing graphs
- [wireplumber](https://gitlab.freedesktop.org/pipewire/wireplumber). (**Wireplumber >=0.5 only**) Session manager for Pipewire

## Requirements

Necesary dependencies for my workflow

- [JetBrains Mono](https://github.com/ryanoasis/nerd-fonts#patched-fonts)
- [feh](https://wiki.archlinux.org/title/feh). Set your system wallpaper programatically
- [babelfish](https://github.com/bouk/babelfish). To re-use .bashrc entries in fish (faster than `bass`). You must install `babelfish` first. I did it with `go install`
- [jq](https://man.archlinux.org/man/jq.1.en). Command-line JSON processor
- [xgetres](https://aur.archlinux.org/packages/xgetres). Get entries from .Xresources
- [veikk-tablet-bin](https://aur.archlinux.org/packages/veikk-tablet-bin). Driver for my graphic tablet

## Workflow

### Bash and fish interoperability

Even thought I like [fish](https://fishshell.com/docs/current/index.html) and I use it extensively, I still refuse to make it my main shell.

In my current workflow, I only use fish from inside my terminal (kitty), leaving the rest of my system to use the default shell (bash).

As I don't want to duplicate the same env variables and aliases from my `.bashrc` file into my `config.fish`, I decided to use fish [babelfish](https://github.com/bouk/babelfish) plugin. With this plugin I just need to source my `~/.bashrc` file from inside fish and it will try its best to transpile bash syntax into fish.

## Plans

- **Add m2i's config files**. Still in progress
- **Add zellij's config files**. :white_check_mark: ~I still don't add them because at the moment zellij doens't support path variable expansion so I will wait until then.~
- **Add wireplumber's config files**. :white_check_mark: ~Still in progress~
- **Add pipewire's config files**. :white_check_mark: ~Still in progress~

## Some guides to my self

- [Python development setup with Neovim](./docs/python-dev-setup.md)
- [keyd special chars setup](./docs/keyd-setup.md)
- [disable internal keyboard with libinput and keyd](./docs/disable-internal-keyboard.md)
- [migrate from optimus-manager to official NVIDIA prime](./docs/nvidia-setup.md)
- [nvim-dap and node cli app written in typescript](./docs/nvim-dap-node-cli.md)

## Past tools

I deprecated this tools from my setup for several reasons

- [wezterm](https://wezfurlong.org/wezterm/index.html). Terminal emulator. I stopped using it due to CPU performance consumption.
- [optimus-manager](https://github.com/Askannz/optimus-manager). GPU switching on Optimus laptops. Migrated from it to official NVIDIA prime method.

