# {{ ansible_managed }}
quiet
# Interactive Python shells need the real /dev/pts terminal. The generic
# dev-tools profile uses private-dev for stronger device isolation, which is
# fine for non-interactive tooling but breaks tty/stty/job-control behavior.
ignore private-dev
keep-shell-rc
include fj-py.profile
