# Amarel VS Code Skill

Set up VS Code Remote-SSH on Rutgers Amarel and fix the GLIBC 2.28 error on
macOS or Windows.

This community-maintained project helps Rutgers Amarel users connect with VS
Code Remote-SSH when VS Code Server fails on Amarel's CentOS 7 environment with
`expected GLIBC >= v2.28.0`. It works with Claude Code, Codex, other LLM tools,
or a plain shell/PowerShell script.

This is not an official Rutgers or OARC project.

## Quick Start

**Claude Code (recommended — no clone):**

```
/plugin marketplace add solomonsjoseph/amarel-vscode
/plugin install amarel-vscode@amarel-vscode
```

Then run `/amarel-vscode-setup`.

**Codex (no clone):**

```
codex plugin marketplace add solomonsjoseph/amarel-vscode
```

Then run `/plugins` in the Codex TUI → install **amarel-vscode**.

**Gemini CLI (no clone):**

```
gemini extensions install https://github.com/solomonsjoseph/amarel-vscode --ref main
```

`--ref main` installs from the branch — without it, `gemini extensions install` pulls the latest GitHub Release, which ships the sysroot tarball but not this extension's manifest.

**Cursor, Cline, or no LLM — clone and link:**

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./install.sh
```

On Windows:

```powershell
.\install.ps1
```

Then use Claude Code with `/amarel-vscode-setup`, ask Codex/Gemini to set up VS
Code Remote-SSH for Amarel, or run the scripts directly:

```bash
./scripts/setup.sh
```

```powershell
pwsh scripts/setup.ps1
```

## Common Search Terms

- amarel vs code skill
- Amarel VS Code
- Rutgers Amarel VS Code
- VS Code Remote SSH Amarel
- Amarel GLIBC 2.28
- Claude Code Amarel skill
- Codex Amarel skill

## More

See the [main README](../README.md) for prerequisites, security rules,
troubleshooting, and the full setup flow.
