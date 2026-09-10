# Amarel VS Code Skill

Set up VS Code Remote-SSH on Rutgers Amarel, run the editor on a **compute node**
instead of a login node, and fix the GLIBC 2.28 error. macOS, Linux or Windows.

This community-maintained project helps Rutgers Amarel users connect with VS
Code Remote-SSH. Amarel is migrating from CentOS 7 (glibc 2.17) to RHEL 9.6
(glibc 2.34) on the new host `amarel-new.hpc.rutgers.edu`. On the legacy CentOS 7
host VS Code Server fails with `expected GLIBC >= v2.28.0`, which this project
fixes with a custom-glibc sysroot; on RHEL 9.6 it runs natively, and the skill
auto-detects the host. It works with Claude Code, Codex, other LLM tools, or a
plain shell/PowerShell script.

## The editor belongs on a compute node

Rutgers OARC kills processes that load a shared login node, and a VS Code Server
is not a thin client: it runs language servers, file watchers and extensions for
as long as the window is open. So the setup offers an optional last step that
books a SLURM job and points an `amarel-dev` SSH alias at whichever compute node
that job landed on. One click in the Remote-SSH menu then lands you on a compute
node, first run or hundredth, and a guard on Amarel refuses an editor server on a
login node from then on.

It is a question, not a step, and it is asked after the rest is working. Saying no
leaves a complete login-node setup with nothing to undo.

Once it is installed, the skill also manages the session. Ask it things like
*is my session running*, *how much time is left*, *stop my amarel job*, or
*give me a fresh 8 hour session*. If a connection fails, tell it so in whatever
words you have (*it's not working* is enough): the editor's own popup carries no
reason, so the skill gathers the evidence itself, fixes it, and asks you to
confirm before recording anything.

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
powershell scripts/setup.ps1
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
troubleshooting, and the full setup flow, and
[source-control-git-fix.md](source-control-git-fix.md) for why Source Control
reports "no Git repository" on the legacy host and what fixes it.
