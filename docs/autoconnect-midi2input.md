# Autoconnect midi2input

```bash
#!/bin/sh

sleep 2

midi_client_id=$(aconnect -i | grep "'APC mini mk2'" | cut -d " " -f 2)
midi_contr=0
midi2input_client_id=$(aconnect -i | grep "'midi2input_alsa'" | cut -d " " -f 2)
midi2input_in=0
midi2input_out=1

aconnect "${midi_client_id}${midi_contr}" "${midi2input_client_id}${midi2input_in}"
aconnect "${midi2input_client_id}${midi2input_out}" "${midi_client_id}${midi_contr}"
```

```bash
# https://github.com/stevelittlefish/auto_midi_connect/blob/master/100-usb.rules
ACTION=="change", SUBSYSTEM=="usb", DRIVER=="usb", RUN+="/usr/local/bin/midi_connect.sh"
```
