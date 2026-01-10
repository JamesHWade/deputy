#!/bin/bash

# Only run in remote/web environments
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  exit 0
fi

echo "Installing R and Air..."

# Install R
sudo apt-get update -qq
sudo apt-get install -y -qq r-base r-base-dev

# Install Air (R formatter from Posit)
# Download first, then execute (safer than curl|sh)
air_installer="/tmp/air-installer.sh"
if curl -LsSf https://github.com/posit-dev/air/releases/latest/download/air-installer.sh -o "$air_installer"; then
  chmod +x "$air_installer"
  "$air_installer"
  rm -f "$air_installer"
else
  echo "Warning: Failed to download Air installer" >&2
fi

# Persist PATH for subsequent bash commands in this session
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
fi

echo "R $(R --version | head -1) installed"
echo "Air installed at ~/.local/bin/air"
