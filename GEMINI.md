# GEMINI.md

This file is read by **Google Gemini CLI** and **Gemini Code Assist** when
operating in this repository.

The canonical agent runbook lives in [`AGENTS.md`](AGENTS.md). Read that file
first and follow it. The instructions are framework-neutral; only the
discovery mechanism differs across tools.

## Quick reference

This repo deploys VS Code Remote-SSH against the Rutgers Amarel HPC cluster
(CentOS 7) using a custom-glibc sysroot. When the user asks you to "set up
Amarel" or "fix the Remote-SSH GLIBC error":

1. Read `AGENTS.md` for the full step-by-step runbook + security constraints.
2. Walk the user through **Phases 0–12 one command at a time.** For each
   phase, give them the exact command in a fenced block, tell them the
   success marker, wait for them to paste the result, then advance.
   (Phases 0–10 = SSH key auth + sysroot setup; **Phase 11** points VS Code at
   a modern git on Amarel so Source Control detects repos; **Phase 12** is
   optional GitHub auth + git identity.) **If the user is already connected and
   only Source Control / git (or GitHub) is broken, use the Phase 0.2 fast path
   in `AGENTS.md` to jump straight to Phase 11/12 — don't re-run Phases 1–10.**
3. **Do not ask the user which OS they are on.** Infer it from context when
   possible; otherwise Phase 0 detects it and you branch from that output.
4. **Do not run the scripts (`scripts/setup.sh` / `scripts/setup.ps1`)
   yourself.** The one-shot script is only for users who explicitly ask
   ("just run it for me") — see the *Power-user path* in `AGENTS.md`.
5. The user types all secrets (Amarel password in Phase 3, key passphrase in
   Phases 1 & 4) into the OS terminal. You never see those.

**Security: you must not** read `~/.ssh/id_*` private keys, invoke `sshpass`/
`expect`, query OS keychains, or weaken `BatchMode=yes` constraints. See
`AGENTS.md` § "Security constraints" for the complete list.

## Installation as a Local Skill/Plugin

If the user asks you to "install this skill" or "install this plugin":
1. Check the local operating system (via environment or terminal command).
2. Execute the install script:
   - **macOS / Linux**: Run `./install.sh` in the terminal.
   - **Windows**: Run `powershell -ExecutionPolicy Bypass -File .\install.ps1` in the terminal.
3. Once completed, inform the user that the skill has been linked to their Gemini config/plugins directory (as well as Claude Code, Codex, etc.).

