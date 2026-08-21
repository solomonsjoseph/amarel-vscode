# GEMINI.md

This file is read by **Google Gemini CLI** and **Gemini Code Assist** when
operating in this repository.

The canonical agent runbook lives in [`AGENTS.md`](AGENTS.md). Read that file
first and follow it. The instructions are framework-neutral; only the
discovery mechanism differs across tools.

## Quick reference

This repo deploys VS Code Remote-SSH against the Rutgers Amarel HPC cluster,
which is migrating from CentOS 7 (glibc 2.17) to RHEL 9.6 (glibc 2.34) on the new
host `amarel-new.hpc.rutgers.edu`. On the legacy CentOS 7 host it uses a
custom-glibc sysroot; on RHEL 9.6 VS Code Server runs natively (Phase 5.5
auto-detects which). When the user asks you to "set up Amarel" or "fix the
Remote-SSH GLIBC error":

1. Read `AGENTS.md` for the full step-by-step runbook + security constraints.
2. Walk the user through **Phases 0–13 one command at a time.** For each
   phase, give them the exact command in a fenced block, tell them the
   success marker, wait for them to paste the result, then advance.
   (Phases 0–10 = SSH key auth + sysroot setup; **Phase 5.5** auto-detects the
   remote platform and skips the sysroot Phases 6–9 on RHEL 9.6; **Phase 11**
   points VS Code at a modern git on Amarel so Source Control detects repos;
   **Phase 12** is optional GitHub auth + git identity; **Phase 13** installs the
   `amarel-dev` compute-node session and **runs before Phase 10**, because it decides
   which host the user picks in the Remote-SSH menu.) **If the user is already connected and
   only Source Control / git (or GitHub) is broken, use the Phase 0.2 fast path
   in `AGENTS.md` to jump straight to Phase 11/12 — don't re-run Phases 1–10.**
   **If they are already set up and are asking about their session** ("stop my amarel
   job", "is my session running", "how much time is left", "give me a fresh 8 hour
   session"), use the Phase 0.2b session menu instead of the setup runbook.
   **If they are reporting a failed connection** ("amarel-dev failed", "it won't
   connect", "the remote window won't open"), use **Phase 13.10**. Do not ask them
   what the error said: the editor popup carries no reason, because OpenSSH discards
   a detached master's stderr. Gather the evidence yourself, fix it, verify, then
   file the issue Phase 13.10 describes.
3. **Do not ask the user which OS they are on.** Infer it from context when
   possible; otherwise Phase 0 detects it and you branch from that output.
4. **Do not run the scripts (`scripts/setup.sh` / `scripts/setup.ps1`)
   yourself.** The one-shot script is only for users who explicitly ask
   ("just run it for me") — see the *Power-user path* in `AGENTS.md`.
5. The user types all secrets (Amarel password in Phase 3, key passphrase in
   Phases 1 & 4) into the OS terminal. You never see those.
6. **Verify, don't trust "done".** When the user says a manual step finished (a
   `fresh` reset, the Phase 3 login, the Phase 12 `gh` login / identity), confirm
   it with a quick read-only probe **before advancing or asking the next
   question** — don't take "done" as proof. And skip steps already in place
   (resume) while cleaning stale residue on a fresh start. See `AGENTS.md`
   execution-contract point 5.
7. **The editor belongs on a compute node.** Phase 13 exists because OARC kills
   processes that load the login nodes, and an editor server is not a thin client.
   Never tell a user to point their editor at `amarel-new.hpc.rutgers.edu` or
   `amarel-jump`; the only editor target is `amarel-dev`. Never remove the Amarel
   `~/.bash_profile` guard to make a login-node connection work. Phase 13 stores no
   credentials, installs only under the user's own `$HOME`, adds no auto-renew, and
   any automatic walltime adjustment may only shorten a job, never extend one.
8. **Dual-host transition.** The runbooks default to `amarel-new.hpc.rutgers.edu`.
   Command literals target the new host, but skip-probe / `known_hosts` / `ssh_config` /
   reset regexes in the runbooks are deliberately **widened** to `amarel(-new\.hpc)?\.rutgers\.edu`
   to match **both** hosts. Do **not** blanket find/replace the hostname.

**Security: you must not** read `~/.ssh/id_*` private keys, invoke `sshpass`/
`expect`, query OS keychains, or weaken `BatchMode=yes` constraints. See
`AGENTS.md` § "Security constraints" for the complete list. A fingerprint mismatch
in Phase 2 is a hard stop. Note: **the Phase 2 reference fingerprint is host-aware**
and both hosts are pinned (legacy `amarel.rutgers.edu` → `SHA256:cN6l3k…`;
`amarel-new.hpc.rutgers.edu` → `SHA256:bKbfUNxVCu2nQvssMuNBFtzoR3J7BxXU5RSI9MjWi+E`).

## Installation as a Local Skill/Plugin

If the user asks you to "install this skill" or "install this plugin":
1. Check the local operating system (via environment or terminal command).
2. Execute the install script:
   - **macOS / Linux**: Run `./install.sh` in the terminal.
   - **Windows**: Run `powershell -ExecutionPolicy Bypass -File .\install.ps1` in the terminal.
3. Once completed, inform the user that the skill has been linked to their Gemini config/plugins directory (as well as Claude Code, Codex, etc.).

> Note: the Claude Code `/plugin marketplace add` flow is Claude-Code-specific and
> does not apply to Gemini. The **Gemini-native** one-command install is
> `gemini extensions install https://github.com/solomonsjoseph/amarel-vscode --ref main`
> (`--ref main` because `gemini extensions install` otherwise pulls the latest GitHub
> Release, which ships the sysroot tarball but not this extension's manifest). Use
> `gemini extensions link <repo>` for local dev. `./install.sh` / `install.ps1` also
> link the repo into `~/.gemini/extensions`.

