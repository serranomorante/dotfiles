# Keyboard MIDI TFT Display

ESP32-S3 + ILI9341 TFT renderer for the keyboard MIDI controller and related feedback surfaces.

## Serial protocol

The display receives line-oriented serial commands from `keyboard-midi-controller` at `115200` baud.

```text
S <active> <channel> <bank> <transport_running>
N <note> <velocity>
P <channel> <note> <velocity>
K <channel> <cc> <value>
B <profile> <continuous> <switch1> <switch2>
C
```

`S` selects the visual channel/bank and updates MIDI mode plus transport state. `N`, `P`, and `K` render local and DAW feedback from the keyboard MIDI controller/ReaLearn flow. `B` renders pedalboard state; profile values are `0=unknown`, `1=piano`, `2=guitar`, and `3=desktop`. `C` clears cached note/CC state and redraws.

## Pedalboard channel

Visual channel `15` is reserved for the pedalboard. Its header shows `Ch 15 Pedalboard` plus the current profile, and its first row renders the core pedal state:

```text
PROF  DAMP  SW1  SW2
```

This channel is intentionally separate from channel `16`, which is reserved for REAPER global utilities such as panic, save, mixer, routing, and action-list controls.
