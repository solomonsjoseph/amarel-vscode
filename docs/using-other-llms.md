# Using this skill with other LLMs

The setup scripts (`scripts/setup.sh`, `scripts/setup.ps1`) are framework-
agnostic — they're plain bash / PowerShell and work without any LLM at all.
The LLM-specific files (`SKILL.md`, `AGENTS.md`, `GEMINI.md`, `.clinerules`,
`.cursor/rules/`) just give various agent frameworks a discovery entry
point. **You can ignore the LLM entirely and run the scripts directly.**

This document covers usage with:

1. [Run the scripts directly (no LLM)](#1-run-the-scripts-directly-no-llm)
2. [Claude Code (slash command)](#2-claude-code-slash-command)
3. [OpenAI Codex CLI](#3-openai-codex-cli)
4. [Google Gemini CLI](#4-google-gemini-cli)
5. [Cursor / Cline (VS Code extensions)](#5-cursor--cline-vs-code-extensions)
6. [Bare LLMs (ChatGPT web, Claude.ai web, Ollama, LM Studio, etc.)](#6-bare-llms-chatgpt-web-claudeai-web-ollama-lm-studio-etc)

---

## 1. Run the scripts directly (no LLM)

This is the simplest path. No agent, no API tokens, nothing.

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./scripts/setup.sh                  # macOS / Linux
# OR
pwsh scripts/setup.ps1              # Windows (PowerShell 7)
# OR
powershell -File scripts\setup.ps1  # Windows PowerShell 5.1
```

The script is self-narrating. It prints colored phase headings, surfaces
`🔒 YOUR TURN` prompts at the four interactive moments, and ends with
clear next steps for the VS Code GUI.

This path has the strongest security guarantees because no LLM is involved
at all — your password and passphrase only ever touch your terminal and
the OpenSSH binaries.

## 2. Claude Code (slash command)

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./install.sh                # symlinks into ~/.claude/skills/amarel-vscode-setup
# Restart Claude Code, then:
/amarel-vscode-setup
```

Claude Code reads `SKILL.md` (which has the YAML frontmatter that makes
`/amarel-vscode-setup` a recognized command) and follows the runbook in
`AGENTS.md`.

## 3. OpenAI Codex CLI

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
codex   # opens Codex CLI in this dir
```

Then ask:

> "Set up VS Code Remote-SSH for me on Amarel."

Codex reads `AGENTS.md` automatically as project-level instructions and
runs the appropriate setup script.

## 4. Google Gemini CLI

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
gemini  # or: gemini-cli
```

Then ask:

> "Set up VS Code Remote-SSH for me on Amarel."

Gemini reads `GEMINI.md`, which defers to `AGENTS.md`, and runs the script.

## 5. Cursor / Cline (VS Code extensions)

Open the cloned repo in VS Code with **Cursor** or **Cline** active.

- **Cursor** picks up `.cursor/rules/amarel-vscode.mdc` automatically.
- **Cline** picks up `.clinerules` automatically.

Both defer to `AGENTS.md`. Then ask the agent:

> "Set up VS Code Remote-SSH for me on Amarel."

## 6. Bare LLMs (ChatGPT web, Claude.ai web, Ollama, LM Studio, etc.)

For LLMs without a project-instructions convention, paste this prompt into
the chat:

```
I'm a Rutgers researcher setting up VS Code Remote-SSH against the Amarel
HPC cluster (CentOS 7, glibc 2.17). I'm using the public repo at
https://github.com/solomonsjoseph/amarel-vscode.

Read its AGENTS.md (https://raw.githubusercontent.com/solomonsjoseph/amarel-vscode/main/AGENTS.md)
and walk me through running the appropriate setup script.

Important security rules you must follow:
- Never read or display ~/.ssh/id_* private key files.
- Never invoke sshpass, expect, or any password-feeding helper.
- I will type my Amarel password and SSH key passphrase directly into the
  scripts' interactive prompts — you must never ask me to share them with
  you in chat.
```

If your LLM can't fetch URLs (no web access), instead clone the repo first
and paste the contents of `AGENTS.md` into the chat as context.

### Local LLMs specifically

For **Ollama**, **LM Studio**, **llama.cpp** servers, etc. — these are
typically less capable at following long instructions than frontier
models. **Strongly consider just running `./scripts/setup.sh` directly**
instead of involving the LLM. The script's UX is good enough on its own;
an LLM wrapper adds no value here.

If you still want to use a local LLM, prefer an instruction-tuned model
≥8B parameters (e.g., Qwen2.5-Coder-7B, DeepSeek-Coder-V2, Codestral) and
paste both `AGENTS.md` and the script source into the context so the
model can answer detailed questions about what it's about to run.

---

## Security model recap

Regardless of which LLM (or no LLM) you use:

- Your Amarel password is typed into `ssh-copy-id`'s TTY prompt exactly
  once. It never enters the LLM's stdin/stdout, never gets logged, never
  hits a file.
- Your SSH key passphrase is typed into `ssh-add`'s TTY prompt exactly
  once. The OS keychain stores it from then on. No LLM has an API to
  read OS keychain entries.
- Every subsequent `ssh`/`scp` call uses `BatchMode=yes`, which **refuses
  to prompt for a password** — if key auth fails for any reason, the
  command errors out loudly rather than silently asking for your password.

The cryptographic boundary is enforced by OpenSSH, not by the LLM's good
intentions. Even a malicious or broken LLM cannot extract your password
from this flow.
