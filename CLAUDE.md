# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is **not** an application — it's an LLM-agnostic *skill/runbook* that sets up VS Code Remote-SSH against the Rutgers Amarel HPC cluster (CentOS 7, glibc 2.17). It installs a custom-glibc 2.28 sysroot into the user's `$HOME` on Amarel so VS Code Server 1.99+ can run there. The deliverable is the setup scripts plus the multi-agent instruction files that drive them.

## Canonical runbook lives elsewhere — read it first

When the user asks you to "set up Amarel," "fix the GLIBC error," or invokes `/amarel-vscode-setup`, **follow `skills/amarel-vscode-setup/SKILL.md`** (the Claude Code entry point). `AGENTS.md` is the framework-neutral mirror of the same runbook for other agents (Codex, Cursor, Cline, Gemini). Both contain the full step-by-step manual flow (Phases 0–10), security deny-list, and failure handling. Do not re-derive that content here.

`skills/amarel-vscode-setup/SKILL.md` / `AGENTS.md` walk the user through **one terminal command at a time** — you hand them the command, they run it, they paste output, you advance. **Do NOT run `scripts/setup.sh` or `scripts/setup.ps1` yourself.** The script is the one-shot fallback for users who explicitly ask for it (documented as "Power-user path" in the runbooks).

If you edit one runbook file, keep the others in sync. The mirrors are:

- `skills/amarel-vscode-setup/SKILL.md` — Claude Code (has YAML frontmatter for slash-command discovery)
- `AGENTS.md` — canonical / Codex / Cursor / Cline (per the [agents.md convention](https://agents.md))
- `GEMINI.md` — Gemini CLI (thin pointer to AGENTS.md)
- `README.md` — end-user docs containing the bare-LLM copy-paste prompt


## Commands

```bash
# End-user setup (idempotent; the script handles every interactive prompt itself)
./scripts/setup.sh                    # macOS / Linux
pwsh scripts/setup.ps1                # Windows
AMAREL_USER=netid ./scripts/setup.sh  # non-interactive username

# Install/refresh local agent skill links (Claude Code + Codex)
./install.sh                          # macOS / Linux
.\install.ps1                         # Windows

# Maintainer-only: rebuild the sysroot tarball (requires Docker, amd64)
./scripts/build-sysroot.sh
```

There is no build/lint/test suite. The "tests" are the 11 idempotent phases (0–10) inside `setup.sh` / `setup.ps1`; they self-verify (preflight tools, VPN reachability, key auth via `BatchMode=yes`, env-var survival in non-interactive SSH, settings.json round-trip). Re-running the script after a fix is the canonical way to verify a change.

## Architecture

The runtime artifact is a tarball (`vscode-sysroot-x86_64-linux-gnu.tgz`) published to GitHub Releases. Locally, the moving parts are:

- `scripts/setup.{sh,ps1}` — the no-LLM / power-user installer (still maintained). 11 phases (0–10): preflight → ssh-keygen → fingerprint verify → ssh-copy-id → ssh-add → BatchMode verify → tarball download+checksum → scp+extract+`.bashrc` edit → non-interactive env-var verify → settings.json signature-disable merge → VS Code GUI hand-off.
- `assets/sysroot.sh` — the snippet appended to `~/.bashrc` on Amarel. Exports three env vars (`VSCODE_SERVER_CUSTOM_GLIBC_LINKER`, `..._PATH`, `VSCODE_SERVER_PATCHELF_PATH`) that VS Code Server's bootstrap reads to patchelf its node binary against the bundled glibc 2.28. This is Microsoft's documented workaround.
- `assets/checksums.txt` — SHA-256 pins for the sysroot tarball + patchelf binary. Phase 6 of `setup.sh` refuses to proceed unless the download matches.
- `scripts/build-sysroot.sh` — maintainer pipeline: clones `ursetto/vscode-sysroot` at a pinned commit, builds via Docker (`linux/amd64`), splices in patchelf ≥ 0.18, re-tars, prints SHAs to paste into `checksums.txt`. The `URSETTO_COMMIT` variable should be a pinned SHA before tagging a release.
- `install.{sh,ps1}` — installs local agent skill links for Claude Code and Codex (`~/.claude/skills/amarel-vscode-setup` and `~/.codex/skills/amarel-vscode-setup`) so `git pull` updates the installed skill.

The release flow (see README "Maintainer notes"): `build-sysroot.sh` → update `checksums.txt` → `gh release create vX.Y.Z …`. `setup.sh` downloads from `releases/latest/download/…`, so a new release becomes default automatically.

## Security boundaries you must respect

`skills/amarel-vscode-setup/SKILL.md` § "Security constraints" is the authoritative list and is non-negotiable. The short version: never read `~/.ssh/id_*`, never invoke `sshpass`/`expect`/`security find-generic-password` or any keychain query, never add `-o PasswordAuthentication=yes` to ssh/scp you spawn, never echo a typed password/passphrase into a file or the transcript. The scripts already enforce these at the bash/PowerShell level by using TTY-attached OS prompts (`ssh-copy-id`, `ssh-add`, `ssh-keygen`); your deny-list is defense-in-depth.

A fingerprint mismatch in Phase 2 is a hard stop — possible MITM. Do not work around it; tell the user to contact OARC.

## Conventions worth knowing

- The 11-phase numbering (0–10) in `setup.sh` and the runbooks is load-bearing — error messages, the README troubleshooting table, `skills/amarel-vscode-setup/SKILL.md`, `AGENTS.md`, and `GEMINI.md` all reference phases by number. Don't renumber; insert new phases with `.5` if absolutely needed.
- Phase 0 owns local OS detection. Do not ask the user whether they are on macOS, Linux, or Windows; infer it from context or the Phase 0 output and branch from there.
- Scripts must remain idempotent. Re-running after any failure is the supported recovery path; don't introduce state that breaks on re-run.
- "🔒 YOUR TURN" is the convention for any prompt the user must type into (vs. confirmations or info lines). Preserve the marker if you add new interactive steps.
