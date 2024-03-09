#
# ~/.bash_profile
#

# If running bash
# Tmux uses a login shell by default.
if [ -n "$BASH_VERSION" ]; then
  # include .bashrc if it exists
  if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
  fi
fi

# credentials
if [ -f "$HOME/.credsrc" ]; then
  . "$HOME/.credsrc"
fi

# Moved from `.bashrc` here because of `babelfish` incompatibility
PS1='[\u@\h \W]\$ '

# Allow script to be executed by udev
# Context: https://stackoverflow.com/a/14263308
# Thanks: https://unix.stackexchange.com/a/10126
case $DISPLAY:$XAUTHORITY in
  :*:?*)
    # DISPLAY is set and points to a local display, and XAUTHORITY is
    # set, so merge the contents of `$XAUTHORITY` into ~/.Xauthority.
    XAUTHORITY=~/.Xauthority xauth merge "$XAUTHORITY";;
esac
