#!/bin/bash

# Ensuring the script fails on errors and unbound variables
set -euo pipefail

# Key assumption on home directory or adaptation to explicit variables
HOME_DIR="${HOME}" # Or replace with `$h` if it's a valid variable

# Read credentials from environment overrides or the KWallet keyring
# provisioned by setup-kwallet (folder pkm, entries hypothesis-username
# and hypothesis-password).
kwallet_value() {
    local entry=$1
    local wallet=${HYPOTHESIS_KWALLET_WALLET:-kdewallet}
    local folder=${HYPOTHESIS_KWALLET_FOLDER:-pkm}

    command -v kwallet-query >/dev/null 2>&1 || return 1
    local value
    if command -v timeout >/dev/null 2>&1; then
        value=$(timeout 10 kwallet-query --folder "$folder" --read-password "$entry" "$wallet" 2>/dev/null) || return 1
    else
        value=$(kwallet-query --folder "$folder" --read-password "$entry" "$wallet" 2>/dev/null) || return 1
    fi
    printf '%s\n' "$value"
}

clean_value() {
    sed -n '1{s/[[:space:]]*$//;p;}' | tr -d '\r'
}

username="${HYPOTHESIS_USERNAME:-}"
if [[ -z "$username" ]]; then
    username=$(kwallet_value hypothesis-username | clean_value) || true
fi
token="${HYPOTHESIS_TOKEN:-}"
if [[ -z "$token" ]]; then
    token=$(kwallet_value hypothesis-password | clean_value) || true
fi

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
  if FJ_PY_PROFILE=fj-py-promnesia.profile ~/bin/fj-py online ~/data/apps/PKM -- ~/data/apps/PKM/.venv/bin/python -m hypexport.export --username "$username" --token "$token" >"$TEMP_FILE"; then
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
