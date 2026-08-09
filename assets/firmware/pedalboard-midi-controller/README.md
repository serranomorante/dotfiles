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

The continuous pedal is filtered in firmware before emitting MIDI. The raw `A0` reading is first mapped through a configurable physical range: by default `range 15 60` maps the first 15% of the observed analog range to MIDI `0`, maps 60% and above to MIDI `127`, and scales the middle linearly. This handles the current damper pedal's noisy release end and its practical full-press point without needing extra pressure to reach 100%.

After range mapping, each value is averaged from eight analog samples, changes smaller than two MIDI steps are not emitted, and a direction change is only accepted after three opposite-direction reads at least six MIDI values away from the current stable value. Accepted movement is slew-limited to four MIDI values per poll so confirmed reversals do not jump directly to a noisy candidate, while endpoint values reset trend tracking so fully released/pressed states remain reliable. This keeps gradual pedal movement monotonic enough for the TFT and DAW while still allowing real direction changes when the pedal is released or pressed further.

## Profiles

Profiles are persisted in EEPROM and can be changed over the Arduino serial port at `115200` baud.

```text
profile piano
profile guitar
profile desktop
profile obs-mouseless-setup
status
range 15 60
range reset
```

Profiles can also be selected while connecting USB:

```text
hold switch 1 -> guitar
hold switch 2 -> piano
hold both -> desktop
```

The default profile is `piano`.

From the host, use `pedalboard-midi-profile` instead of opening the serial port manually:

```text
pedalboard-midi-profile status
pedalboard-midi-profile piano
pedalboard-midi-profile guitar
pedalboard-midi-profile desktop
pedalboard-midi-profile obs-mouseless-setup
pedalboard-midi-profile range 15 60
pedalboard-midi-profile range reset
```

The range command is persisted in EEPROM. `range ZERO FULL` expects percentages from `0..100`, with `ZERO < FULL` and a minimum five-point gap. Use `pedalboard-midi-profile range reset` to return to the firmware default `15 60`.

The helper sends the serial command to the Arduino, prints the firmware status line, and publishes the resulting profile/value to the TFT through `keyboard-midi-controller`.

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

obs-mouseless-setup:
  channel 15
  continuous -> CC4 foot controller, 0..127
  switch 1 -> CC80 OBS scene toggle, momentary 0/127
  switch 2 -> CC81 auxiliary OBS action, momentary 0/127
```

The `desktop` and `obs-mouseless-setup` profiles are intentionally still plain MIDI. Separate host-side action mappers translate these events into microphone toggles, scripts, OBS scene changes, or window actions.

Host-side action mapper profiles run as `pedalboard-midi-actions@<profile>.service` instances backed by `pedalboard-midi-actions.<profile>.tsv`; `pedalboard-midi-profile desktop` starts `@desktop`, `pedalboard-midi-profile obs-mouseless-setup` starts `@obs-mouseless-setup`, and instrument-only profiles start a feedback-only `@piano`/`@guitar` instance that publishes TFT state without host actions.

## TFT feedback

`pedalboard-midi-actions` owns the host-side pedalboard state used for desktop actions and display feedback. When it receives pedalboard CC events, it publishes the inferred profile and pedal values to `keyboard-midi-controller` with this command shape:

```text
keyboard-midi-controller pedalboard-state PROFILE CONT SW1 SW2
```

`keyboard-midi-controller` remains the only writer to the TFT serial display. The TFT renders this state on visual channel `15`, labeled `Pedalboard`, so pedalboard feedback stays separate from channel `16` REAPER global utilities. In the `desktop` profile, `desktop-state-monitor` publishes stable action slots alongside the physical pedal state: tile 1 is `MODE`, tile 2 is `MIC`, tile 3 is `SHOT`, tile 4 is `REC`, and tile 5 is `MON`; tiles 4 and 5 draw a modifier dot because they are triggered by holding the continuous pedal while pressing pedals 2 or 3. The modifier dot is grey in `MODE BASE` and yellow in `MODE SHIFT`. `pedalboard-midi-actions` emits `desktop.layer` only when the continuous pedal crosses the base/shift threshold, and `desktop-state-monitor` updates only the `MODE` slot for that transition, avoiding redundant TFT serial updates during continuous pedal movement. The TFT redraws the full `MODE` tile plus only the two modifier dots for a base/shift transition. Script-backed desktop actions show `BUSY` immediately from `desktop.action START ACTION`, then the real subsystem state replaces it when the PipeWire, screenshot, recording, or display event arrives. `SHOT` is rendered as momentary feedback: screenshot `BUSY` appears while Spectacle runs, then `SAVED` or `ERROR` flashes briefly and returns to `READY`.

The `pedalboard-midi-actions` listener supervises `aseqdump` and uses a low-frequency visibility check against `aseqdump -l`, so changing the Arduino USB cable or port should trigger an automatic listener reconnect without subscribing to noisy global ALSA sequencer events. `PEDALBOARD_MIDI_RECONNECT_DELAY` controls the retry/check delay in seconds and defaults to `2`.
