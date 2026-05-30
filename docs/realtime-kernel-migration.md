# Realtime Kernel Migration

This workstation can migrate from `linux-lts` to `linux-rt-lts` without reinstalling. Keep `linux-lts` and `linux-lts-headers` installed as the fallback boot path, add `linux-rt-lts` and `linux-rt-lts-headers`, and use DKMS-backed kernel modules for hardware that must work on both kernels.

## Secure Boot And TPM

Secure Boot does not need to be disabled for this migration when the existing `sbctl` keys are already enrolled. The new RT UKI must be generated and signed before booting it, but `sbctl sign -s` can do that while Secure Boot remains enabled.

Do not reset or re-enroll Secure Boot keys as part of this migration. The encrypted setup binds LUKS TPM unlocks to PCR 7 plus PCR 15 states, and changing the Secure Boot key database changes PCR 7. Installing and signing another UKI with the already enrolled key should not require LUKS TPM re-enrollment because the Secure Boot policy stays the same.

The pre-hibernation setup used on the current machine has hibernation disabled and uses one normal userspace TPM enrollment for swap and home. The realtime migration does not need to change LUKS slots, crypttab, fstab, or hibernation state.

## Kernel Modules

`nvidia-open-lts` is built for Arch's `linux-lts` package. The realtime kernel needs `nvidia-open-dkms` so the open NVIDIA kernel module is built for every installed kernel that has headers available.

VirtualBox host modules need the same treatment. Use `virtualbox-host-dkms`, not `virtualbox-host-modules-lts`, so host modules build for `linux-rt-lts` as well as the fallback `linux-lts` kernel. The migration masks `/usr/lib/modules-load.d/virtualbox-host-dkms.conf` through `/etc/modules-load.d/virtualbox-host-dkms.conf -> /dev/null` because `vboxdrv` can trigger scheduler BUG warnings on `PREEMPT_RT`; load those modules manually only when you intentionally use VirtualBox, preferably from the fallback `linux-lts` boot.

`linux-rt-lts` itself provides `VIRTUALBOX-GUEST-MODULES`, which satisfies the guest-utils dependency path. Host support still needs the DKMS host module package when running VirtualBox guests on the workstation.

## Boot Flow

The install uses systemd-boot with UKIs under `/boot/EFI/Linux/`. The migration playbook rewrites the `linux-rt-lts` mkinitcpio preset to use `/boot` instead of `/efi`, runs `mkinitcpio --allpresets`, saves the LTS and RT UKIs in the `sbctl` signing database, signs any unsigned `/boot` EFI files reported by `sbctl verify`, regenerates the presets once more so the signed UKIs are fresh, verifies that no `/boot` file remains unsigned, masks VirtualBox host module autoloading, and installs any migration DKMS entries that were left in a built-only state.

After the playbook succeeds, reboot and select the `linux-rt-lts` UKI from systemd-boot. Keep the existing `linux-lts` entry available until NVIDIA, audio, display switching, and VirtualBox have been tested on the RT kernel.

## Expected Side Effects

The audio stack is already mostly prepared for RT use: `realtime-privileges`, `rtirq`, `cpupower`, PipeWire/JACK, the `realtime` group membership, and `threadirqs` are managed by the audio role. The audio role prioritizes generic USB IRQ handlers before HDA audio because this workstation's USB interface is attached through an `xhci_hcd` IRQ that `rtirq` does not reliably discover through its `snd-usb` helper path. Keep low PipeWire/JACK latency launcher-scoped through `pipewire_latency_vars`; do not set `node.force-quantum` or `node.latency` in global JACK config unless every JACK client should inherit it. Full `PREEMPT_RT` still cannot make the NVIDIA driver realtime-safe, so xruns can still happen under display or GPU load.

The NVIDIA display workflow should remain functionally the same because the userspace packages, Xorg offload config, SDDM `Xsetup`, `nvidia-prime-rtd3pm`, and `/etc/cmdline.d/video.conf` are unchanged. The higher-risk part is DKMS build success for the open module against the RT headers.

VirtualBox host modules are deliberately not autoloaded after the migration. `virtualbox-host-dkms` remains installed and built for both kernels, but `vboxdrv` has shown scheduler BUG warnings on the RT kernel. For VirtualBox work, boot `linux-lts` and load the modules explicitly with `modprobe vboxdrv vboxnetadp vboxnetflt` before starting VMs.
