# dotfiles

These dotfiles help me replicate my exact system after OS upgrades or after a fresh archlinux install.

The system is intented to be used just by me, but you can extract any useful configs from this repo if you want.

You might see files like `dot-bashrc` instead of `.bashrc` on this repo. I use `stow --dotfiles` command to symlink those `dot-bashrc` into `.bashrc` files. Using this convention helps with the fact that `.bashrc` (or any other file that starts with a literal dot) are hidden by default on some explorers, code editors, etc.

## How to replicate the full system

If you want to install my system (why would you want that?) you can, but you need **a fresh arch linux installation**:

### Prerequisits

- Only for machines with 2 nvme drives. These playbooks follow the strict convention of system partitions on physical drive 1 and home partition on physical drive 2. Even if you try to test this on a virtual machine, you must setup 2 nvme drives on that virtual machine.
- 

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

**Important**: this arch install is meant for 2 nvme drives: drive 1 (min 40GB) is going to have the EFI, swap and root partitions, drive 2 (min 40GB) is going to have home partition. Everything except EFI partition will be encrypted. `EFI`, `swap` and `root` partitions are mounted automatically by `systemd-gpt-auto-generator` while home is mounted by crypttab + fstab.

I dislike installing arch manually.

This ansible playbook was run from a remote computer. I haven't tested executing these playbooks from inside the arch bootable usb and I don't recommend you try to do it this way unless you have at least 8GB on your usb.

Requirements:

Disable secure boot and reset/clear the existent keys.

You need 2 public ssh authorization keys on your **booted usb system**

```sh
# the email doesn't matter
ssh-keygen -t ed25519 -C "arch_user@example.com" -f ~/.ssh/ed25519.arch_user -N ""
ssh-keygen -t ed25519 -C "arch_chroot@example.com" -f ~/.ssh/ed25519.arch_chroot -N ""
```

The reason behind this is that one of those two keys is going to run commands in a chroot environment automatically for us.

On your host system, you need this client ssh config

`cat ~/.ssh/config`

```sshconfig
Host arch-chroot
HostName <the ip of your booted usb system>
User root
IdentitiesOnly yes
IdentityFile ~/.ssh/your private ssh key...arch_chroot

Host arch-user
HostName <the ip of your booted usb system>
User root
IdentitiesOnly yes
IdentityFile ~/.ssh/your private ssh key...arch_user
```

`IdentitiesOnly yes` is required here. Otherwise `ssh-agent` may offer a different loaded key first, and `arch-chroot` can end up authenticating as `arch-user`, which bypasses the forced `command="/root/ssh_chroot"` behavior.

On the guest system:

`vim ~/.ssh/authorized_keys`

```sh
...<your arch_user ssh key (public)>
command="/root/ssh_chroot" <your arch_chroot ssh key (public)>
```

`command="/root/ssh_chroot"` is the thing that is going to force that some ansible operations run on a chroot environment.

And finally your ansible inventory should reflect these 2 hosts

```
[arch_user]
arch-user

[arch_chroot]
arch-chroot
```

**Important**: you might need to run `rm -rf ~/.ansible` at some point if ansible cache is giving you problems

**Important**: these playbook are not design in a indempotent way, everything should work ok on the first run otherwise it will format the partitions again and again.

As last step you need to fill these variables in the ansible files:

You need to gather this info:

- **system_disk_by_id**\
  Execute: `ls -l /dev/disk/by-id | grep nvme`
- **home_disk_by_id**\
  Same here, execute: `ls -l /dev/disk/by-id | grep nvme`
- **luks_pass**\
  The password to encrypt your drives
- **tpm_pin**\
  The password you will input everytime your machine boots.
- **username**
- **user password**

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
