# {{ ansible_managed }}
# Shared hardening baseline for all dev-tool sandboxes.
# Keep profile-specific filesystem access and user-session D-Bus rules
# in the top-level profiles so their intent stays readable.
caps.drop all
seccomp
# Hide host device nodes and give each sandbox a private /tmp.
private-dev
private-tmp
# Block the system bus here; top-level profiles decide whether the user bus
# should also be hidden.
dbus-system none
