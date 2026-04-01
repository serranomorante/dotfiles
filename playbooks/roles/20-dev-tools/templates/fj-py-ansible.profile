# {{ ansible_managed }}
quiet
# Ansible pip profile: inherit the generic Python runtime policy and let the
# wrapper provide the target venv root plus any explicit overrides.
include fj-py.profile
