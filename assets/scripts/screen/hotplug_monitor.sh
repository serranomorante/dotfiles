#!/bin/sh

exec >{{ ansible_env.HOME }}/udev.out 2>&1

export XAUTHORITY={{ ansible_env.HOME }}/.Xauthority
export DISPLAY=:0

user_id=$(id -u {{ ansible_env.USER }})
internal=$(xrandr | grep "DP.* connected" | cut -d " " -f 1 | sed -n '1p') # first match only
external=$(xrandr | grep "HDMI.* connected" | cut -d " " -f 1)
if [[ $external == "" ]]; then
   # In case usb-c is connected
   external=$(xrandr | grep "DP.* connected" | cut -d " " -f 1 | sed -n '2p') # try a second match
fi

xrandr --output $internal --primary --mode 1920x1080 --rate 120.21 --brightness 0.5

if [[ $external != "" ]]; then
   xrandr --output $external --mode 3440x1440 --rate 59.97 --right-of $internal --brightness 0.5
   # Notify the system
   sudo -u {{ ansible_env.USER }} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user_id/bus /usr/bin/notify-send "[external] $external connected"
   # Set a max limit on the graphics gpu to save energy
   nvidia-smi -lgc 139,300
   # Under-clock the graphics memory to save energy
   nvidia-settings -a "GPUMemoryTransferRateOffset[0x3]=-2000" -c :0
else
   external=$(xrandr --listmonitors | grep -Po "\d:\s\+\K[^\s*]+")
   if [[ $external != "" ]]; then
      xrandr --output $external --off
   fi
fi

# Notify the system
sudo -u {{ ansible_env.USER }} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$user_id/bus /usr/bin/notify-send "[internal] $internal connected"
# Reset wallpaper
sudo -u {{ ansible_env.USER }} /usr/bin/feh --bg-scale --recursive --verbose --randomize {{ ansible_env.HOME }}/.wallpapers/
