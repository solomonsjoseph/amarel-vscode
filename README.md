# Amarel VS Code Skill
## Set up VS Code Remote-SSH on Rutgers Amarel and fix the GLIBC 2.28 error

Amarel VS Code Skill is a community-maintained setup guide and script for
Rutgers Amarel users who need VS Code Remote-SSH to work. Amarel is migrating
from CentOS 7 (glibc 2.17) to **RHEL 9.6 (glibc 2.34)** on the new host
`amarel-new.hpc.rutgers.edu`. On the legacy CentOS 7 host it fixes the
**`expected GLIBC >= v2.28.0`** error by installing a pinned user-space sysroot
in your Amarel `$HOME`; on RHEL 9.6 VS Code Server runs natively, so the skill
auto-detects the host and skips the sysroot. Works with any LLM or no LLM at all.

This is not an official Rutgers or OARC project.

After setup you connect to Amarel from VS Code in two clicks and **never type
your Amarel password again**.

---

## Who this is for

- Rutgers Amarel users setting up VS Code Remote-SSH from macOS or Windows.
- Researchers who hit the VS Code Server `GLIBC >= v2.28.0` error on Amarel.
- Claude Code, Codex, Gemini CLI, Cursor, and Cline users who want a guided
  skill.
- Anyone who prefers to run a plain shell or PowerShell script without an LLM.

## Common search terms this fixes

This repo is meant to be discoverable for:

- amarel vs code skill
- Amarel VS Code
- Rutgers Amarel VS Code
- VS Code Remote SSH Amarel
- Amarel GLIBC 2.28
- Claude Code Amarel skill
- Codex Amarel skill

## Quick start

### Claude Code (recommended — no clone needed)

```
/plugin marketplace add solomonsjoseph/amarel-vscode
/plugin install amarel-vscode@amarel-vscode
```

Then run `/amarel-vscode-setup`. (If the command doesn't appear yet, run
`/reload-plugins` or restart the session.)

### Codex (no clone needed)

```
codex plugin marketplace add solomonsjoseph/amarel-vscode
```

Then start Codex, run **`/plugins`** → install **amarel-vscode**, and ask:
*"Set up VS Code Remote-SSH for me on Amarel."* (Type `@` to invoke the bundled skill.)

### Gemini CLI (no clone needed)

```
gemini extensions install https://github.com/solomonsjoseph/amarel-vscode --ref main
```

Then ask: *"Set up VS Code Remote-SSH for me on Amarel."* (`--ref main` installs from
the branch — `gemini extensions install` otherwise pulls the latest GitHub Release,
which ships the sysroot tarball but not this extension's manifest.)

### Cursor, Cline, or any other agent — clone and link

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./install.sh          # macOS / Linux
.\install.ps1         # Windows
```

The tool auto-reads `AGENTS.md` / `GEMINI.md`. Ask:
*"Set up VS Code Remote-SSH for me on Amarel."*

### No LLM — just run the script

```bash
./scripts/setup.sh          # macOS / Linux
pwsh scripts/setup.ps1      # Windows
```

The script is self-narrating and handles everything interactively.

### ChatGPT, Claude.ai, or any bare LLM

Paste this into a new chat (or share `AGENTS.md` as a file if your LLM
supports uploads):

```
I'm a Rutgers researcher setting up VS Code Remote-SSH against the Amarel
HPC cluster, which is migrating from CentOS 7 (glibc 2.17) to RHEL 9.6
(glibc 2.34) on the new host amarel-new.hpc.rutgers.edu. I'm using this repo:
https://github.com/solomonsjoseph/amarel-vscode

Read its AGENTS.md:
https://raw.githubusercontent.com/solomonsjoseph/amarel-vscode/main/AGENTS.md

Walk me through it step by step:
- Give me ONE command at a time in a fenced code block.
- Tell me the success marker so I know when it worked.
- Wait for me to paste my terminal output before advancing.
- Do NOT ask which OS I'm on — Phase 0 detects it automatically.
- Do NOT run scripts/setup.sh on my behalf.

Security rules:
- Never read or display ~/.ssh/id_* private key files.
- Never use sshpass, expect, or any password-feeding helper.
- I will type my Amarel password and SSH passphrase directly into
  interactive terminal prompts — never ask me to share them in chat.
```

> **Ollama / LM Studio / local LLMs:** smaller models often struggle
> following the full runbook. For the most reliable experience, just run
> `./scripts/setup.sh` directly — no LLM needed.

---

## How do I use VS Code on Rutgers Amarel?

Install VS Code and the Remote-SSH extension, clone this repo, run the guided
skill or setup script, then connect to `amarel-new.hpc.rutgers.edu` (the new
RHEL 9.6 host; the legacy `amarel.rutgers.edu` still works during the transition)
from VS Code's Remote-SSH host picker. The setup creates a dedicated SSH key,
verifies passwordless SSH, installs the sysroot VS Code Server needs on the
legacy host (auto-skipped on RHEL 9.6), and prints the final GUI steps.

## Why does VS Code fail on Amarel with GLIBC >= 2.28?

The **legacy** Amarel host runs CentOS 7 with glibc 2.17, while modern VS Code
Server builds need glibc 2.28 or newer — so on that host this repo installs a
pinned user-space glibc 2.28 sysroot under your Amarel home directory and
configures VS Code Server startup to use it. The **new** host
`amarel-new.hpc.rutgers.edu` runs RHEL 9.6 (glibc 2.34), which satisfies VS Code
natively, so no sysroot is needed there — Phase 5.5 detects the remote glibc and
routes automatically.

## Is this only for Claude Code?

No. Claude Code can run the packaged skill, but the same workflow is available
to Codex, Gemini CLI, Cursor, Cline, ChatGPT, Claude.ai, and other LLMs through
the repo instructions.

## Can I use this without an LLM?

Yes. Run `./scripts/setup.sh` on macOS/Linux or `pwsh scripts/setup.ps1` on
Windows. The scripts are self-narrating and handle the same setup flow
interactively.

## Is my Amarel password exposed to the LLM?

No. You type your Amarel password only into an interactive SSH terminal prompt.
The LLM is forbidden from reading private keys, piping passwords, or using
password-feeding helpers. See the Security section for the full rules.

## Does this work on macOS and Windows?

Yes. macOS/Linux use the shell scripts and Windows uses the PowerShell scripts.
Both paths set up VS Code Remote-SSH for Rutgers Amarel and apply the GLIBC
2.28 sysroot fix.

---

## Prerequisites

1. **Rutgers Amarel account** — request one via OARC if you don't have it.
2. **Rutgers VPN connected** — Cisco AnyConnect or GlobalProtect.
3. **VS Code** with the **Remote-SSH** extension (`ms-vscode-remote.remote-ssh`).
4. **OpenSSH tools** — included by default on macOS and Windows 10/11 (1809+).

Phase 0 of the skill detects your OS and confirms all of these automatically.

---

## What it does

| Phase | Action |
|-------|--------|
| 0 | Preflight — detect OS, check tools, verify VPN reachability |
| 1 | Generate a dedicated SSH keypair (`~/.ssh/id_ed25519_amarel`) |
| 2 | Display Amarel's host fingerprint — you verify it against OARC's published value |
| 3 | `ssh-copy-id` — install your key on Amarel. **Your last Amarel password prompt ever.** |
| 4 | `ssh-add` — save your key passphrase to the OS keychain |
| 5 | Verify passwordless SSH works end-to-end |
| 5.5 | Detect the remote platform (glibc): RHEL 9.6 → skip the sysroot Phases 6–9; CentOS 7 → run them |
| 5.5b | *(RHEL 9.6 only)* Strip any legacy sysroot residue left from a prior CentOS 7 setup on the same `$HOME` |
| 5.5c | *(RHEL 9.6 only)* Add an `amarel.rutgers.edu` → `amarel-new.hpc.rutgers.edu` alias to `~/.ssh/config` so stale VS Code Recents entries don't land on the old CentOS 7 host |
| 6 | *(legacy CentOS 7 only)* Download the glibc 2.28 sysroot tarball from GitHub Releases, verify SHA-256 |
| 7 | *(legacy CentOS 7 only)* Copy the tarball to Amarel, extract it, wire up `~/.bashrc` |
| 8 | *(legacy CentOS 7 only)* Verify the glibc env vars load in a non-interactive SSH session |
| 9 | *(legacy CentOS 7 only)* Write `"extensions.verifySignature": false` to VS Code Server's settings — needed only when the node binary is patched against the custom glibc |
| 10 | Print the VS Code GUI steps — connect and you're done |
| 11 | Point VS Code at a modern git on Amarel (`git.path`) so Source Control detects your repos — needed on legacy CentOS 7 (stock git 1.8.3.1); on RHEL 9.6 the system git ~2.43 already passes, so nothing is written |
| 12 | *(Optional)* Authenticate GitHub on Amarel (`gh auth login`) and set your git identity, so commits and pushes work |

After Phase 10: **VS Code → Remote-SSH: Connect to Host → `amarel-new.hpc.rutgers.edu`**
(or the legacy `amarel.rutgers.edu` during the transition). Then, once connected,
Phase 11 fixes Source Control and the optional Phase 12 sets up GitHub.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `VPN check failed` | Connect to Rutgers VPN and re-run. |
| `Permission denied (publickey,...)` after Phase 3 | Fix permissions on Amarel: `ssh amarel-new.hpc.rutgers.edu 'chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'` |
| `expected GLIBC >= v2.28.0` still appears *(legacy CentOS 7 host)* | Phase 8 catches this. If it persists after Phase 8 passes, remove the stale server cache: `ssh amarel.rutgers.edu 'chmod -R u+w ~/.vscode-server/cli && rm -rf ~/.vscode-server/cli'`. On RHEL 9.6 (amarel-new) this error should not appear at all. |
| Tarball download fails | GitHub release not yet published, or your network blocks GitHub. Rebuild locally: `./scripts/build-sysroot.sh` (requires Docker). |
| Env vars not loading in non-interactive shells | Check `~/.bashrc` on Amarel for an early `return` that skips the source line — move the sysroot block to the top. |
| Extension install fails (`signature verification failed`) | On legacy CentOS 7, Phase 9 handles this and is idempotent — re-run from Phase 9. On RHEL 9.6 it's rare; merge `"extensions.verifySignature": false` into `~/.vscode-server/data/Machine/settings.json` by hand. |
| Host fingerprint doesn't match OARC's published value | **Stop immediately. Possible MITM attack. Contact OARC.** |
| Source Control shows "no Git repository" / "Initialize Repository" on a real clone | VS Code Server is using CentOS 7's git 1.8.3.1, too old for its repo probe. Phase 11 sets `git.path` to a modern git in the remote Machine settings (on Amarel, `module use /projects/community/modulefiles` then `module load git` — the git modules aren't on the default `MODULEPATH`), then self-tests that VS Code will detect repos; `setup.sh` / `setup.ps1` apply and self-test it automatically. **On RHEL 9.6 (amarel-new) the system git (~2.43) already passes the probe, so Phase 11 writes nothing.** Deep dive: [docs/source-control-git-fix.md](docs/source-control-git-fix.md). |
| Push rejected with `GH007` | Only happens when GitHub's "Keep my email address private" is on. Use your no-reply email (safe on any account), then re-stamp the commit: `git config --global user.email <id>+<user>@users.noreply.github.com && git commit --amend --reset-author --no-edit`, then push. Phase 12 covers GitHub auth + identity for both private and non-private accounts. |

---

## Security

Your credentials never enter the LLM's process:

| Material | Where it goes | LLM can read it? |
|---|---|---|
| Amarel password | Typed into `ssh-copy-id` TTY → encrypted to Amarel sshd | **No** |
| SSH key passphrase | Typed into `ssh-add` → stored in OS keychain | **No** |
| Private key (`id_ed25519_amarel`) | Encrypted on disk | Forbidden by the skill |
| Public key (`.pub`) | On disk; uploaded to Amarel | Yes — it's public by design |

The skill is forbidden from using `sshpass`, `expect`, `security find-generic-password`, or any other helper that could pipe a secret through the LLM's process. After Phase 5, all SSH/SCP calls use `BatchMode=yes` — if key auth fails they error loudly rather than silently prompting for a password.

The sysroot tarball is SHA-256 pinned in `assets/checksums.txt` and verified before extraction. Builds are reproducible via Docker (`scripts/build-sysroot.sh`).

---

## Architecture

```
   YOUR LAPTOP (macOS / Windows)                         AMAREL (CentOS 7)
┌───────────────────────────────┐                ┌────────────────────────────┐
│  VS Code (the desktop app)    │                │  VS Code Server            │
│   + Remote-SSH extension      │                │  ─ Headless Node.js        │
│            │                  │                │  ─ Lives in ~/.vscode-server│
│            │ shells out to    │                │  ─ Patched at startup      │
│            ▼                  │                │    against glibc 2.28      │
│  OpenSSH (ssh, scp)           │   SSH tunnel   │    from the sysroot        │
│            │                  │ ◄─────────────►│    this skill installs     │
│            ▼                  │                └────────────────────────────┘
│  ssh-agent ◄── OS keychain    │
└───────────────────────────────┘
```

The sysroot (`vscode-sysroot-x86_64-linux-gnu.tgz`) contains glibc 2.28 +
libstdc++ + patchelf 0.18, extracted into `$HOME` on Amarel. Three env vars
written to `~/.bashrc` tell VS Code's bootstrap to patchelf its node binary
against this sysroot on every server start. This is
[Microsoft's documented workaround](https://code.visualstudio.com/docs/remote/faq#_can-i-run-vs-code-server-on-older-linux-distributions)
for running VS Code Server on older glibc systems.

---

## Maintainer notes

### Releasing a new sysroot tarball

```bash
./scripts/build-sysroot.sh    # produces build/vscode-sysroot-x86_64-linux-gnu.tgz
# paste the printed SHA-256s into assets/checksums.txt, then:
git add assets/checksums.txt
git commit -m "checksums: bump to vX.Y.Z"
git push
gh release create vX.Y.Z build/vscode-sysroot-x86_64-linux-gnu.tgz \
   --title "vX.Y.Z" --notes "Built from ursetto/vscode-sysroot @ <commit>"
```

**CI alternative (recommended on Apple Silicon):** push a `vX.Y.Z` tag or
run the **Build and release sysroot tarball** workflow from the Actions tab.
The workflow builds on a native x86_64 runner (avoiding the arm64/QEMU GMP
failure on Apple Silicon) and publishes the release automatically.

### Publishing to the plugin marketplace

The repo is its own Claude Code plugin marketplace. Two manifests under
`.claude-plugin/` drive it:

- `.claude-plugin/marketplace.json` — the marketplace (`name: amarel-vscode`)
  with one plugin entry whose `source` is `"./"` (the repo root).
- `.claude-plugin/plugin.json` — the plugin manifest (`name: amarel-vscode`).
  The `skills/amarel-vscode-setup/` skill is auto-discovered; no `skills` key
  is needed.

To cut a plugin release, bump `version` in **both** `.claude-plugin/plugin.json`
and the `plugins[0]` entry of `.claude-plugin/marketplace.json` (keep them
identical — `claude plugin tag` validates that they agree, and `plugin.json`
wins silently if they differ), then commit and push. Users pick up the new
version via `/plugin marketplace update amarel-vscode`. Validate locally with
`claude plugin validate --strict .` before pushing.

### Keeping the runbooks in sync

`skills/amarel-vscode-setup/SKILL.md` (Claude Code) and `AGENTS.md` (Codex / Cursor / Cline) must stay
logically byte-identical in all non-framework-specific sections. `GEMINI.md`
is a thin pointer — update only if phase numbers change. If you edit one
runbook, edit all three.

### Adding a new platform

1. Add `scripts/setup-<platform>.sh` (or `.ps1`).
2. Update `skills/amarel-vscode-setup/SKILL.md` and `AGENTS.md` to dispatch on the new platform.
3. Update the Prerequisites table in this README.

### Pinning `ursetto/vscode-sysroot`

`scripts/build-sysroot.sh` pins `URSETTO_COMMIT` to a specific SHA so two
maintainers running the same script produce identical tarballs. Bump the SHA
explicitly after auditing upstream changes; never let it default back to `main`.

---

## License

[MIT](LICENSE).
