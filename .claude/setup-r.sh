#!/bin/bash

# Only run in remote/web environments
if [ "$CLAUDE_CODE_REMOTE" != "true" ]; then
  exit 0
fi

echo "Installing R and Air..."

# Install R and common development packages via apt
# Note: CRAN is not in the Claude Code web allowlist, so we use apt packages
# and install remaining dependencies from GitHub
apt-get update -qq
apt-get install -y -qq \
  r-base \
  r-base-dev \
  r-cran-devtools \
  r-cran-testthat \
  r-cran-cli \
  r-cran-rlang \
  r-cran-r6 \
  r-cran-digest \
  r-cran-remotes \
  r-cran-roxygen2 \
  r-cran-knitr \
  r-cran-rmarkdown

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

# Install R packages from GitHub that aren't available via apt
# (CRAN is blocked in Claude Code web environments)
echo "Installing R packages from GitHub..."

install_from_github() {
  local repo="$1"
  local name="$2"
  local tarball="/tmp/${name}.tar.gz"

  echo "  Installing ${name}..."
  if curl -LSsf -o "$tarball" "https://github.com/${repo}/archive/refs/heads/main.tar.gz"; then
    cd /tmp && tar -xzf "$tarball" && R CMD INSTALL "${name}-main" --quiet 2>/dev/null
    rm -rf "/tmp/${name}-main" "$tarball"
  else
    echo "  Warning: Failed to install ${name}" >&2
  fi
}

# Install dependencies in order (httr2 -> S7 -> coro -> ellmer)
install_from_github "r-lib/httr2" "httr2"
install_from_github "RConsortium/S7" "S7"
install_from_github "r-lib/coro" "coro"
install_from_github "tidyverse/ellmer" "ellmer"

# Persist PATH for subsequent bash commands in this session
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
fi

echo "R $(R --version | head -1) installed"
echo "Air installed at ~/.local/bin/air"
