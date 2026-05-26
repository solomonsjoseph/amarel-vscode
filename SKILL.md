---
name: amarel-vscode-setup
description: |
  Set up VS Code Remote-SSH against the Rutgers Amarel HPC cluster (CentOS 7,
  glibc 2.17) using a custom-glibc sysroot. Handles SSH key auth, OS keychain
  integration, sysroot deployment to the user's $HOME on Amarel, and ~/.bashrc
  wiring. Idempotent and safe to re-run. Requires Rutgers VPN connection and
  a valid Amarel account.
---

# amarel-vscode-setup

You are guiding a developer through installing VS Code Remote-SSH access to
the Rutgers Amarel HPC cluster. Amarel runs CentOS 7 (glibc 2.17), while VS
Code Server 1.99+ requires glibc 2.28 — so this skill deploys a custom-built
sysroot into the user's `$HOME` and configures `~/.bashrc` to point VS Code
at it.

## Run order

1. Confirm prerequisites with the user (one bulleted check, no questions):
   - Valid Amarel account + password
   - Connected to Rutgers VPN right now
   - VS Code installed locally with the Remote-SSH extension
2. Detect platform:
   - macOS / Linux → run `scripts/setup.sh`
   - Windows → run `scripts/setup.ps1`
3. Stream the script's output back to the user verbatim.
4. The script handles every interactive step on its own (it prompts the user
   directly for things like passphrases). Your job is to launch it, surface
   errors clearly, and answer any "what does this mean?" questions.

## What the script does (so you can explain it if asked)

| Phase | Action | Human input needed? |
|-------|--------|---------------------|
| 0 | Preflight: check ssh tools, VS Code, VPN reachability | No |
| 1 | Generate `~/.ssh/id_ed25519_amarel` if missing | Yes — passphrase typed into ssh-keygen |
| 2 | Show Amarel host fingerprint, ask user to verify | Yes — out-of-band check + y/N |
| 3 | `ssh-copy-id` (or Windows equivalent) | Yes — Amarel password typed once |
| 4 | `ssh-add --apple-use-keychain` (Mac) / `ssh-add` (Win) | Yes — passphrase typed once |
| 5 | Verify passwordless SSH with `BatchMode=yes` | No |
| 6 | Download tarball from GitHub Release, verify SHA-256 | No |
| 7 | `scp` tarball + sysroot.sh, extract on Amarel, edit `.bashrc` | No |
| 8 | Verify env vars survive non-interactive SSH | No |
| 9 | Print instructions for VS Code GUI step | Yes — user clicks in VS Code |

Total user-typing during a clean run: **one Amarel password + one key
passphrase + one fingerprint y/N**. After that, zero passwords forever.

## Security constraints — these are non-negotiable

You **MUST NOT**:

- Read or `cat` any file under `~/.ssh/id_*` (private key material).
- Invoke `security find-generic-password`, `Get-StoredCredential`, or any
  other tool that queries the OS keychain.
- Invoke `sshpass`, `expect`, or any helper that feeds a password to ssh via
  stdin pipe. The setup script is forbidden from doing this too.
- Add `-o PasswordAuthentication=yes` to any `ssh`/`scp` invocation you
  spawn autonomously. Force `BatchMode=yes` once key auth is in place.
- Write any string the user typed during a password/passphrase prompt to a
  file, to memory, or to the conversation transcript.

If the user reports their password was leaked or something looks suspicious,
stop and tell them to rotate their Amarel password via Rutgers OARC.

## Failure handling

If the setup script exits non-zero:

1. Read the last 30 lines of its output.
2. Identify which phase failed (the script prints `Phase N` headings).
3. Common failures:
   - **Phase 0 VPN check fails** → tell user to connect to Rutgers VPN, re-run.
   - **Phase 2 fingerprint mismatch** → STOP. Possible MITM. Tell user to
     contact OARC.
   - **Phase 3 ssh-copy-id fails** → likely wrong Amarel password. Tell user
     to verify they can log in interactively first.
   - **Phase 6 tarball download fails** → release may not be published yet,
     or network is blocking. Suggest `./scripts/build-sysroot.sh` to rebuild
     (requires Docker).
   - **Phase 8 env var check fails** → `~/.bashrc` on Amarel has an early
     `return` for non-interactive shells. Inspect `head -20 ~/.bashrc` on
     Amarel; the source line must run before any such guard.

After fixing, the user can re-run the skill — every phase is idempotent.

## Final hand-off

When the script reaches Phase 9 it prints the VS Code GUI steps. Repeat them
in chat for emphasis:

> 1. Open VS Code → `Cmd+Shift+P` / `Ctrl+Shift+P`
> 2. Run: `Remote-SSH: Connect to Host`
> 3. Pick `amarel.rutgers.edu`
> 4. First time only: click **Allow** on the OS-unsupported warning

Tell the user to paste back the Remote-SSH Output panel if anything fails.

## References

- Repo + issues: <https://github.com/solomonsjoseph/amarel-vscode>
- Microsoft FAQ (the supported workaround pattern): <https://code.visualstudio.com/docs/remote/faq#_can-i-run-vs-code-server-on-older-linux-distributions>
- ursetto/vscode-sysroot (upstream of the sysroot tarball): <https://github.com/ursetto/vscode-sysroot>
