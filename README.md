# amarel-vscode

Fix the **`expected GLIBC >= v2.28.0`** error and set up VS Code Remote-SSH
for the Rutgers Amarel HPC cluster — in about 5 minutes, with any LLM or no
LLM at all.

After setup you connect to Amarel from VS Code in two clicks and **never type
your Amarel password again**.

---

## Install

### Claude Code or Codex (recommended)

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./install.sh          # macOS / Linux
.\install.ps1         # Windows
```

Restart your session, then:

- **Claude Code:** run `/amarel-vscode-setup`
- **Codex:** ask — *"Set up VS Code Remote-SSH for me on Amarel."*

### Gemini CLI, Cursor, or Cline

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
gemini     # — or open this folder in VS Code with Cursor / Cline active
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
HPC cluster (CentOS 7, glibc 2.17). I'm using this repo:
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
| 6 | Download the glibc 2.28 sysroot tarball from GitHub Releases, verify SHA-256 |
| 7 | Copy the tarball to Amarel, extract it, wire up `~/.bashrc` |
| 8 | Verify the glibc env vars load in a non-interactive SSH session |
| 9 | Write `"extensions.verifySignature": false` to VS Code Server's settings on Amarel — required for extensions to install on CentOS 7 with the patched node binary |
| 10 | Print the VS Code GUI steps — connect and you're done |

After Phase 10: **VS Code → Remote-SSH: Connect to Host → `amarel.rutgers.edu`**

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `VPN check failed` | Connect to Rutgers VPN and re-run. |
| `Permission denied (publickey,...)` after Phase 3 | Fix permissions on Amarel: `ssh amarel.rutgers.edu 'chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'` |
| `expected GLIBC >= v2.28.0` still appears | Phase 8 catches this. If it persists after Phase 8 passes, remove the stale server cache: `ssh amarel.rutgers.edu 'chmod -R u+w ~/.vscode-server/cli && rm -rf ~/.vscode-server/cli'` |
| Tarball download fails | GitHub release not yet published, or your network blocks GitHub. Rebuild locally: `./scripts/build-sysroot.sh` (requires Docker). |
| Env vars not loading in non-interactive shells | Check `~/.bashrc` on Amarel for an early `return` that skips the source line — move the sysroot block to the top. |
| Extension install fails (`signature verification failed`) | Phase 9 handles this and is idempotent — re-run the skill from Phase 9. |
| Host fingerprint doesn't match OARC's published value | **Stop immediately. Possible MITM attack. Contact OARC.** |

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

### Keeping the runbooks in sync

`SKILL.md` (Claude Code) and `AGENTS.md` (Codex / Cursor / Cline) must stay
logically byte-identical in all non-framework-specific sections. `GEMINI.md`
is a thin pointer — update only if phase numbers change. If you edit one
runbook, edit all three.

### Adding a new platform

1. Add `scripts/setup-<platform>.sh` (or `.ps1`).
2. Update `SKILL.md` and `AGENTS.md` to dispatch on the new platform.
3. Update the Prerequisites table in this README.

### Pinning `ursetto/vscode-sysroot`

`scripts/build-sysroot.sh` pins `URSETTO_COMMIT` to a specific SHA so two
maintainers running the same script produce identical tarballs. Bump the SHA
explicitly after auditing upstream changes; never let it default back to `main`.

---

## License

[MIT](LICENSE).
