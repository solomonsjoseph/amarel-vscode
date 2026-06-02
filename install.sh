#!/usr/bin/env bash
# Install the amarel-vscode-setup skill into local agent skill directories.
#
# Run this once after cloning. Re-running is safe (updates the symlink).

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="amarel-vscode-setup"
PLUGIN_NAME="amarel-vscode"

install_link() {
  local agent_name="$1"
  local source_dir="$2"
  local parent_dir="$3"
  local name="$4"
  local target="${parent_dir}/${name}"

  mkdir -p "$parent_dir"

  # Remove any prior install (symlink or directory)
  if [[ -L "$target" || -e "$target" ]]; then
    echo "→ removing previous ${agent_name} install at $target"
    rm -rf "$target"
  fi

  # Symlink so 'git pull' on the repo updates the installed skill automatically
  ln -s "$source_dir" "$target"
  echo "✓ Installed for ${agent_name}: $target → $source_dir"
}

install_link "Claude Code" "${REPO_DIR}/skills/${SKILL_NAME}" "${HOME}/.claude/skills" "$SKILL_NAME"
install_link "Codex" "${REPO_DIR}/skills/${SKILL_NAME}" "${HOME}/.codex/skills" "$SKILL_NAME"
install_link "Gemini CLI" "$REPO_DIR" "${HOME}/.gemini/config/plugins" "$PLUGIN_NAME"
install_link "Agents" "${REPO_DIR}/skills/${SKILL_NAME}" "${HOME}/.agents/skills" "$SKILL_NAME"

echo ""
echo "Restart your agent so it reloads the local skills/plugins."
echo ""
echo "Claude Code users can instead install via the plugin marketplace (no clone needed):"
echo "  /plugin marketplace add solomonsjoseph/amarel-vscode"
echo "  /plugin install amarel-vscode@amarel-vscode"
echo "Claude Code command:  /${SKILL_NAME}"
echo "Gemini / Codex: ask it to set up VS Code Remote-SSH for Amarel; it will load this skill by name/description."
