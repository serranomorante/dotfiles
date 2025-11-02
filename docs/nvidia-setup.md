# NVIDIA setup - Migrate from Optimus Manager to Official method

> Disclaimer: This setup hasn't achieve completely turning off the GPU. The power consumption is perceptibly lower, but the GPU is still active, draining battery power.

> Disclaimer 2: This is a guide for myself, I hope it can be useful to you but I just wrote it to remind me the steps I followed. For example, I'm not explaining how to install the NVIDIA drivers in the first place.

## My specs

```
                   -`                    serranomorante@arch
                  .o+`                   -------------------
                 `ooo/                   OS: Arch Linux x86_64
                `+oooo:                  Host: 82B5 Lenovo Legion 5 15ARH05
               `+oooooo:                 Kernel: 6.1.53-1-lts
               -+oooooo+:                Uptime: 1 hour, 47 mins
             `/:-:++oooo+:               Packages: 1648 (pacman), 15 (flatpak)
            `/++++/+++++++:              Shell: bash 5.1.16
           `/++++++++++++++:             Resolution: 1920x1080
          `/+++ooooooooooooo/`           DE: Plasma 5.27.8
         ./ooosssso++osssssso+`          WM: i3
        .oossssso-````/ossssss+`         Theme: [Plasma], Breeze [GTK2/3]
       -osssssso.      :ssssssso.        Icons: [Plasma], breeze-dark [GTK2/3]
      :osssssss/        osssso+++.       Terminal: zellij
     /ossssssss/        +ssssooo/-       CPU: AMD Ryzen 7 4800H with Radeon Graphics (16) @ 2.900GHz
   `/ossssso+/:-        -:/+osssso+-     GPU: AMD ATI 06:00.0 Renoir
  `+sso+:-`                 `.-/+oso:    GPU: NVIDIA GeForce GTX 1650 Ti Mobile
 `++:.                           `-/+/   Memory: 7017MiB / 31464MiB
 .`                                 `/
```


|Family|Specifics|
|-|-|
|NV160 family (Turing)|NV167 (TU117)	GeForce GTX 1650|

After executing: `pacman -Qs | grep nvidia`

|Installed|Version|
|-|-|
|local/nvidia-lts|1:535.104.05-10|
|local/nvidia-settings|535.104.05-1|
|local/nvidia-prime|1.0-4|
|local/nvidia-prime-rtd3pm|1.0-2|
|local/nvidia-utils|535.104.05-1|
|local/opencl-nvidia-525xx|525.116.04-1|

## Intro

When I migrated from Windows to Linux I never expected the tremendous amount of additional knowledge that decision will bring me. While on Windows most of the things "just work" out-of-the-box... on Linux you have to put an extra effort trying to understand the inner working of your tools and system. I prefer this latter approach.

Trying to use NVIDIA on Linux with a Legion 5 AMD laptop can be a challenge. That's why I decided to start with the [optimus-manager]() package and stick to it for several months. Now I finally decided to make the switch to the official driver setup just for the sake of understanding how things work and also remove more dependencies from my system (`optimus-manager`, `optimus-manager-qt`, `autorandr`, etc...)

## What I have achieved now

Not only have I removed `optimus-manager` and `optimus-manager-qt` as a dependency but also `autorandr`. Sometimes is better not having to worry about extra dependencies that are not under your control.

`Hybrid mode` never worked that well for me when using optimus-manager, I have to admit I never had the time to further test down that issue but I can confirm that it is now solved in my new setup.

Also, `optimus-manager` gave me some problems in the past after a system upgrade (it was due to a wrong python version) but I can vividly remember it was a nightmare to debug.

## Steps I followed

**TL;DR**
> 1. Removed some packages
> 2. Removed the `/etc/X11/xorg.conf.d/90-monitor.conf`
> 3. Edited the `/usr/share/sddm/scripts/Xsetup` script
> 4. Detect monitor plug/unplug
> 4. Installed some packages
> 5. Enable `nvidia-persistence` service
> 6. Add modprobe conf file: `/etc/modprobe.d/nvidia-pm.conf`
> 7. Extract and add a custom EDID to Xorg
> 8. Add kernel parameters
> 9. Generate CVT with 40 refresh rate (this is very important!)

### Remove some packages

I removed `optimus-manager-qt` and `optimus-manager` using `yay -Rns <the package>`.

### Remove `90-monitor.conf` file

I also removed the `/etc/X11/xorg.conf.d/90-monitor.conf` file that had this content:

```bash
Section "Monitor"
        Identifier             "HDMI-0"
        DisplaySize            3440 1440   # In millimeters
EndSection

Section "Device"
        Identifier "HDMI-0"
        # Driver  "nvidia-lts"
        # Option  "NoLogo"         "True"
        # Option  "CoolBits"       "24"
        # Option  "TripleBuffer"   "True"
        # Option  "DPI"            "100x100"
        Option  "UseEdidDpi"     "False"
# find more options in  /usr/share/doc/nvidia/README
EndSection
```

I cannot remember how that file got in there in the first place. If it was auto-generated it doesn't seems to be the case anymore because is **not there** again.

### Edited the `/usr/share/sddm/scripts/Xsetup`

When using `optimus-manager` you must not relay on the `sddm` script called `Xsetup` because `optimus-manager` offers you other scripts to do the same thing. Now that you deleted that package you can go back and edit the `/usr/share/sddm/scripts/Xsetup` with your preferred content:

```bash
#!/bin/sh
# Xsetup - run as root before the login dialog appears

snixembed --fork

internal=$(xrandr | grep "DP.* connected" | cut -d " " -f 1)
external=$(xrandr | grep "HDMI.* connected" | cut -d " " -f 1)

if [[ $external != "" ]]; then
    # Turn off internal screen
    xrandr --output $internal --off

    # Set external monitor as primary
    xrandr --output $external --primary --mode 3440x1440 --rate 59.97

    # Set a max limit on the graphics gpu
    nvidia-smi -lgc 139,300

    # Under-clock the graphics memory
    nvidia-settings -a "GPUMemoryTransferRateOffset[0x3]=-2000" -c :0
else
    xrandr --output $internal --primary --mode 1920x1080 --rate 120.21
fi

# snixembed --fork
```

### Installed some packages

I installed the [xf86-video-amdgpu](https://archlinux.org/packages/?name=xf86-video-amdgpu) package and this was very important to make everything work correctly.

### Enable `nvidia-persistence` service (actually don't as I only have single gpu)

### Add modprobe conf file

I created this file as sudo: `/etc/modprobe.d/nvidia-pm.conf` with the following content:

```bash
options nvidia NVreg_RegistryDwords="RMUseSwI2c=1; OverrideMaxPerf=0x1"
```

It was based on this link: [https://forums.developer.nvidia.com/t/nvidia-turing-1660-ti-forcing-maximum-power-saving-minimum-performance-mode/145573](https://forums.developer.nvidia.com/t/nvidia-turing-1660-ti-forcing-maximum-power-saving-minimum-performance-mode/145573) but in reality it **didn't help a lot** I think.

### Add kernel parameters

I added the following kernel parameters on `/etc/default/grub` and then execute `sudo grub-mkconfig -o /boot/grub/grub.cfg`.

```bash
...
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1 nvidia.NVreg_DynamicPowerManagement=0x01 nvidia.NVreg_RegistryDwords=\"OverrideMaxPerf=1\""
...
```

> `nvidia_drm.modeset=1` is necessary and should not be deleted

> Notice how `OverrideMaxPerf` is duplicated with the previous modprobe conf file. Apparently neither worked.

### Add the following .conf file to Xorg

> `/etc/X11/xorg.conf.d/80-igpu-primary-egpu-offload.conf`

```bash
Section "Device"
    Identifier   "Device0"
    Driver       "modesetting"
    BusID        "PCI:6:0:0"
    # Option     "AsyncFlipSecondaries" "true"
    # Option     "TearFree"             "true"
    # Option     "DRI"                  "1"
EndSection

Section "Device"
    Identifier "Device1"
    Driver     "nvidia"
    BusID      "PCI:1:0:0"                              # Edit according to lspci, translate from hex to decimal.
    Option     "AllowExternalGpus"            "True"    # Required for proprietary NVIDIA driver.
    Option     "Coolbits"                     "8"       # https://us.download.nvidia.com/XFree86/Linux-x86_64/535.104.05/README/index.html
    Option     "AllowPRIMEDisplayOffloadSink" "true"
    Option     "ForceFullCompositionPipeline" "true"
    # Option   "CustomEDID"                   "HDMI-1-0:/etc/X11/edid.bin"
    # Option   "UseEDID"                      "FALSE"
    # Option   "UseEDIDFreqs"                 "FALSE"
    # Option   "UseEDIDDpi"                   "FALSE"
    # Option   "ModeValidation"               "NoEdidModes"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    Monitor        "Monitor0"
    # Option       "GPUPowerMizerMode"            "0"
    # Option       "ForceFullCompositionPipeline" "on"
    # Option       "AllowIndirectGLXProtocol"     "off"
    # Option       "TripleBuffer"                 "on"
EndSection
```

### Handle connect/disconnect of external monitor

tdlr: I created a `udev` rule, a custom script and added a config to my `.bashrc` file.

This fixes the problem with disconnecting (unplugging) my external monitor when I'm on external-only mode.

#### Create the udev rule

> /etc/udev/rules.d/95-monitor-hotplug.rules

```bash
#Rule for executing commands when an external screen is plugged in.
#Credits go to: http://unix.stackexchange.com/questions/4489/a-tool-for-automatically-applying-randr-configuration-when-external-display-is-p

ACTION=="change", SUBSYSTEM=="drm", RUN+="/usr/local/bin/hotplug_monitor.sh"
```

#### Write a custom script

> /usr/local/bin/hotplug_monitor.sh

```bash
#!/bin/sh

echo 'After udev.out'

export XAUTHORITY=/home/serranomorante/.Xauthority
export DISPLAY=:0

internal=$(xrandr | grep "DP.* connected" | cut -d " " -f 1)
external=$(xrandr | grep "HDMI.* connected" | cut -d " " -f 1)

echo 'After xrandr variables'

if [[ $external != "" ]]; then
    # Turn off internal screen
    xrandr --output $internal --off

    # Set external monitor as primary
    xrandr --output $external --primary --mode 3440x1440 --rate 59.97

    # Set a max limit on the graphics gpu
    nvidia-smi -lgc 139,300

    # Under-clock the graphics memory
    nvidia-settings -a "GPUMemoryTransferRateOffset[0x3]=-2000" -c :0
else
    xrandr --output $internal --primary --mode 1920x1080 --rate 120.21
fi

echo 'After conditions'

echo 'After end'
```

#### Add the following lines to .bashrc

> ~/.bashrc

```bash
# Allow script to be executed by udev
# Context: https://stackoverflow.com/a/14263308
# Thanks: https://unix.stackexchange.com/a/10126
case $DISPLAY:$XAUTHORITY in
  :*:?*)
    # DISPLAY is set and points to a local display, and XAUTHORITY is
    # set, so merge the contents of `$XAUTHORITY` into ~/.Xauthority.
    XAUTHORITY=~/.Xauthority xauth merge "$XAUTHORITY";;
esac
```

## Other

This is the output of `nvidia-smi` now:

> Laptop's monitor only


> External monitor only

```bash
Sun Nov  5 23:26:48 2023
+---------------------------------------------------------------------------------------+
| NVIDIA-SMI 545.29.02              Driver Version: 545.29.02    CUDA Version: 12.3     |
|-----------------------------------------+----------------------+----------------------+
| GPU  Name                 Persistence-M | Bus-Id        Disp.A | Volatile Uncorr. ECC |
| Fan  Temp   Perf          Pwr:Usage/Cap |         Memory-Usage | GPU-Util  Compute M. |
|                                         |                      |               MIG M. |
|=========================================+======================+======================|
|   0  NVIDIA GeForce GTX 1650 Ti     Off | 00000000:01:00.0  On |                  N/A |
| N/A   38C    P8               3W /  50W |     94MiB /  4096MiB |     44%      Default |
|                                         |                      |                  N/A |
+-----------------------------------------+----------------------+----------------------+
                                                                                         
+---------------------------------------------------------------------------------------+
| Processes:                                                                            |
|  GPU   GI   CI        PID   Type   Process name                            GPU Memory |
|        ID   ID                                                             Usage      |
|=======================================================================================|
|    0   N/A  N/A       821      G   /usr/lib/Xorg                                93MiB |
+---------------------------------------------------------------------------------------+
```

This is the output of `htop` filtering `"Xorg"` now:

> External monitor only

```bash
  [Main] [I/O]
    PID USER       PRI  NI  VIRT   RES   SHR S  CPU%▽MEM%   TIME+  Command
  23996 serranomor  20   0 11904  8064  3568 R  29.6  0.0  0:00.17 htop -F Xorg
    821 root        20   0 25.8G  234M  162M S   0.0  0.7  1:40.34 /usr/lib/Xorg
    848 root        20   0 25.8G  234M  162M S   0.0  0.7  0:06.83 /usr/lib/Xorg
    849 root        39  19 25.8G  234M  162M S   0.0  0.7  0:00.00 /usr/lib/Xorg
    850 root        20   0 25.8G  234M  162M S   0.0  0.7  0:00.00 /usr/lib/Xorg
    851 root        39  19 25.8G  234M  162M S   0.0  0.7  0:00.00 /usr/lib/Xorg
    856 root        20   0 25.8G  234M  162M S   0.0  0.7  0:03.46 /usr/lib/Xorg
    857 root        20   0 25.8G  234M  162M S   0.0  0.7  0:00.00 /usr/lib/Xorg
    858 root        20   0 25.8G  234M  162M S   0.0  0.7  0:00.00 /usr/lib/Xorg
    860 root        20   0 25.8G  234M  162M S   0.0  0.7  0:02.80 /usr/lib/Xorg
   1032 root        20   0 25.8G  234M  162M S   0.0  0.7  0:00.00 /usr/lib/Xorg
   1051 root        39  19 25.8G  234M  162M S   0.0  0.7  0:00.01 /usr/lib/Xorg
```

This is the output of `lspci | grep -e VGA -e 3D`

> External monitor only

```bash
01:00.0 VGA compatible controller: NVIDIA Corporation TU117M [GeForce GTX 1650 Ti Mobile] (rev a1)
06:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Renoir (rev c6)
```

This is the output of `glxinfo | grep -i "opengl renderer"`

> External monitor only

```bash
OpenGL renderer string: AMD Radeon Graphics (renoir, LLVM 16.0.6, DRM 3.49, 6.1.61-1-lts)
```

This is the output of `xrandr --listproviders`

> External monitor only

```bash
Providers: number : 2
Provider 0: id: 0x43 cap: 0xf, Source Output, Sink Output, Source Offload, Sink Offload crtcs: 4 outputs: 1 associated providers: 1 name:modesetting
Provider 1: id: 0x278 cap: 0x2, Sink Output crtcs: 4 outputs: 4 associated providers: 1 name:NVIDIA-G0
```

## Resources

- [Getting HDMI output to work with switchable graphics with an integrated AMD GPU and discrete Nvidia GPU on Arch Linux (i.e. reverse PRIME) - Has anyone had success with this?](https://www.reddit.com/r/LenovoLegion/comments/118x2je/getting_hdmi_output_to_work_with_switchable/)
- [Configuring reverse PRIME for integrated AMD GPU and discrete Nvidia GPU](https://www.reddit.com/r/archlinux/comments/1128dy0/configuring_reverse_prime_for_integrated_amd_gpu/)
- [Xorg rendered on iGPU, PRIME render offload to eGPU](https://wiki.archlinux.org/title/External_GPU#Xorg_rendered_on_iGPU,_PRIME_render_offload_to_eGPU)
- [Saving overclocking settings](https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks#Saving_overclocking_settings)

## Useful commands

```bash
# Look for the current nvidia? performance level setting
# output: auto

cat /sys/class/drm/card*/device/power_dpm_force_performance_level

# Look for the Mhz of card* (nvidia?)
# output: 
# 2: 400Mhz
# 3: 1600Mhz *

cat /sys/class/drm/card*/device/pp_dpm_mclk

# Your xorg logs
# output: ... too large ...

cat /var/log/Xorg.0.log

# Apply your changes in the grub file

sudo grub-mkconfig -o /boot/grub/grub.cfg^C
```

