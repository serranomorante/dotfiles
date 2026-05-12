# {{ ansible_managed }}
quiet
# Piper HTTP server profile. The service launches this through fj-py offline,
# which creates a network namespace with only loopback. The stable sandbox name
# lets piper-say join the same namespace for local HTTP requests.
name piper-tts
include fj-py.profile
