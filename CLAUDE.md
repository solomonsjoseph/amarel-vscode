# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is **not** an application — it's an LLM-agnostic *skill/runbook* that sets up VS Code Remote-SSH against the Rutgers Amarel HPC cluster. Amarel is migrating from CentOS 7 (glibc 2.17) to **RHEL 9.6 (glibc 2.34)** on the new host `amarel-new.hpc.rutgers.edu` (the scripts' default target). On the **legacy CentOS 7 host** it installs a custom-glibc 2.28 sysroot into the user's `$HOME` so VS Code Server 1.99+ can run there; on **RHEL 9.6** VS Code Server runs natively and the sysroot is skipped. A new **Phase 5.5** probes the remote glibc and routes NATIVE vs LEGACY automatically (routing on glibc, not hostname, so either host the user targets is handled). The deliverable is the setup scripts plus the multi-agent instruction files that drive them.

## Canonical runbook lives elsewhere — read it first

When the user asks you to "set up Amarel," "fix the GLIBC error," or invokes `/amarel-vscode-setup`, **follow `skills/amarel-vscode-setup/SKILL.md`** (the Claude Code entry point). `AGENTS.md` is the framework-neutral mirror of the same runbook for other agents (Codex, Cursor, Cline, Gemini). Both contain the full step-by-step manual flow (Phases 0–13 — Phases 0–5 are SSH key auth; **Phase 5.5 auto-detects the remote platform**; Phases 6–9 are the legacy CentOS 7 sysroot + signature workaround, auto-skipped on RHEL 9.6; Phase 10 connects; Phase 11 points VS Code at a modern git so Source Control works; Phase 12 is optional GitHub auth; **Phase 13 installs the `amarel-dev` compute-node session, is *optional*, and is offered *after* Phase 12**; whether the user accepts decides which host they connect to at Phase 10), security deny-list, and failure handling. Do not re-derive that content here.

`skills/amarel-vscode-setup/SKILL.md` / `AGENTS.md` walk the user through **one terminal command at a time** — you hand them the command, they run it, they paste output, you advance. **Do NOT run `scripts/setup.sh` or `scripts/setup.ps1` yourself.** The script is the one-shot fallback for users who explicitly ask for it (documented as "Power-user path" in the runbooks).

If you edit one runbook file, keep the others in sync. The mirrors are:

- `skills/amarel-vscode-setup/SKILL.md` — Claude Code (has YAML frontmatter for slash-command discovery)
- `AGENTS.md` — canonical / Codex / Cursor / Cline (per the [agents.md convention](https://agents.md))
- `GEMINI.md` — Gemini CLI (thin pointer to AGENTS.md)
- `README.md` — end-user docs containing the bare-LLM copy-paste prompt
- `docs/index.md` — the GitHub Pages landing page
- `docs/source-control-git-fix.md` — the Phase 11/12 deep dive

The last two are easy to forget and both carry phase numbers, so they drift
quietly. There is now a `docs-parity` CI job that catches the mechanical half of
that (see below); it cannot catch prose going stale.


## Commands

```bash
# End-user setup (idempotent; the script handles every interactive prompt itself)
./scripts/setup.sh                    # macOS / Linux
powershell scripts/setup.ps1          # Windows
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

There is no build/lint/test suite for behaviour, but there **is** a `docs-parity` GitHub Actions job (`.github/workflows/docs-parity.yml`) that fails a PR if `AGENTS.md` and `SKILL.md` fall out of lockstep, if a doc's code fences go odd, if the five manifest versions disagree, or if the two fingerprint pins stop matching. Twelve commits between 2026-08-19 and 2026-08-22 changed `AGENTS.md` without touching `README.md`, which is what that job exists to stop.

The behavioural "tests" are the idempotent phases inside `setup.sh` / `setup.ps1` (0–10 plus a **5.5** remote-platform probe, a **5.6** NATIVE-only residue strip, a **9.5** git.path step and a **9.6** compute-session install); they self-verify (preflight tools, VPN reachability, remote glibc detection for NATIVE/LEGACY routing, key auth via `BatchMode=yes`, env-var survival in non-interactive SSH, settings.json round-trip, modern-git detection, and a Source Control repo-detection self-test that reproduces VS Code's `git rev-parse --git-dir --git-common-dir` probe through the *effective* git — the configured `git.path` if set, else the system git). Re-running the script after a fix is the canonical way to verify a change.

## Architecture

The runtime artifact is a tarball (`vscode-sysroot-x86_64-linux-gnu.tgz`) published to GitHub Releases. Locally, the moving parts are:

- `scripts/setup.{sh,ps1}` — the no-LLM / power-user installer (still maintained). Phases 0–10 plus a 5.5, 5.6, and 9.5: preflight → ssh-keygen → fingerprint verify (host-aware reference) → ssh-copy-id → ssh-add → BatchMode verify → **remote-platform probe (Phase 5.5: glibc ≥ 2.28 ⇒ NATIVE; else LEGACY)** → **[NATIVE only] strip legacy sysroot residue (Phase 5.6: a prior LEGACY run on a shared `$HOME` leaves the `~/.bashrc` custom-glibc loader, whose `VSCODE_SERVER_CUSTOM_GLIBC_*` env vars make VS Code show the "unsupported OS" dialog + take the sysroot path even on RHEL 9 — so NATIVE removes the loader, `~/.vscode-server/sysroot*`, and any server patchelf'd against it (`bin`/`cli`), keeping `data/`)** → *[LEGACY only]* tarball download+checksum → scp+extract+`.bashrc` edit → non-interactive env-var verify → settings.json signature-disable merge → **git.path step (Phase 9.5: LEGACY writes an Lmod `git-modern.sh` wrapper / absolute path; NATIVE tests the *effective* git and only writes/repoints `git.path` if VS Code's probe fails — which also cleans a stale legacy `git.path` on a shared `$HOME`)** → VS Code GUI hand-off. The default host is `amarel-new.hpc.rutgers.edu`; override with `AMAREL_HOST=…`. **Speed-up:** when the target is the legacy host and the tarball isn't cached, the scripts kick off a *background* tarball prefetch right after preflight so the LEGACY download overlaps the interactive auth phases (reaped at Phase 6, killed if Phase 5.5 unexpectedly probes NATIVE). This is a cache warm-up keyed on the *hostname hint only* — it does **not** affect routing, which stays glibc-based; NATIVE (default) prefetches nothing. The guided runbooks expose 9.5 as **Phase 11** (post-connect, with reload+verify) and add an optional **Phase 12** (GitHub auth) the scripts don't.
- `cluster/` — the Phase 13 compute-node session, installed into the user's own `$HOME` on Amarel by `setup.sh` Phase 9.6. `amarel-dev-lib` (sourced helpers: walltime maths, MAINT-reservation lookup, job lookup, node probes), `dev-session` (`ensure`/`status`/`node`/`stop`), `amarel-dev-connect` (the connect-time brain, run by the `ProxyCommand`, plus a `--selftest` mode the setup gates on), `amarel-dev.conf.example`, and `bash_profile_block.sh` (the login-node guard, wrapped in `# >>> amarel-vscode phase 13 >>>` markers so the reset can strip it). **Three coupled facts live here and are easy to break:** the connect script's stdout *is* the SSH tunnel, so only `nc` may write to it; `nc -i 120s` only survives because the laptop's `ssh_config` sets `ServerAliveInterval 15` on `Host amarel-dev`; and every wait sums over the longest path to ~265s against the editor's 300s ceiling. MAINT detection keys on `Flags=*MAINT*`, never on "is any reservation active" (a `SPEC_NODES` reservation ran to 2027-07-31 and would refuse every connection for eleven months). Live verification log: `cluster/VERIFICATION-2026-08-21.md`.
- `assets/sysroot.sh` — the snippet appended to `~/.bashrc` on Amarel. Exports three env vars (`VSCODE_SERVER_CUSTOM_GLIBC_LINKER`, `..._PATH`, `VSCODE_SERVER_PATCHELF_PATH`) that VS Code Server's bootstrap reads to patchelf its node binary against the bundled glibc 2.28. This is Microsoft's documented workaround.
- `assets/checksums.txt` — SHA-256 pins for the sysroot tarball + patchelf binary. Phase 6 of `setup.sh` refuses to proceed unless the download matches.
- `scripts/build-sysroot.sh` — maintainer pipeline: clones `ursetto/vscode-sysroot` at a pinned commit, builds via Docker (`linux/amd64`), splices in patchelf ≥ 0.18, re-tars, prints SHAs to paste into `checksums.txt`. The `URSETTO_COMMIT` variable should be a pinned SHA before tagging a release.
- `scripts/devmode-verify.sh` + `scripts/devmode_verify.py` + `scripts/devmode.digest.json` — the gate on the `AGENTS.md` "Dev mode" section. A salted PBKDF2-SHA256 verifier (600k iterations) that checks one phrase **read from stdin, never argv**, and prints only `MATCH` / `NO-MATCH`. It fails closed if any piece is missing. The python lives in its own file on purpose: as a heredoc it would *become* the process's stdin, so python would read the script instead of the phrase and every check would fail. Load-bearing, and previously documented only in `GEMINI.md`.
- `.watch/GOAL.md` + `.watch/NOTES.md` — the six verbatim goals Phase 13 is audited against, and a read-only 2026-08-21 audit against them. Working artifacts, not user-facing, and not read by any code. Useful as recorded design intent: its HIGH finding (four `return 0` paths printing "Server-side setup complete" while leaving the login-node guard uninstalled) is fixed, `COMPUTE_SESSION_SKIP` / `COMPUTE_SESSION_DECLINED` now gate that summary.
- `.github/workflows/build-and-release.yml` — builds the sysroot tarball on a native x86_64 runner (crosstool-NG cannot build under QEMU on Apple Silicon) and publishes it to a Release on a `v*` tag. `.github/workflows/docs-parity.yml` — the doc lockstep/fence/version/pin checks.
- `docs/` — `index.md` is the GitHub Pages landing page; `source-control-git-fix.md` is the Phase 11/12 deep dive. Both carry phase numbers and both belong in the mirror set above.
- `install.{sh,ps1}` — installs local agent skill links for Claude Code and Codex (`~/.claude/skills/amarel-vscode-setup` and `~/.codex/skills/amarel-vscode-setup`) so `git pull` updates the installed skill.
- `.claude-plugin/marketplace.json` + `.claude-plugin/plugin.json` — the Claude Code plugin manifests that make the repo installable via `/plugin marketplace add solomonsjoseph/amarel-vscode` then `/plugin install amarel-vscode@amarel-vscode`. The plugin `source` is `"./"` (repo root); the `skills/amarel-vscode-setup/` skill is auto-discovered, so no `skills` key is declared. **`plugin.json` was MOVED here from the repo root — Claude Code reads only `.claude-plugin/plugin.json`, so future manifest edits go here, never to a root `plugin.json`.** Keep `name` (`amarel-vscode`) and `version` identical across both manifests and `PLUGIN_NAME` in `install.{sh,ps1}`. The symlink install path (`install.sh`) remains the supported route for Codex/Gemini/Agents and a Claude Code fallback.
- `.codex-plugin/plugin.json` + `.agents/plugins/marketplace.json` — the **Codex** plugin + marketplace manifests (`codex plugin marketplace add solomonsjoseph/amarel-vscode`; plugin `source.path` is `"./"`, and `"skills": "./skills/"` makes the same `skills/amarel-vscode-setup/` skill discoverable). `gemini-extension.json` (repo root) — the **Gemini** extension manifest (`gemini extensions install <repo-url>`; GEMINI.md is auto-loaded as context and `skills/` is auto-discovered; Gemini loads from `~/.gemini/extensions`). Codex and Gemini do **not** read `.claude-plugin/*` — each ecosystem needs its own manifest. Validate with `claude plugin validate --strict .`, `gemini extensions validate .`, and a local `codex plugin marketplace add <dir>`.

The release flow (see README "Maintainer notes"): `build-sysroot.sh` → update `checksums.txt` → `gh release create vX.Y.Z …`. `setup.sh` downloads from `releases/latest/download/…`, so a new release becomes default automatically.

## Security boundaries you must respect

`skills/amarel-vscode-setup/SKILL.md` § "Security constraints" is the authoritative list and is non-negotiable. The short version: never read `~/.ssh/id_*`, never invoke `sshpass`/`expect`/`security find-generic-password` or any keychain query, never add `-o PasswordAuthentication=yes` to ssh/scp you spawn, never echo a typed password/passphrase into a file or the transcript. The scripts already enforce these at the bash/PowerShell level by using TTY-attached OS prompts (`ssh-copy-id`, `ssh-add`, `ssh-keygen`); your deny-list is defense-in-depth.

**`[TTY]` is a hard prohibition, not a convention.** A step tagged `[TTY]` is the user's to run, always, and you must never execute one yourself. This became unconditional in #36/#37 (2026-08-22) after an agent ran a destructive `[TTY]` reset step on its own reasoning that the step prompted for no secret. Whether it prompts for a secret is irrelevant, and an autonomous-mode instruction does not lift it.

**The skill has two non-setup lanes, and they are the common case once someone is set up.** Phase 13.9 is session management (`stop my amarel job`, `how much time is left`, `give me a fresh 8 hour session`, which needs the conf edited before `ensure`). Phase 13.10 is the failure lane, and it routes on a vague report (`it's not working`, `something is broken`, `help`) as well as a named one, because the editor's popup carries no reason. Do not ask the user to read an error message; gather the evidence yourself, fix it, have them confirm, then file the issue.

A fingerprint mismatch in Phase 2 is a hard stop — possible MITM. Do not work around it; tell the user to contact OARC.

The Phase 2 reference fingerprint is **host-aware** and **both hosts are pinned**: legacy `amarel.rutgers.edu` (CentOS 7, recorded 2026-05-26) and new `amarel-new.hpc.rutgers.edu` (RHEL 9.6, recorded 2026-06-05, ed25519, confirmed by two independent reads, the live first-connect prompt and a local `ssh-keyscan`, and distinct from the legacy key, which OARC confirmed was rotated for RHEL9).

**The pin values are deliberately not repeated here.** They live in exactly three places: `scripts/setup.sh`, `scripts/setup.ps1`, and the Phase 2.2 block in `AGENTS.md` (mirrored to `SKILL.md`). This file and `GEMINI.md` used to carry a truncated copy of the legacy pin, which meant a rotation had to touch five files and the two abbreviated ones would have been missed. A security constant should have as few copies as possible; read Phase 2.2 for the values. The `docs-parity` CI job asserts the three remaining copies still agree. If OARC rotates a key, update those three together, and never re-pin just because a key stopped matching. **Phase 2 auto-verifies** against the pin (since both hosts are pinned): the scripts compare the scanned `SHA256:…` to the recorded reference and proceed on match / `die` on mismatch (no user eyeball), and the runbooks tell the agent to do the same — manual user confirmation only remains for a non-standard `AMAREL_HOST` override with no pin.

## Conventions worth knowing

- The phase numbering is load-bearing — error messages, the README troubleshooting table, `skills/amarel-vscode-setup/SKILL.md`, `AGENTS.md`, and `GEMINI.md` all reference phases by number. The runbooks run 0–13 (5.5 = remote-platform probe, 5.5b = NATIVE-only legacy-residue cleanup, 11 = Source Control git.path, 12 = optional GitHub, 13 = optional compute-node session, offered after 12); the scripts run 0–10 plus 5.5 (remote-platform probe), 5.6 (NATIVE-only legacy-residue cleanup), 9.5 (the git.path step the runbooks surface as Phase 11), and 9.6 (the compute-node session the runbooks surface as Phase 13). Don't renumber existing phases; append at the end, or insert with `.5`/`.6`.
- **Dual-host during the transition.** The runbooks default to `amarel-new.hpc.rutgers.edu`; the legacy `amarel.rutgers.edu` is still supported and routing is by remote **glibc, never hostname** (Phase 5.5), so a transition DNS alias is handled correctly. Command literals target the new host, but the skip-probe / `known_hosts` / `ssh_config` / reset regexes in the runbooks are deliberately **widened** to `amarel(-new\.hpc)?\.rutgers\.edu` so they match **both** hosts. Do **not** blanket find/replace the hostname — a naive sed flips those widened regexes to a single host and breaks cleanup/detection for the other. In the scripts, the host is the single `AMAREL_HOST`/`$AmarelHost` constant (env-overridable); flip the default there, not inline.
- Phase 0 owns local OS detection. Do not ask the user whether they are on macOS, Linux, or Windows; infer it from context or the Phase 0 output and branch from there.
- Scripts must remain idempotent. Re-running after any failure is the supported recovery path; don't introduce state that breaks on re-run.
- "🔒 YOUR TURN" is the convention for any prompt the user must type into (vs. confirmations or info lines). Preserve the marker if you add new interactive steps.
- The repo ships **five** plugin/extension manifests — Claude (`.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json`), Codex (`.codex-plugin/plugin.json` + `.agents/plugins/marketplace.json`), and Gemini (`gemini-extension.json`). Keep `name` (`amarel-vscode`) and `version` identical across all five (and `PLUGIN_NAME` in `install.{sh,ps1}`). Within each ecosystem the plugin manifest wins if it diverges from its marketplace entry (`claude plugin tag` enforces the Claude pair). Never reintroduce a repo-root `plugin.json` — Claude reads only `.claude-plugin/plugin.json`.
- `gemini extensions install <url>` (no `--ref`) installs from the latest **GitHub Release**, not the default branch — so the documented Gemini command uses **`--ref main`**. Our releases carry the sysroot tarball (`setup.sh` reads `releases/latest/download/…`) and predate `gemini-extension.json`. To enable the bare (no-`--ref`) command, a future release must include `gemini-extension.json` **and** still attach the sysroot tarball asset, or `setup.sh`'s download breaks. (Claude's `/plugin marketplace add` and Codex's `codex plugin marketplace add` read the default branch directly, so they need no release.)

## Status

**Working, on macOS, as of 2026-09-10.** Phases 0–12 were end-to-end validated on a fresh account against `amarel-new.hpc.rutgers.edu` (RHEL 9.6, NATIVE path) on 2026-06-05, and **Phase 13 (the compute-node session) landed 2026-08-21** with a live-cluster log at `cluster/VERIFICATION-2026-08-21.md`. PR #29 added a live clean run on 2026-08-21, and #36/#37 turned `[TTY]` into a hard, unconditional agent prohibition on 2026-08-22 after an agent executed a destructive `[TTY]` reset step itself.

Per-platform, because "fully functional" was hiding real gaps:

| Platform | State |
|---|---|
| macOS | Validated, including Phase 13 against a live compute node. |
| Linux | Not validated. Shares the bash path with macOS, so expected to work; the only known divergences are `UseKeychain` (macOS only) and the Sequoia fix in 4.4. |
| Windows, Phases 0–12 | **Works** against `amarel-new`, per the owner. |
| Windows, Phase 13 / `amarel-dev` | **Never run.** This is the one real gap; see issue #30 and the untested-items table in `AGENTS.md`. |
| Legacy CentOS 7 | Maintained but not re-validated since the RHEL 9.6 migration. |

## Known issues / future work

**Do not record an issue list here.** The previous version of this section said "No known open issues as of 2026-06-10", and by 2026-08-22 there were four. A snapshot of a moving list is worse than no list, because an agent reads it and concludes there is nothing to fix.

Read `gh issue list` instead. For work that is *known* to be open but is not an issue, see the untested-items table in the `AGENTS.md` Dev mode section.

One correction worth stating here, because getting it wrong reintroduces a fixed bug: **issue #16 removed `ControlMaster`, and Phase 13 deliberately puts it back** for the `amarel-dev` block, with a coupled `ServerAliveInterval 15` / `ServerAliveCountMax 3` keepalive and `ControlPersist 1800`. The rationale and the 2026-08-21 re-test are in the `ssh_config` comment block the runbook writes. Do not "clean up" `ControlMaster` on the strength of #16's title.

