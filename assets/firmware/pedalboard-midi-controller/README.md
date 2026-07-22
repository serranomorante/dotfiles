# Pedalboard MIDI Controller

Arduino Micro firmware for a three-pedal USB MIDI surface.

## Wiring

All pedal sleeves share Arduino `GND`.

```text
switch pedal 1 tip -> D2
switch pedal 2 tip -> D3
continuous pedal tip -> A0
continuous pedal ring -> optional A1, currently unused
```

Do not connect the pedal jacks to `5V`. The firmware uses `INPUT_PULLUP`, and the continuous pedal calibration is based on the observed `A0` range of roughly `30..480`.

The switch pedal inputs are intentionally inverted in firmware for the currently wired normally-closed pedals: resting state emits `0`, and pressing the pedal emits `127`.

## Profiles

Profiles are persisted in EEPROM and can be changed over the Arduino serial port at `115200` baud.

```text
profile piano
profile guitar
profile desktop
status
```

Profiles can also be selected while connecting USB:

```text
hold switch 1 -> guitar
hold switch 2 -> piano
hold both -> desktop
```

The default profile is `piano`.

```text
piano:
  channel 1
  continuous -> CC64 sustain/damper, 0..127
  switch 1 -> CC66 sostenuto, momentary 0/127
  switch 2 -> CC67 soft pedal, momentary 0/127

guitar:
  channel 2
  continuous -> CC4 foot controller, 0..127
  switch 1 -> CC80 stomp A, latched 0/127
  switch 2 -> CC81 stomp B, latched 0/127

desktop:
  channel 16
  continuous -> CC4 foot controller, 0..127
  switch 1 -> CC80 action A, momentary 0/127
  switch 2 -> CC81 action B, momentary 0/127
```

The `desktop` profile is intentionally still plain MIDI. A separate host-side action mapper should translate these events into microphone toggles, scripts, or window actions.

## TFT feedback

`pedalboard-midi-actions` owns the host-side pedalboard state used for desktop actions and display feedback. When it receives pedalboard CC events, it publishes the inferred profile and pedal values to `keyboard-midi-controller` with this command shape:

```text
keyboard-midi-controller pedalboard-state PROFILE CONT SW1 SW2
```

`keyboard-midi-controller` remains the only writer to the TFT serial display. The TFT renders this state on visual channel `15`, labeled `Pedalboard`, so pedalboard feedback stays separate from channel `16` REAPER global utilities.
