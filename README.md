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

## Advance: install arch with LUKS, secure boot and tpm

**Important**: this will format your partitions and delete all your data, remove any external drives before proceding

**Important**: this arch install is meant for 2 drives: drive 1 (500GB) is going to have the EFI, swap and root partitions, drive 2 (1TB) is going to have home partition. Everything except EFI partition will be encrypted. `EFI`, `swap` and `root` partitions are mounted automatically by `systemd-gpt-auto-generator` while home is mounted by crypttab + fstab.

I dislike installing arch manually.

This ansible playbook was run from a remote computer. I haven't tested executing these playbooks from inside the arch bootable usb and I don't recommend you try to do it this way unless you have at least 8GB on your usb.

Requirements:

Disable secure boot and reset/clear the existent keys.

You need 2 public ssh authorization keys on your **booted usb system**

The reason behind this is that one of those two keys is going to run commands in a chroot environment automatically for us.

`cat ~/.ssh/authorized_keys`

```sh
...your public ssh key number one
command="/root/ssh_chroot" ...the rest of your public ssh key number two
```

`command="/root/ssh_chroot"` is the thing that is going to force that some ansible operations run on a chroot environment.

On your host system, you need this client ssh config

`cat ~/.ssh/config`

```sshconfig
Host arch-chroot
HostName <the ip of your booted usb system>
User root
IndentityFile ~/.ssh/your private ssh key...arch_chroot

Host arch-user
HostName <the ip of your booted usb system>
User root
IndentityFile ~/.ssh/your private ssh key...arch_user
```

And finally your ansible inventory should reflect these 2 hosts

```
[arch_user]
arch-user

[arch_chroot]
arch-chroot
```

**Important**: you might need to run `rm -rf ~/.ansible` at some point if ansible cache is giving you problems

**Important**: these playbook are not design in a indempotent way, everything should work ok on the first run otherwise it will format the partitions again and again.

Now you can run the playbooks like this:

First, the initial setup, all tasks should work.

`ansible-playbook arch-user-setup.yml -l arch_user`

Then, the chroot setup, all tasks should work. When this playbook ends you should manually restart your computer and enable secure boot.

`ansible-playbook arch-chroot-setup.yml -l arch_chroot`

Lastly, we do a new pass on the first playbook again to complete installation. After this you can proceed with the regular user stuff

`ansible-playbook arch-user-setup.yml -l arch_user`

## Some guides to my self

- [Python development setup with Neovim](./docs/python-dev-setup.md)
- [keyd special chars setup](./docs/keyd-setup.md)
- [disable internal keyboard with libinput and keyd](./docs/disable-internal-keyboard.md)
- [migrate from optimus-manager to official NVIDIA prime](./docs/nvidia-setup.md)
- [nvim-dap and node cli app written in typescript](./docs/nvim-dap-node-cli.md)
- [Comments on neovim plugins journey](/docs/nvim-plugins.md)
