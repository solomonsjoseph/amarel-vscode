#!/usr/bin/env bash
# Install the amarel-vscode-setup skill into local agent skill directories.
#
# Run this once after cloning. Re-running is safe (updates the symlink).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="amarel-vscode-setup"

install_skill_link() {
  local agent_name="$1"
  local skills_dir="$2"
  local target="${skills_dir}/${SKILL_NAME}"

  mkdir -p "$skills_dir"

  # Remove any prior install (symlink or directory)
  if [[ -L "$target" || -e "$target" ]]; then
    echo "→ removing previous ${agent_name} install at $target"
    rm -rf "$target"
  fi

  # Symlink so 'git pull' on the repo updates the installed skill automatically
  ln -s "$REPO_DIR" "$target"
  echo "✓ Installed for ${agent_name}: $target → $REPO_DIR"
}

install_skill_link "Claude Code" "${HOME}/.claude/skills"
install_skill_link "Codex" "${HOME}/.codex/skills"

echo ""
echo "Restart Claude Code or Codex so it reloads local skills."
echo "Claude Code command:  /${SKILL_NAME}"
echo "Codex: ask it to set up VS Code Remote-SSH for Amarel; it will load this skill by name/description."
