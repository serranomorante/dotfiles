# Disable internal keyboard with libinput and keyd

I have always wanted to find a way to disable my laptop's built-in keyboard so I can be able to put my external keyboard on top of it without accidentally pressing/holding down any keys. Somehow this has always being a difficult topic because non of the more conventional solutions worked for me, what ended up working was using libinput based on this guide to [disable the touchscreen](https://wiki.archlinux.org/title/Dell_XPS_13_(9343)#Disable_the_touchscreen).

I basically followed those steps from the guide in combination with excluding the built-in keyboard from `keyd` configuration.

```bash
sudo libinput list-devices
```

This resulted in the following output:

```text
Device:           AT Translated Set 2 keyboard
Kernel:           /dev/input/eventXX

Device:           ITE Tech. Inc. ITE Device(8910) Keyboard
Kernel:           /dev/input/eventXX

Device:           Ideapad extra buttons
Kernel:           /dev/input/eventXX

Device:           keyd virtual keyboard
Kernel:           /dev/input/eventXX
...

Device:           keyd virtual pointer
Kernel:           /dev/input/eventXX
...

Device:           VEIKK Pen
Kernel:           /dev/input/eventXX
...

Device:           VEIKK Keyboard
Kernel:           /dev/input/eventXX
...
```

The output was much much larger, but I could guess that `AT Translated Set 2 keyboard` and `ITE Tech. Inc. ITE Device(8910) Keyboard` corresponded somehow to my keyboard so I create the following file and content:

```bash
# First I created the file

sudo touch /etc/udev/rules.d/99-disable_internal_keyboard.rules

# Then I added the content

KERNEL=="event*", ATTRS{name}=="AT Translated Set 2 keyboard", ENV{LIBINPUT_IGNORE_DEVICE}="1"
KERNEL=="event*", ATTRS{name}=="ITE Tech. Inc. ITE Device(8910) Keyboard", ENV{LIBINPUT_IGNORE_DEVICE}="1"
KERNEL=="event*", ATTRS{name}=="Ideapad extra buttons", ENV{LIBINPUT_IGNORE_DEVICE}="1"
```

> Forget about "Ideapad extra buttons" I was just testing my luck

You will then reboot your system and usually everything should work except it didn't! My internal keyboard was still working flawlesly as if nothing happened. After further debugging I realized that `keyd` was somehow interfering with the solution so I also disabled `keyd virtual keyboard` only to find out that after non of my keyboards worked at all, not by bluetooth, dongle or cable! Please don't do this!

> I has to chroot with a bootable usb to undo all my mess.

Later I realized that `keyd` offers a configuration to ignore(?) the devices you specificy, I thought that might help me to fix the interference between `keyd` and `libinput`. So I did the following:

I executed `sudo keyd monitor` to find the id of my laptops internal keyboard and then I added this to my `keyd` config:

```dotini
[ids]

*
-xxxx:xxxx
-xxxx:xxxx

[main]
...
```

> You should replace those `xxxx:xxxx` with the ones you found after executing the `monitor` command.

Then after I restarted, finally, every other keyboard was working except for my laptop built-in keyboard!

Now the next challenge is finding a way for my external keyboard to not get damaged by the temperatura of my laptop.

