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

# An optional third argument installs a specific commit instead of main.
install_from_github() {
  local repo="$1"
  local name="$2"
  local ref="${3:-}"
  local tarball="/tmp/${name}.tar.gz"
  local url="https://github.com/${repo}/archive/refs/heads/main.tar.gz"
  local dir="${name}-main"
  if [ -n "$ref" ]; then
    url="https://github.com/${repo}/archive/${ref}.tar.gz"
    dir="${name}-${ref}"
  fi

  echo "  Installing ${name}${ref:+ at ${ref}}..."
  if curl -LSsf -o "$tarball" "$url"; then
    cd /tmp && tar -xzf "$tarball" && R CMD INSTALL "$dir" --quiet 2>/dev/null
    rm -rf "/tmp/${dir}" "$tarball"
  else
    echo "  Warning: Failed to install ${name}" >&2
  fi
}

# coro is pinned by DESCRIPTION's Remotes field (ADR-0004, #192). Read the
# commit from there so remote sessions test the same revision as CI.
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
coro_ref="$(sed -n 's|^[[:space:]]*r-lib/coro@\([0-9a-f]\{40\}\).*|\1|p' "${project_dir}/DESCRIPTION" 2>/dev/null | head -1)"
if [ -z "$coro_ref" ]; then
  echo "  Warning: coro pin not found in DESCRIPTION; installing coro main" >&2
fi

# Install dependencies in order (httr2 -> S7 -> coro -> ellmer)
install_from_github "r-lib/httr2" "httr2"
install_from_github "RConsortium/S7" "S7"
install_from_github "r-lib/coro" "coro" "$coro_ref"
install_from_github "tidyverse/ellmer" "ellmer"

# Persist PATH for subsequent bash commands in this session
if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$CLAUDE_ENV_FILE"
fi

echo "R $(R --version | head -1) installed"
echo "Air installed at ~/.local/bin/air"
