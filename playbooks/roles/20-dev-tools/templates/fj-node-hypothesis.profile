# {{ ansible_managed }}
quiet
# Hypothesis development services are Node/Python mixed make targets. They need
# the managed toolchains plus repo-local writes; fj-node supplies the repo root.
include fj-node.profile

whitelist-ro ${HOME}/.pyenv
whitelist-ro ${HOME}/data/repos/client
whitelist-ro ${HOME}/data/repos/hypothesis-extension
whitelist ${HOME}/data/repos/h
whitelist ${HOME}/data/repos/bouncer
