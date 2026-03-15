#!/bin/bash
set -euo pipefail

# Only run in remote (web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SUPERPOWERS_DIR="${HOME}/.claude/plugins/superpowers"

# Install superpowers plugin if not already installed
if [ ! -d "$SUPERPOWERS_DIR/.git" ]; then
  echo "Installing superpowers plugin..."
  mkdir -p "$(dirname "$SUPERPOWERS_DIR")"
  git clone --depth=1 https://github.com/obra/superpowers.git "$SUPERPOWERS_DIR"
else
  echo "Superpowers plugin already installed, pulling latest..."
  git -C "$SUPERPOWERS_DIR" pull --ff-only origin main || true
fi

# Install Ruby gems
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ -f "Gemfile" ]; then
  echo "Installing Ruby gems..."
  bundle install --quiet 2>&1 || echo "Warning: bundle install failed (non-fatal)"
fi

# Install npm packages
if [ -f "package.json" ]; then
  echo "Installing npm packages..."
  npm install --silent 2>&1 || echo "Warning: npm install failed (non-fatal)"
fi

# Sync superpowers commands and skills into project .claude directory
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
mkdir -p "$PROJECT_DIR/.claude/commands" "$PROJECT_DIR/.claude/skills"
cp -r "$SUPERPOWERS_DIR/commands/"*.md "$PROJECT_DIR/.claude/commands/" 2>/dev/null || true
cp -rT "$SUPERPOWERS_DIR/skills/" "$PROJECT_DIR/.claude/skills/" 2>/dev/null || true

# Run superpowers session-start hook to inject context
if [ -f "$SUPERPOWERS_DIR/hooks/run-hook.cmd" ]; then
  CLAUDE_PLUGIN_ROOT="$SUPERPOWERS_DIR" bash "$SUPERPOWERS_DIR/hooks/run-hook.cmd" session-start 2>/dev/null || true
fi
