#!/bin/bash

# Ensuring the script fails on errors and unbound variables
set -euo pipefail

# Key assumption on home directory or adaptation to explicit variables
HOME_DIR="${HOME}" # Or replace with `$h` if it's a valid variable

# Decrypt credentials
username=$(gpg --decrypt "${HOME_DIR}/data/secrets/hypothesis_username.gpg" 2>/dev/null || {
  echo "Failed to decrypt username."
  exit 1
})
token=$(gpg --decrypt "${HOME_DIR}/data/secrets/hypothesis_token.gpg" 2>/dev/null || {
  echo "Failed to decrypt token."
  exit 1
})

# Function to get timestamp
timestamp() {
  date +'%Y-%m-%d_%H-%M-%S'
}

# If both credentials are available, perform export
if [[ -n $username && -n $token ]]; then
  JSON_DIR="${HOME_DIR}/data/PKM/data/highlights"
  mkdir -p "$JSON_DIR" # Ensure that the target directory exists
  EXPORT_FILE="$JSON_DIR/hypothesis.$(timestamp).json"
  TEMP_FILE="$(mktemp)" # Create a temporary file

  # Redirect output to the temporary file
  if ~/data/apps/PKM/.venv/bin/python -m hypexport.export --username "$username" --token "$token" >"$TEMP_FILE"; then
    mv "$TEMP_FILE" "$EXPORT_FILE"
    echo "Export completed successfully and written to $EXPORT_FILE"
  else
    echo "Export failed."
    rm -f "$TEMP_FILE" # Remove the temporary file in case of failure
    exit 1
  fi
else
  echo "Username or token is missing. Aborting."
  exit 1
fi
