# Using this skill with other LLMs

Two paths exist, and both work end-to-end:

- **Step-by-step (LLM-mediated):** the LLM reads `SKILL.md` / `AGENTS.md` and
  hands you one terminal command at a time, waiting for your output between
  phases. This is the default LLM-driven path.
- **One-shot script (no LLM needed):** run `scripts/setup.sh` (or
  `scripts/setup.ps1`) directly. It does the same 11 phases in sequence with
  the same idempotency and TTY-based prompts. No agent involved.

The LLM-specific files (`SKILL.md`, `AGENTS.md`, `GEMINI.md`) just give
agent frameworks a discovery entry point. **You can ignore the LLM entirely
and run the script.**

This document covers usage with:

1. [Run the script directly (no LLM)](#1-run-the-script-directly-no-llm)
2. [Local skill install for Claude Code and Codex](#2-local-skill-install-for-claude-code-and-codex)
3. [OpenAI Codex CLI without install](#3-openai-codex-cli-without-install)
4. [Google Gemini CLI](#4-google-gemini-cli)
5. [Cursor / Cline (VS Code extensions)](#5-cursor--cline-vs-code-extensions)
6. [Bare LLMs (ChatGPT web, Claude.ai web, Ollama, LM Studio, etc.)](#6-bare-llms-chatgpt-web-claudeai-web-ollama-lm-studio-etc)

---

## 1. Run the script directly (no LLM)

The simplest path. No agent, no API tokens, nothing.

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

## 2. Local skill install for Claude Code and Codex

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./install.sh                # symlinks into ~/.claude/skills and ~/.codex/skills
# Restart Claude Code or Codex so it reloads local skills.
```

Claude Code exposes the slash command:

```text
/amarel-vscode-setup
```

Codex loads the same installed skill by name/description. Ask:

```text
Set up VS Code Remote-SSH for me on Amarel.
```

The skill walks you through Phases 0–10 **one command at a time**. For each
phase, the agent:

1. Tells you what the phase does.
2. Gives you the exact command(s) to copy into your terminal.
3. Tells you the success marker to look for.
4. Waits for you to paste your output back, then advances or diagnoses.

Phase 0 detects the local OS. The agent should not ask whether you are on
macOS, Linux, or Windows.

You can also ask the agent to "just run the script" — it will point you at the
one-shot path in section 1 above instead.

## 3. OpenAI Codex CLI without install

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
codex   # opens Codex CLI in this dir
```

Then ask:

> "Set up VS Code Remote-SSH for me on Amarel."

Codex reads `AGENTS.md` automatically as project-level instructions and
walks you through Phases 0–10 one command at a time.

## 4. Google Gemini CLI

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
gemini  # or: gemini-cli
```

Then ask:

> "Set up VS Code Remote-SSH for me on Amarel."

Gemini reads `GEMINI.md`, which defers to `AGENTS.md`, and walks you
through Phases 0–10 one command at a time.

## 5. Cursor / Cline (VS Code extensions)

Open the cloned repo in VS Code with **Cursor** or **Cline** active.
Both agents look for an `AGENTS.md` at the repo root and use it as
project-level instructions.

Then ask the agent:

> "Set up VS Code Remote-SSH for me on Amarel."

The agent walks you through Phases 0–10 one command at a time.

## 6. Bare LLMs (ChatGPT web, Claude.ai web, Ollama, LM Studio, etc.)

For LLMs without a project-instructions convention, paste this prompt into
the chat:

```
I'm a Rutgers researcher setting up VS Code Remote-SSH against the Amarel
HPC cluster (CentOS 7, glibc 2.17). I'm using the public repo at
https://github.com/solomonsjoseph/amarel-vscode.

Read its AGENTS.md (https://raw.githubusercontent.com/solomonsjoseph/amarel-vscode/main/AGENTS.md)
and walk me through it step-by-step:
- Give me ONE command at a time in a fenced code block.
- Tell me the success marker so I know when it worked.
- Wait for me to paste my terminal output before giving the next command.
- Do NOT ask me which operating system I'm on — Phase 0 detects it and you
  should choose later commands from that output.
- Do NOT run the script (scripts/setup.sh) on my behalf or paste its
  contents at me — walk me through the manual phases instead.

Important security rules you must follow:
- Never read or display ~/.ssh/id_* private key files.
- Never invoke sshpass, expect, or any password-feeding helper.
- I will type my Amarel password and SSH key passphrase directly into
  interactive prompts — you must never ask me to share them with you in
  chat.
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
model can answer detailed questions about each step before running it.

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
