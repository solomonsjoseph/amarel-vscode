# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is **not** an application — it's an LLM-agnostic *skill/runbook* that sets up VS Code Remote-SSH against the Rutgers Amarel HPC cluster. Amarel is migrating from CentOS 7 (glibc 2.17) to **RHEL 9.6 (glibc 2.34)** on the new host `amarel-new.hpc.rutgers.edu` (the scripts' default target). On the **legacy CentOS 7 host** it installs a custom-glibc 2.28 sysroot into the user's `$HOME` so VS Code Server 1.99+ can run there; on **RHEL 9.6** VS Code Server runs natively and the sysroot is skipped. A new **Phase 5.5** probes the remote glibc and routes NATIVE vs LEGACY automatically (routing on glibc, not hostname, so either host the user targets is handled). The deliverable is the setup scripts plus the multi-agent instruction files that drive them.

## Canonical runbook lives elsewhere — read it first

When the user asks you to "set up Amarel," "fix the GLIBC error," or invokes `/amarel-vscode-setup`, **follow `skills/amarel-vscode-setup/SKILL.md`** (the Claude Code entry point). `AGENTS.md` is the framework-neutral mirror of the same runbook for other agents (Codex, Cursor, Cline, Gemini). Both contain the full step-by-step manual flow (Phases 0–12 — Phases 0–5 are SSH key auth; **Phase 5.5 auto-detects the remote platform**; Phases 6–9 are the legacy CentOS 7 sysroot + signature workaround, auto-skipped on RHEL 9.6; Phase 10 connects; Phase 11 points VS Code at a modern git so Source Control works; Phase 12 is optional GitHub auth), security deny-list, and failure handling. Do not re-derive that content here.

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
AMAREL_HOST=amarel.rutgers.edu ./scripts/setup.sh   # target the legacy CentOS 7 host (default: amarel-new.hpc.rutgers.edu)

# Per-LLM plugin install (no clone):
#   Claude Code:  /plugin marketplace add solomonsjoseph/amarel-vscode  then  /plugin install amarel-vscode@amarel-vscode
#   Codex:        codex plugin marketplace add solomonsjoseph/amarel-vscode   (then the /plugins picker)
#   Gemini CLI:   gemini extensions install https://github.com/solomonsjoseph/amarel-vscode --ref main
# Install/refresh local agent skill links (symlink path — Cursor/Cline/other agents, and a fallback)
./install.sh                          # macOS / Linux
.\install.ps1                         # Windows

# Maintainer-only: rebuild the sysroot tarball (requires Docker, amd64)
./scripts/build-sysroot.sh
```

There is no build/lint/test suite. The "tests" are the idempotent phases inside `setup.sh` / `setup.ps1` (0–10 plus a **5.5** remote-platform probe and a **9.5** git.path step); they self-verify (preflight tools, VPN reachability, remote glibc detection for NATIVE/LEGACY routing, key auth via `BatchMode=yes`, env-var survival in non-interactive SSH, settings.json round-trip, modern-git detection, and a Source Control repo-detection self-test that reproduces VS Code's `git rev-parse --git-dir --git-common-dir` probe through the *effective* git — the configured `git.path` if set, else the system git). Re-running the script after a fix is the canonical way to verify a change.

## Architecture

The runtime artifact is a tarball (`vscode-sysroot-x86_64-linux-gnu.tgz`) published to GitHub Releases. Locally, the moving parts are:

- `scripts/setup.{sh,ps1}` — the no-LLM / power-user installer (still maintained). Phases 0–10 plus a 5.5, 5.6, and 9.5: preflight → ssh-keygen → fingerprint verify (host-aware reference) → ssh-copy-id → ssh-add → BatchMode verify → **remote-platform probe (Phase 5.5: glibc ≥ 2.28 ⇒ NATIVE; else LEGACY)** → **[NATIVE only] strip legacy sysroot residue (Phase 5.6: a prior LEGACY run on a shared `$HOME` leaves the `~/.bashrc` custom-glibc loader, whose `VSCODE_SERVER_CUSTOM_GLIBC_*` env vars make VS Code show the "unsupported OS" dialog + take the sysroot path even on RHEL 9 — so NATIVE removes the loader, `~/.vscode-server/sysroot*`, and any server patchelf'd against it (`bin`/`cli`), keeping `data/`)** → *[LEGACY only]* tarball download+checksum → scp+extract+`.bashrc` edit → non-interactive env-var verify → settings.json signature-disable merge → **git.path step (Phase 9.5: LEGACY writes an Lmod `git-modern.sh` wrapper / absolute path; NATIVE tests the *effective* git and only writes/repoints `git.path` if VS Code's probe fails — which also cleans a stale legacy `git.path` on a shared `$HOME`)** → VS Code GUI hand-off. The default host is `amarel-new.hpc.rutgers.edu`; override with `AMAREL_HOST=…`. **Speed-up:** when the target is the legacy host and the tarball isn't cached, the scripts kick off a *background* tarball prefetch right after preflight so the LEGACY download overlaps the interactive auth phases (reaped at Phase 6, killed if Phase 5.5 unexpectedly probes NATIVE). This is a cache warm-up keyed on the *hostname hint only* — it does **not** affect routing, which stays glibc-based; NATIVE (default) prefetches nothing. The guided runbooks expose 9.5 as **Phase 11** (post-connect, with reload+verify) and add an optional **Phase 12** (GitHub auth) the scripts don't.
- `assets/sysroot.sh` — the snippet appended to `~/.bashrc` on Amarel. Exports three env vars (`VSCODE_SERVER_CUSTOM_GLIBC_LINKER`, `..._PATH`, `VSCODE_SERVER_PATCHELF_PATH`) that VS Code Server's bootstrap reads to patchelf its node binary against the bundled glibc 2.28. This is Microsoft's documented workaround.
- `assets/checksums.txt` — SHA-256 pins for the sysroot tarball + patchelf binary. Phase 6 of `setup.sh` refuses to proceed unless the download matches.
- `scripts/build-sysroot.sh` — maintainer pipeline: clones `ursetto/vscode-sysroot` at a pinned commit, builds via Docker (`linux/amd64`), splices in patchelf ≥ 0.18, re-tars, prints SHAs to paste into `checksums.txt`. The `URSETTO_COMMIT` variable should be a pinned SHA before tagging a release.
- `install.{sh,ps1}` — installs local agent skill links for Claude Code and Codex (`~/.claude/skills/amarel-vscode-setup` and `~/.codex/skills/amarel-vscode-setup`) so `git pull` updates the installed skill.
- `.claude-plugin/marketplace.json` + `.claude-plugin/plugin.json` — the Claude Code plugin manifests that make the repo installable via `/plugin marketplace add solomonsjoseph/amarel-vscode` then `/plugin install amarel-vscode@amarel-vscode`. The plugin `source` is `"./"` (repo root); the `skills/amarel-vscode-setup/` skill is auto-discovered, so no `skills` key is declared. **`plugin.json` was MOVED here from the repo root — Claude Code reads only `.claude-plugin/plugin.json`, so future manifest edits go here, never to a root `plugin.json`.** Keep `name` (`amarel-vscode`) and `version` identical across both manifests and `PLUGIN_NAME` in `install.{sh,ps1}`. The symlink install path (`install.sh`) remains the supported route for Codex/Gemini/Agents and a Claude Code fallback.
- `.codex-plugin/plugin.json` + `.agents/plugins/marketplace.json` — the **Codex** plugin + marketplace manifests (`codex plugin marketplace add solomonsjoseph/amarel-vscode`; plugin `source.path` is `"./"`, and `"skills": "./skills/"` makes the same `skills/amarel-vscode-setup/` skill discoverable). `gemini-extension.json` (repo root) — the **Gemini** extension manifest (`gemini extensions install <repo-url>`; GEMINI.md is auto-loaded as context and `skills/` is auto-discovered; Gemini loads from `~/.gemini/extensions`). Codex and Gemini do **not** read `.claude-plugin/*` — each ecosystem needs its own manifest. Validate with `claude plugin validate --strict .`, `gemini extensions validate .`, and a local `codex plugin marketplace add <dir>`.

The release flow (see README "Maintainer notes"): `build-sysroot.sh` → update `checksums.txt` → `gh release create vX.Y.Z …`. `setup.sh` downloads from `releases/latest/download/…`, so a new release becomes default automatically.

## Security boundaries you must respect

`skills/amarel-vscode-setup/SKILL.md` § "Security constraints" is the authoritative list and is non-negotiable. The short version: never read `~/.ssh/id_*`, never invoke `sshpass`/`expect`/`security find-generic-password` or any keychain query, never add `-o PasswordAuthentication=yes` to ssh/scp you spawn, never echo a typed password/passphrase into a file or the transcript. The scripts already enforce these at the bash/PowerShell level by using TTY-attached OS prompts (`ssh-copy-id`, `ssh-add`, `ssh-keygen`); your deny-list is defense-in-depth.

A fingerprint mismatch in Phase 2 is a hard stop — possible MITM. Do not work around it; tell the user to contact OARC.

The Phase 2 reference fingerprint is **host-aware** and **both hosts are now pinned**: legacy `amarel.rutgers.edu` (CentOS 7) → `SHA256:cN6l3k…` (recorded 2026-05-26); new `amarel-new.hpc.rutgers.edu` (RHEL 9.6) → `SHA256:bKbfUNxVCu2nQvssMuNBFtzoR3J7BxXU5RSI9MjWi+E` (recorded 2026-06-05, ed25519, confirmed by two independent reads — live first-connect prompt + local `ssh-keyscan` — and distinct from the legacy key, which OARC confirmed was rotated for RHEL9). The pins live in three places kept in lockstep: `scripts/setup.sh`, `scripts/setup.ps1`, and the Phase 2.2 block in `SKILL.md`/`AGENTS.md`. If OARC rotates a key again, update all three together and never re-pin just because a key stopped matching. **Phase 2 auto-verifies** against the pin (since both hosts are pinned): the scripts compare the scanned `SHA256:…` to the recorded reference and proceed on match / `die` on mismatch (no user eyeball), and the runbooks tell the agent to do the same — manual user confirmation only remains for a non-standard `AMAREL_HOST` override with no pin.

## Conventions worth knowing

- The phase numbering is load-bearing — error messages, the README troubleshooting table, `skills/amarel-vscode-setup/SKILL.md`, `AGENTS.md`, and `GEMINI.md` all reference phases by number. The runbooks run 0–12 (5.5 = remote-platform probe, 5.5b = NATIVE-only legacy-residue cleanup, 11 = Source Control git.path, 12 = optional GitHub); the scripts run 0–10 plus 5.5 (remote-platform probe), 5.6 (NATIVE-only legacy-residue cleanup), and 9.5 (the git.path step the runbooks surface as Phase 11). Don't renumber existing phases; append at the end, or insert with `.5`/`.6`.
- **Dual-host during the transition.** The runbooks default to `amarel-new.hpc.rutgers.edu`; the legacy `amarel.rutgers.edu` is still supported and routing is by remote **glibc, never hostname** (Phase 5.5), so a transition DNS alias is handled correctly. Command literals target the new host, but the skip-probe / `known_hosts` / `ssh_config` / reset regexes in the runbooks are deliberately **widened** to `amarel(-new\.hpc)?\.rutgers\.edu` so they match **both** hosts. Do **not** blanket find/replace the hostname — a naive sed flips those widened regexes to a single host and breaks cleanup/detection for the other. In the scripts, the host is the single `AMAREL_HOST`/`$AmarelHost` constant (env-overridable); flip the default there, not inline.
- Phase 0 owns local OS detection. Do not ask the user whether they are on macOS, Linux, or Windows; infer it from context or the Phase 0 output and branch from there.
- Scripts must remain idempotent. Re-running after any failure is the supported recovery path; don't introduce state that breaks on re-run.
- "🔒 YOUR TURN" is the convention for any prompt the user must type into (vs. confirmations or info lines). Preserve the marker if you add new interactive steps.
- The repo ships **five** plugin/extension manifests — Claude (`.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`), Codex (`.codex-plugin/plugin.json` + `.agents/plugins/marketplace.json`), and Gemini (`gemini-extension.json`). Keep `name` (`amarel-vscode`) and `version` identical across all five (and `PLUGIN_NAME` in `install.{sh,ps1}`). Within each ecosystem the plugin manifest wins if it diverges from its marketplace entry (`claude plugin tag` enforces the Claude pair). Never reintroduce a repo-root `plugin.json` — Claude reads only `.claude-plugin/plugin.json`.
- `gemini extensions install <url>` (no `--ref`) installs from the latest **GitHub Release**, not the default branch — so the documented Gemini command uses **`--ref main`**. Our releases carry the sysroot tarball (`setup.sh` reads `releases/latest/download/…`) and predate `gemini-extension.json`. To enable the bare (no-`--ref`) command, a future release must include `gemini-extension.json` **and** still attach the sysroot tarball asset, or `setup.sh`'s download breaks. (Claude's `/plugin marketplace add` and Codex's `codex plugin marketplace add` read the default branch directly, so they need no release.)

## Status

**The skill is fully functional as of 2026-06-05.** End-to-end validated on a fresh account against `amarel-new.hpc.rutgers.edu` (RHEL 9.6, NATIVE path). All phases 0–12 pass. Legacy CentOS 7 path is maintained but not re-validated since the RHEL 9.6 migration.

## Known issues / future work

These are low-priority bugs confirmed during the 2026-05-29 live run. The skill works end-to-end despite them — they affect edge cases in resume/fresh-start flows.

1. **Phase 3.0 skip-probe false-positive** (tracked in GitHub issue #14): if stale Amarel keys remain in `ssh-agent` from a previous session but have not been installed on Amarel yet, the Phase 3.0 BatchMode probe succeeds (agent offers the key, server rejects it quietly), causing Phase 3 (`ssh-copy-id`) to be incorrectly skipped. Fix: tighten the probe to verify the key is actually accepted, not just attempted.

2. **Fresh-start reset wipes `known_hosts` before the Amarel cleanup** (tracked in GitHub issue #15): the reset removes the Amarel `known_hosts` entry early in the wipe sequence, so the subsequent SSH-based Amarel-side cleanup (sysroot removal, `authorized_keys` scrub) cannot connect and is silently skipped. Fix: reorder the reset — run the remote cleanup first while the host entry still exists, then wipe `known_hosts`.

3. **ControlMaster socket goes stale** (tracked in GitHub issue #16): `ControlMaster auto` + `ControlPersist 10m` in `~/.ssh/config` creates a shared socket that outlives the master SSH process after the persist window expires. VS Code then hangs with "Unable to resolve resource" when it tries to reuse the dead socket. Fix: add a troubleshooting entry, or remove `ControlMaster`/`ControlPersist` from the skill-written `ssh_config` block.
