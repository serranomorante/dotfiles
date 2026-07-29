# Pedalboard MIDI

Pedalboard MIDI profile metadata is centralized in `audio/dot-local/share/dotfiles/pedalboard-midi-profiles.tsv`; host tools should query it through `pedalboard-midi-profiles` instead of hardcoding profile names, channels, CCs, aliases, action-mapper units, or TFT IDs.

`pedalboard-midi-profile` changes the Arduino profile over serial and starts only the host action mapper declared by the selected TSV row. `pedalboard-midi-actions` loads the same TSV at startup to publish TFT state from incoming CC events.

Firmware still embeds the profile table because the Arduino cannot read the host TSV at runtime; update the firmware table and TFT label/ID handling alongside the TSV, and keep tests checking those contracts together.

`Ctrl+Alt+B` and `Ctrl+AltGr+B` open `pedalboard-midi-profile-picker` through keyd, using the same Kitty/fzf quick-access style as snippets and Vim registers.
