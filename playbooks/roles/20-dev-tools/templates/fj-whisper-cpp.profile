# {{ ansible_managed }}
quiet
# whisper.cpp CUDA needs /dev/nvidia* devices, so this profile intentionally
# keeps the real /dev while disabling unrelated desktop device classes below.
include dev-tools-common.inc
ignore private-dev
dbus-user none
noinput
nosound
notv
nou2f
