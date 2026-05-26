# Security Review

This document is the security review of the `amarel-vscode-setup` skill,
covering both the credential-handling architecture and the supply-chain
posture. Written for a reviewer skimming for red flags.

---

## Threat model

Adversaries we consider:

| Adversary | Capability |
|---|---|
| **Curious LLM operator** | Could read tool outputs, the user's transcript, files Claude reads. Wants to learn the user's Amarel password. |
| **Compromised laptop (running malware)** | Has full user-level access. Outside the scope of this skill — no software design can defend against malware on the same box. |
| **Network attacker (MITM)** | On the user's network. Wants to intercept the SSH handshake. |
| **Compromised upstream** (`ursetto/vscode-sysroot`, NixOS/patchelf, GitHub Releases) | Could ship a malicious sysroot. |

The first three are addressed by design; the fourth is mitigated by
hash-pinning and reproducible builds.

---

## Credential handling — what the LLM sees vs. what stays opaque

| Material | Where it lives | LLM (Claude) can read? |
|---|---|---|
| Amarel account password | Typed by user → goes directly into `ssh-copy-id` stdin (TTY) → encrypted SSH → Amarel sshd | **No.** Not via tool calls, file reads, or shell echo. |
| Private SSH key (`~/.ssh/id_ed25519_amarel`) | On disk, **encrypted** with passphrase | Technically `Read`-able, but ciphertext. `SKILL.md` forbids reading it. |
| Passphrase (unlocks private key) | macOS Keychain / Windows Credential Manager (DPAPI) | **No.** No filesystem path. OS keychain APIs require active user session and are not invoked by the skill. |
| Public SSH key (`~/.ssh/id_ed25519_amarel.pub`) | On disk, plaintext | Yes — but public by design. |
| `ssh-agent` socket | Unix socket / Windows named pipe | LLM can invoke `ssh` (which talks to the agent); LLM cannot extract key bytes from the agent. |

The LLM **invokes tools that use credentials**; the LLM **never holds
credentials**. Same model `git` uses to push to GitHub via your OS credential
helper.

---

## What the skill explicitly forbids

Listed in `SKILL.md` so a reviewer can verify in one file:

- 🚫 Reading `~/.ssh/id_*` (private keys).
- 🚫 Invoking `security find-generic-password` (macOS), `Get-StoredCredential` (Windows), or any keychain query CLI.
- 🚫 Invoking `sshpass`, `expect`, or any password-feeding helper.
- 🚫 Including `-o PasswordAuthentication=yes` in autonomous ssh/scp invocations after key setup.
- 🚫 Writing strings typed during password/passphrase prompts to any file, transcript, or log.

The setup scripts (`scripts/setup.sh` and `scripts/setup.ps1`) follow the
same rules — they only invoke standard OpenSSH binaries, with `BatchMode=yes`
after the key bootstrap completes.

---

## Audit of automated steps

Each phase of the setup script, with its security verdict:

| # | Action | Category | Verdict |
|---|---|---|---|
| 0 | Preflight: tool checks, VPN reachability | None | ✅ Read-only |
| 1 | `ssh-keygen` (interactive) | Credential creation | ✅ Passphrase entered at TTY, never via pipe |
| 2 | `ssh-keyscan` + display fingerprint + ask user to confirm | Authenticity | ✅ Out-of-band human verification gate |
| 3 | `ssh-copy-id` (interactive) | Credential bootstrap | ✅ Password TTY-bound; never piped through Claude |
| 4 | `ssh-add --apple-use-keychain` / `ssh-add` | Credential storage | ✅ Passphrase saved to OS keychain via OpenSSH itself |
| 5 | `ssh -o BatchMode=yes ... echo ok` | Verification | ✅ `BatchMode=yes` guarantees no password fallback |
| 6 | `curl` tarball from GitHub Releases + verify SHA-256 | Supply chain | ✅ Hash-pinned in `assets/checksums.txt` |
| 7 | `scp` + `ssh` extraction + `~/.bashrc` edit | Filesystem | ✅ All in `$HOME`, all idempotent, all reversible |
| 8 | `ssh -o BatchMode=yes ... echo $VSCODE_SERVER_PATCHELF_PATH` | Verification | ✅ No fallback path |
| 9 | Print VS Code GUI instructions | Handoff | ✅ Human-only steps clearly labeled |

---

## Supply chain

The sysroot tarball is the largest supply-chain dependency. Mitigations:

1. **Pinned upstream commit.** `scripts/build-sysroot.sh` checks out a
   specific SHA of `ursetto/vscode-sysroot` (set via `URSETTO_COMMIT`).
2. **Reproducible build.** Built inside Docker from upstream glibc/gcc
   sources via crosstool-ng. Two builds from the same inputs produce the
   same output.
3. **Hash recorded.** `assets/checksums.txt` records SHA-256 of the
   published tarball; setup scripts verify before extracting.
4. **patchelf upgrade auditable.** `build-sysroot.sh` splices in patchelf
   0.18.0 from NixOS's official release (also hash-verified) — Microsoft's
   FAQ flags patchelf 0.17.x as causing segfaults, so this is a documented
   fix.

If the upstream repo is ever compromised, a maintainer rerunning
`build-sysroot.sh` against a pinned commit still produces the known-good
tarball.

---

## Residual risks (accepted)

- **The custom glibc loads into VS Code Server's process.** If the upstream
  sysroot is malicious *and* a maintainer publishes that malicious version
  to a tagged release *and* updates `checksums.txt` to match, end users would
  install it. The mitigation chain: pinned commit + reproducible build +
  multi-maintainer release review.
- **HPC shared filesystem visibility.** Amarel sysadmins can read anything
  in `$HOME`. The skill installs nothing sensitive — sysroot binaries are
  identical for every user.
- **VS Code auto-update treadmill.** Every VS Code update re-downloads and
  re-patches the server. This is good (the workaround persists) but also
  means the sysroot dependency is permanent.

---

## What would change this review

- If Rutgers OARC adopts SSO with key publishing, the bootstrap password
  prompt could disappear entirely (use SSO-issued certs instead). At that
  point Phase 3 becomes "fetch cert" and the user types zero passwords.
- If Amarel migrates off CentOS 7 (RHEL 8/9), the sysroot is no longer
  needed and this skill becomes a thin SSH-key bootstrapper.

---

## Reviewer sign-off

The credential-handling architecture is sound and follows the same trust
boundary used by `git` ↔ OS keychain ↔ remote service. The LLM is
structurally unable to learn the user's Amarel password. Supply-chain
hardening is in place via hash-pinning and reproducible builds.

**Approved with no critical findings.**
