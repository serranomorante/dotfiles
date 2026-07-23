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
D <slot> <label> <value>
C
```

`S` selects the visual channel/bank and updates MIDI mode plus transport state. `N`, `P`, and `K` render local and DAW feedback from the keyboard MIDI controller/ReaLearn flow. `B` renders pedalboard state; profile values are `0=unknown`, `1=piano`, `2=guitar`, and `3=desktop`. `D` renders semantic desktop action feedback for pedalboard slots `0..4`; labels and values are short whitespace-free tokens such as `MIC MUTED` or `MIC LIVE`. `C` clears cached note/CC state and redraws.

## Pedalboard channel

Visual channel `15` is reserved for the pedalboard. Its header shows `Ch 15 Pedalboard` plus the current profile, and its first row renders the pedal surface:

```text
DAMP/SOST/SOFT/SOST*/SOFT*
EXP/STMPA/STMPB/STMPA*/STMPB*
CTRL/ACT A/ACT B/ACT A*/ACT B*
```

The exact labels depend on the active profile. The profile itself is shown in the header, not duplicated in a tile. The first three tiles are the physical pedals; tiles four and five mirror pedals two and three on the continuous-pedal modifier layer, use `2` and `3` as their small physical pedal labels, and draw a corner dot to show that they require the modifier. In the desktop profile the dot is grey in `MODE BASE` and yellow only in `MODE SHIFT`.

In the `desktop` profile, host-side system feedback replaces the generic action labels with semantic state from the real subsystem. `desktop-state-monitor` publishes stable action slots: `0=MODE`, `1=MIC`, `2=SHOT`, `3=REC`, and `4=MON`. `MODE BASE` or `MODE SHIFT` owns tile 1 in the desktop profile, so that tile does not fall back to the continuous pedal percentage. `pedalboard-midi-actions` emits `desktop.layer` only when the continuous pedal crosses the base/shift threshold, and the monitor updates only slot `0` for that layer transition so the TFT does not queue redundant full-row refreshes while the pedal moves. The TFT redraws the full `MODE` tile plus only the modifier dots on tiles four and five for this transition. For script actions, `desktop-action-run` emits `desktop.action START ACTION` immediately and the monitor publishes `BUSY` to the matching tile until the real subsystem event arrives. For example, it watches PipeWire default-source events and asks `keyboard-midi-controller` to forward `D 1 MIC MUTED` or `D 1 MIC LIVE`, so the second tile shows microphone state even when the mute was toggled outside the pedalboard. `SHOT` is momentary feedback: `BUSY` appears while Spectacle runs, then `SAVED` or `ERROR` flashes briefly and the display returns the tile value to `READY`, so screenshots do not look like a latched action.

This channel is intentionally separate from channel `16`, which is reserved for REAPER global utilities such as panic, save, mixer, routing, and action-list controls.
