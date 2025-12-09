# dotfiles

These dotfiles help me replicate my exact system after OS upgrades or after a fresh archlinux install.

The system is intented to be used just by me, but you can extract any useful configs from this repo if you want.

## How to replicate the full system

If you want to install my system (why would you want that?) you can, but you need **a fresh arch linux installation**:

> warning: if you're gonna do this on a virtual machine, enable 3D acceleration and pre-allocate the disk space instead of using dynamic disk allocation.

> only tested on AMD with NVIDIA gpu using linux-lts

### Partitions

4 partitions:

1. at least `8Gb` of a swap partition
1. at least `30Gb` mounted to /
1. at least `60Gb` mounted to /home

### Dependencies

A fresh archlinux install with just `git` and `ansible`

### User

You need a user with sudo access and added to the `wheel` group. Don't try to run the playbook as root.

### Steps

1. `git clone https://github.com/serranomorante/dotfiles`
1. `cd dotfiles/playbooks`
1. `ansible-playbook -K tools.yml -l localhost --tags all`

It will take at least ~1h to complete, do a restart, select Plasma x11 session on the login screen, enter your password and that's all.

### What tools does it have?

Everything I use, even browser extensions with my own configs already patched into the extensions themselves.

### What it doesn't have?

My secret keys and data.

## Some guides to my self

- [Python development setup with Neovim](./docs/python-dev-setup.md)
- [keyd special chars setup](./docs/keyd-setup.md)
- [disable internal keyboard with libinput and keyd](./docs/disable-internal-keyboard.md)
- [migrate from optimus-manager to official NVIDIA prime](./docs/nvidia-setup.md)
- [nvim-dap and node cli app written in typescript](./docs/nvim-dap-node-cli.md)
- [Comments on neovim plugins journey](/docs/nvim-plugins.md)
