# AGENTS.md — canonical instructions for any LLM coding agent

This file is read automatically by:

- **OpenAI Codex CLI** (`codex`, project-level instructions)
- **Cursor** (newer versions, alongside `.cursor/rules/`)
- **Cline** (VS Code extension, alongside `.clinerules`)
- Most agent frameworks following the [AGENTS.md convention](https://agents.md)

For framework-specific entrypoints that ultimately defer to this file, see:

- `SKILL.md` — Claude Code (with YAML frontmatter for slash-command discovery)
- `GEMINI.md` — Google Gemini CLI / Gemini Code Assist
- `.clinerules` — Cline
- `.cursor/rules/amarel-vscode.mdc` — Cursor (MDC format)

If you're using a **bare LLM** (ChatGPT web, Claude.ai, a local Ollama model, etc.)
with no project-instruction system, see [`docs/using-other-llms.md`](docs/using-other-llms.md)
for a copy-paste prompt.

---

## What this repo does

Sets up VS Code Remote-SSH against the **Rutgers Amarel HPC cluster** (CentOS 7,
glibc 2.17) using a custom-glibc sysroot. VS Code Server 1.99+ requires glibc 2.28
which CentOS 7 cannot provide, so we install a tarball with glibc 2.28 +
libstdc++ + patchelf into the user's `$HOME` on Amarel and wire `~/.bashrc` to
point VS Code at it.

The user's role: connect to Rutgers VPN, type their Amarel password once
(into the OS terminal, not visible to you), accept their host fingerprint, type
their SSH key passphrase once.

Your role: run the platform-appropriate script, surface its output, help
interpret errors.

## Run order

1. Confirm the user has met the prerequisites (do **not** ask — just list them):
   - Valid Amarel account + password
   - Connected to Rutgers VPN right now
   - VS Code installed locally with the Remote-SSH extension
2. Detect platform:
   - **macOS / Linux** → run `bash scripts/setup.sh`
   - **Windows** → run `pwsh scripts/setup.ps1` (or `powershell -File ...` on Windows PowerShell)
3. Stream the script's output back to the user verbatim. The script prints
   colored phase headings (`Phase 0`…`Phase 9`) and `🔒 YOUR TURN` prompts at
   each interactive moment.
4. The script handles every interactive step on its own (it prompts the user
   directly via the OS terminal). Your job: launch it, surface errors clearly,
   answer "what does this mean?" follow-ups.

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

Total user typing during a clean run: **one Amarel password + one key passphrase
+ one fingerprint y/N**. After that, zero passwords forever.

## Security constraints — non-negotiable

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

The scripts enforce these at the bash/PowerShell level — they use OS-native
interactive prompts (ssh-copy-id, ssh-add, ssh-keygen) that write directly
to the TTY, bypassing any pipe an LLM could capture. The deny-list above is
defense-in-depth, not the primary security boundary.

## Failure handling

If the setup script exits non-zero:

1. Read the last ~30 lines of its output.
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

After fixing, the user can re-run the skill/script — every phase is
idempotent.

## Final hand-off

When the script reaches Phase 9 it prints the VS Code GUI steps. Repeat them
in chat for emphasis:

> 1. Open VS Code → `Cmd+Shift+P` / `Ctrl+Shift+P`
> 2. Run: `Remote-SSH: Connect to Host`
> 3. Pick `amarel.rutgers.edu`
> 4. First time only: click **Allow** on the OS-unsupported warning

Tell the user to paste back the Remote-SSH Output panel if anything fails.

## Without you (the LLM)

A teammate with no LLM at all can do the whole setup by running:

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./scripts/setup.sh        # or .\scripts\setup.ps1 on Windows
```

The scripts are self-narrating. Your job as an agent is purely UX: surfacing
output, interpreting errors, walking the user through the same flow they
could do by themselves. Don't introduce extra automation that bypasses what
the scripts already do.

## References

- Repo + issues: <https://github.com/solomonsjoseph/amarel-vscode>
- Microsoft FAQ (the supported workaround pattern): <https://code.visualstudio.com/docs/remote/faq#_can-i-run-vs-code-server-on-older-linux-distributions>
- ursetto/vscode-sysroot (upstream of the sysroot tarball): <https://github.com/ursetto/vscode-sysroot>
- AGENTS.md convention: <https://agents.md>
