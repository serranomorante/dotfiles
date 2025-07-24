#!/bin/sh

sleep 1

internal=$(xrandr | grep "DP.* connected" | cut -d " " -f 1 | sed -n '1p') # first match only
external=$(xrandr | grep "HDMI.* connected" | cut -d " " -f 1)
if [[ $external == "" ]]; then
   # In case usb-c is connected
   external=$(xrandr | grep "DP.* connected" | cut -d " " -f 1 | sed -n '2p') # try a second match
fi

xrandr --newmode "1920x1080f"   285.00   1920 2028 2076 2076   1080 1090 1100 1142 -hsync -vsync
xrandr --addmode $internal "1920x1080f"
xrandr --output $internal --primary --mode "1920x1080f" --rate 120.21
# xrandr --output $internal --set "PRIME Synchronization" 1

if [[ $external != "" ]]; then
   xrandr --output $external --mode 3440x1440 --rate 59.97 --right-of $internal --brightness 0.5
   # Notify the system
   /usr/bin/notify-send "[external] $external connected"
   # Under-clock the graphics memory to save energy
   # nvidia-settings -a "GPUMemoryTransferRateOffset[0x3]=-2000" -c $DISPLAY
else
   external=$(xrandr --listmonitors | grep -Po "\d:\s\+\K[^\s*]+")
   if [[ $external != "" ]]; then
      /usr/bin/notify-send "[external] $external disconnected"
      xrandr --output $external --off
   fi
fi

# Reset wallpaper
/usr/bin/feh --bg-scale --recursive --verbose --randomize ~/.wallpapers/
# Re-apply wacom config
wacom-config.sh
