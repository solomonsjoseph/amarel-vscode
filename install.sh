#!/usr/bin/env bash
# Install the amarel-vscode-setup skill into ~/.claude/skills/
#
# Run this once after cloning. Re-running is safe (updates the symlink).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="amarel-vscode-setup"
SKILLS_DIR="${HOME}/.claude/skills"
TARGET="${SKILLS_DIR}/${SKILL_NAME}"

mkdir -p "$SKILLS_DIR"

# Remove any prior install (symlink or directory)
if [[ -L "$TARGET" || -e "$TARGET" ]]; then
  echo "→ removing previous install at $TARGET"
  rm -rf "$TARGET"
fi

# Symlink so 'git pull' on the repo updates the installed skill automatically
ln -s "$REPO_DIR" "$TARGET"
echo "✓ Installed: $TARGET → $REPO_DIR"
echo ""
echo "Restart Claude Code, then run:  /${SKILL_NAME}"
