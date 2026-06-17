# {{ ansible_managed }}
quiet
# Promnesia/HPI runtime profile. The wrapper selects the network mode per
# caller; this profile exposes only the PKM sources and writable runtime data
# that Promnesia and HPI exporters need.
include fj-py.profile

whitelist-ro ${HOME}/.config/my
whitelist-ro ${HOME}/.config/promnesia
# Promnesia config is stowed: ~/.config/promnesia/config.py points here.
whitelist-ro ${HOME}/dotfiles/PKM/dot-config/promnesia
whitelist-ro ${HOME}/data/notes/foam
whitelist-ro ${HOME}/data/repos/HPI

whitelist ${HOME}/data/PKM/data
whitelist ${HOME}/.local/share/promnesia
