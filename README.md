# amarel-vscode

LLM-agnostic skill that sets up **VS Code Remote-SSH** against the
**Rutgers Amarel HPC cluster** (CentOS 7, glibc 2.17) using a custom-glibc
sysroot. Fixes the dreaded:

```
expected GLIBC >= v2.28.0 (but found v2.17.0 instead)
```

After running this once, you connect to Amarel from VS Code in 2 clicks
and **never type your Amarel password again**.

**Works with:** Claude Code, OpenAI Codex CLI, Gemini CLI, Cursor, Cline,
bare LLMs (ChatGPT / Claude.ai / Ollama), and **no LLM at all** — the
setup scripts are plain bash / PowerShell.

---

## Quick start (pick one)

### A. No LLM — just run the script

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./scripts/setup.sh                # macOS / Linux
# OR on Windows:
pwsh scripts/setup.ps1
```

### B. Claude Code (slash command)

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./install.sh                       # or: .\install.ps1   on Windows
# Restart Claude Code, then:
/amarel-vscode-setup
```

### C. Codex CLI / Gemini CLI / Cursor / Cline

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
codex      # or: gemini  /  open the folder in Cursor or VS Code with Cline
```
Then ask the agent: *"Set up VS Code Remote-SSH for me on Amarel."*

Each tool picks up its own instruction file (`AGENTS.md`, `GEMINI.md`,
`.cursor/rules/`, `.clinerules`) — all defer to `AGENTS.md` for the
canonical runbook.

### D. ChatGPT, Claude.ai, Ollama, LM Studio, etc.

See [`docs/using-other-llms.md`](docs/using-other-llms.md) for a copy-paste
prompt template. The TL;DR: paste `AGENTS.md`'s contents into your chat as
context and ask the model to walk you through it.

Total time on any path: ~5 min. You'll type your Amarel password exactly
**once** and your SSH key passphrase exactly **once**. After that the OS
keychain handles auth.

---

## Prerequisites

Regardless of which path you pick:

1. **Valid Rutgers Amarel account.** If you don't have one, request access via OARC.
2. **Connected to the Rutgers VPN.** The VPN gateway is where 2FA / Duo happens — once you're inside the VPN, Amarel doesn't re-challenge for 2FA on SSH connections.
3. **VS Code installed** with the **Remote-SSH** extension (`ms-vscode-remote.remote-ssh`).
4. **OpenSSH client tools.** Ship by default on macOS and Windows 10/11 (1809+) — no install needed for 99% of users.

The setup script checks all four and aborts with a friendly message if
anything's missing.

---

## What it does

| Phase | Action |
|-------|--------|
| 0 | Preflight (tools, VPN reachability, VS Code) |
| 1 | Generate SSH keypair (`~/.ssh/id_ed25519_amarel`) — you pick the passphrase |
| 2 | Show Amarel's host fingerprint, ask you to verify against Rutgers OARC's published value |
| 3 | `ssh-copy-id` — installs your public key on Amarel (one Amarel password prompt) |
| 4 | `ssh-add --apple-use-keychain` (Mac) / `ssh-add` (Windows) — passphrase saved to OS keychain |
| 5 | Verify passwordless SSH works (`BatchMode=yes`, no fallback to password) |
| 6 | Download sysroot tarball from GitHub Release, verify SHA-256 |
| 7 | `scp` tarball to Amarel, extract under `~/.vscode-server/sysroot/`, edit `~/.bashrc` |
| 8 | Verify env vars survive a non-interactive SSH session |
| 9 | Print VS Code GUI steps |

After phase 9, open VS Code → **Remote-SSH: Connect to Host** → `amarel.rutgers.edu`. Done.

---

## Security model

Passwords are typed by you, into the OS terminal, never visible to the LLM
or to any helper process. Specifically:

| Material | Lives where | Claude can read? |
|---|---|---|
| Amarel password | Typed once into `ssh-copy-id` TTY → sent to Amarel sshd | **No.** TTY-attached prompt. |
| Private SSH key | `~/.ssh/id_ed25519_amarel`, encrypted with passphrase | Forbidden by `SKILL.md`. |
| Key passphrase | macOS Keychain / Windows Credential Manager (DPAPI) | **No.** Filesystem-inaccessible. |
| Public SSH key | `~/.ssh/id_ed25519_amarel.pub`, plaintext | Yes — but it's public by design. |

The setup scripts are forbidden from invoking `sshpass`, `expect`, the
`security` CLI, or any other helper that could pipe a password through Claude's
process tree. `SKILL.md` codifies these constraints so a reviewer can verify
them by reading one file.

See [`docs/security-review.md`](docs/security-review.md) for the full audit.

---

## Architecture

```
   YOUR LAPTOP (macOS / Windows)                          AMAREL
┌────────────────────────────────┐                ┌─────────────────────────┐
│  VS Code (the desktop app)     │                │                         │
│   + Remote-SSH extension       │                │  VS Code Server         │
│         │                      │                │  ─ Headless Node.js     │
│         │ shells out to        │                │  ─ Lives in             │
│         ▼                      │                │    ~/.vscode-server/    │
│  OpenSSH (`ssh`, `scp`)        │   SSH tunnel   │  ─ Patched at startup   │
│         │                      │ ◄─────────────►│    against glibc 2.28   │
│         │ key auth via         │                │    from the sysroot we  │
│         ▼                      │                │    install              │
│  ssh-agent ◄── OS keychain     │                │                         │
└────────────────────────────────┘                └─────────────────────────┘
```

The sysroot is a tarball containing glibc 2.28 + libstdc++ + patchelf 0.18,
extracted into the user's `$HOME` on Amarel. Three env vars
(`VSCODE_SERVER_CUSTOM_GLIBC_LINKER`, `..._PATH`, `VSCODE_SERVER_PATCHELF_PATH`)
tell VS Code's bootstrap to patchelf its node binary against this sysroot.
This is Microsoft's [officially documented workaround](https://code.visualstudio.com/docs/remote/faq#_can-i-run-vs-code-server-on-older-linux-distributions).

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `VPN check failed` | Connect to Rutgers VPN, re-run skill. |
| `Permission denied (publickey,...)` after Phase 3 | Run `ssh -v amarel.rutgers.edu` to see what's blocking. Usually `~/.ssh/authorized_keys` permissions on Amarel — fix with `chmod 600 ~/.ssh/authorized_keys`. |
| `expected GLIBC >= v2.28.0` still appears in Remote-SSH log | Phase 8 of the skill verifies this; if it passed and VS Code still errors, you likely have a stale `~/.vscode-server` from a previous attempt. Remove it: `ssh amarel.rutgers.edu 'chmod -R u+w ~/.vscode-server/cli && rm -rf ~/.vscode-server/cli'` and try again. |
| Tarball download fails | The maintainer hasn't published a release yet, or your network blocks GitHub. Rebuild locally: `./scripts/build-sysroot.sh` (requires Docker). |
| Env vars not loading in non-interactive shells | Inspect `head -20 ~/.bashrc` on Amarel — there's an early `return` skipping the source line. Move the source line to the top of `.bashrc`. |
| Fingerprint doesn't match Rutgers's published value | **Stop.** Possible MITM. Contact OARC. |

---

## Maintainer notes

### Releasing a new sysroot tarball

```bash
./scripts/build-sysroot.sh             # produces build/vscode-sysroot-x86_64-linux-gnu.tgz
# Update assets/checksums.txt with the SHA-256 the script prints
git add assets/checksums.txt
git commit -m "checksums: bump to vX.Y.Z"
git push
gh release create vX.Y.Z build/vscode-sysroot-x86_64-linux-gnu.tgz \
   --title "vX.Y.Z" --notes "Built from ursetto/vscode-sysroot @ <commit>"
```

The setup script downloads from `releases/latest/download/...`, so a freshly
published release becomes the default for new users automatically.

### Adding a new platform

1. Add `scripts/setup-<platform>.sh` (or `.ps1`).
2. Update `SKILL.md` to dispatch on the new platform.
3. Update the prerequisite table in this README.

### Pinning ursetto/vscode-sysroot

`scripts/build-sysroot.sh` has `URSETTO_COMMIT="${URSETTO_COMMIT:-main}"` —
replace `main` with a specific SHA before tagging a release so the build is
reproducible.

---

## License

[MIT](LICENSE).
