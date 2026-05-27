# AGENTS.md — canonical instructions for any LLM coding agent

This file is read automatically by:

- **OpenAI Codex CLI** (`codex`, project-level instructions)
- **Cursor** (newer versions, alongside `.cursor/rules/`)
- **Cline** (VS Code extension, alongside `.clinerules`)
- Most agent frameworks following the [AGENTS.md convention](https://agents.md)

For framework-specific entrypoints that ultimately defer to this file, see:

- `SKILL.md` — Claude Code (with YAML frontmatter for slash-command discovery)
- `GEMINI.md` — Google Gemini CLI / Gemini Code Assist

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

The user's role: connect to Rutgers VPN, run terminal commands you give them
one at a time, type their Amarel password once (into the OS terminal, not
visible to you), accept their host fingerprint, type their SSH key passphrase
once.

Your role: hand the user **one command at a time**, wait for them to paste
the result, confirm success or diagnose failures, then hand them the next
command. **You do not execute these commands yourself.**

## How to run this skill (read this first)

For every phase below:

1. Print a one-line description of what the phase does.
2. Give the user the exact command(s) in a fenced code block they can copy.
3. Tell them what success looks like (the success marker).
4. Tell them what to paste back to you (last few lines is usually enough).
5. **Wait for the user's response before advancing.** Do not chain phases.
6. If the user pastes an error, diagnose using the "if you see…" notes in
   that phase, suggest the fix, and have them re-run the phase. Phases are
   idempotent.

If the user says "just run the script for me," point them at the one-shot
fallback in the **Power-user path** section near the end of this file.

### Before you start — confirm prerequisites (do not ask, just list)

> Before we begin, confirm you have:
> 1. A valid Amarel account + password (test it works via Rutgers webmail or OARC portal if unsure).
> 2. The Rutgers VPN connected right now (Cisco AnyConnect or GlobalProtect, depending on your campus).
> 3. VS Code installed locally with the Remote-SSH extension (`ms-vscode-remote.remote-ssh`).
> 4. A local terminal. Phase 0 will detect whether it is macOS, Linux, or Windows.
>
> Reply with your Amarel username (NetID, e.g. `abc123`) and I'll start with Phase 0.

Substitute the user's NetID inline for every `<NetID>` placeholder before
showing each command — don't make the user edit the snippets.

Do **not** ask the user which operating system they are on. Infer it from
agent/runtime context if the tool gives you that information. Otherwise,
Phase 0 detects it. After Phase 0, record `LOCAL_OS` as `macOS`, `Linux`, or
`Windows`, and use that value to choose every OS-specific command below. If a
POSIX command clearly lands in PowerShell, switch to the Windows command and
continue; do not ask the user to self-identify their OS.

---

## Phase 0 — Preflight

**Goal:** Detect the user's local OS, confirm OpenSSH tools are present, and
confirm Amarel is reachable on the VPN.

**macOS / Linux shell — run:**

```bash
case "$(uname -s)" in
  Darwin) echo "✓ OS: macOS" ;;
  Linux) echo "✓ OS: Linux" ;;
  *) echo "✗ OS: unsupported ($(uname -s))" ;;
esac
for c in ssh scp ssh-keygen ssh-add ssh-copy-id ssh-keyscan nc; do
  command -v "$c" >/dev/null && echo "✓ $c" || echo "✗ $c MISSING"
done
nc -z -w 5 amarel.rutgers.edu 22 && echo "✓ VPN: Amarel reachable" || echo "✗ VPN: cannot reach amarel.rutgers.edu:22"
```

**Windows PowerShell — run:**

```powershell
"✓ OS: Windows"
foreach ($c in 'ssh','scp','ssh-keygen','ssh-add','ssh-keyscan') {
  if (Get-Command $c -ErrorAction SilentlyContinue) { "✓ $c" } else { "✗ $c MISSING" }
}
if (Test-NetConnection amarel.rutgers.edu -Port 22 -InformationLevel Quiet) { "✓ VPN: Amarel reachable" } else { "✗ VPN: cannot reach amarel.rutgers.edu:22" }
```

**Success:** the OS line is `✓ OS: macOS`, `✓ OS: Linux`, or `✓ OS:
Windows`, and every other line begins with `✓`.

**If you see** `✗ ... MISSING`: on macOS/Linux install `openssh-client`; on Windows install OpenSSH client via *Settings → Apps → Optional features*. Windows lacks `ssh-copy-id` by default — Phase 3 has a manual workaround.

**If you see** `✗ VPN`: connect to the Rutgers VPN and re-run.

**Ask the user to paste the output. Record `LOCAL_OS` from the OS line, then
advance.**

---

## Phase 1 — Generate the Amarel SSH key

**Goal:** Create `~/.ssh/id_ed25519_amarel` (a dedicated key for Amarel only — keeps it separate from any GitHub key you may have).

**First, check if it already exists:**

```bash
test -f ~/.ssh/id_ed25519_amarel && echo "EXISTS — skip Phase 1" || echo "MISSING — run keygen below"
```

If `EXISTS`, skip to Phase 2.

**If `MISSING`, run:**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_amarel -C "amarel-vscode-$(whoami)@$(hostname)"
```

**Windows (PowerShell):**

```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519_amarel -C "amarel-vscode-$env:USERNAME@$env:COMPUTERNAME"
```

> **🔒 YOUR TURN:** `ssh-keygen` will prompt twice for a passphrase. Pick a
> strong one you'll remember — you'll type it exactly once more (in Phase 4),
> and then the OS keychain remembers it forever. **I cannot see what you type.**

**Success:** `Your identification has been saved in /Users/<you>/.ssh/id_ed25519_amarel`.

**Ask the user to confirm both files exist:**

```bash
ls -l ~/.ssh/id_ed25519_amarel ~/.ssh/id_ed25519_amarel.pub
```

Then advance.

---

## Phase 2 — Verify Amarel's host fingerprint

**Goal:** Pin Amarel's SSH host key in `~/.ssh/known_hosts` *after* the user
verifies the fingerprint out-of-band. This is the only protection against
MITM on the first connection.

**Check if Amarel is already in known_hosts:**

```bash
grep -E "^amarel\.rutgers\.edu |^\|1\|" ~/.ssh/known_hosts 2>/dev/null | grep -q amarel && echo "ALREADY TRUSTED — skip Phase 2" || echo "NEEDS VERIFICATION"
```

If `ALREADY TRUSTED`, skip to Phase 3.

**If `NEEDS VERIFICATION`, fetch and display the fingerprint:**

```bash
ssh-keyscan -t ed25519 amarel.rutgers.edu 2>/dev/null | tee /tmp/amarel_hostkey | ssh-keygen -lf -
```

**Success:** the command prints a line like
`256 SHA256:cN6l3kR3jbdOv6Ofz1b+KNCt3LaOCj9bq6yeHoR3eLs amarel.rutgers.edu (ED25519)`.

> **🔒 YOUR TURN:** Compare that `SHA256:…` value against Rutgers OARC's
> published fingerprint (check their website or your account-activation
> email). The reference fingerprint recorded by this skill on 2026-05-26 is:
>
> ```
> SHA256:cN6l3kR3jbdOv6Ofz1b+KNCt3LaOCj9bq6yeHoR3eLs
> ```
>
> Only continue if your output matches. **A mismatch means a possible
> man-in-the-middle attack — STOP and contact OARC.**

**If it matches, the user runs:**

```bash
cat /tmp/amarel_hostkey >> ~/.ssh/known_hosts && rm /tmp/amarel_hostkey && echo "✓ host key trusted"
```

**Wait for confirmation, then advance.**

---

## Phase 3 — Install your public key on Amarel

**Goal:** Copy `id_ed25519_amarel.pub` into Amarel's `~/.ssh/authorized_keys`
so future logins use the key instead of a password.

**Check if key auth already works** (substitute the user's NetID for `<NetID>`):

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_amarel <NetID>@amarel.rutgers.edu true && echo "ALREADY WORKS — skip Phase 3" || echo "NEEDS ssh-copy-id"
```

If `ALREADY WORKS`, skip to Phase 4.

**macOS / Linux — run:**

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_amarel.pub -o PreferredAuthentications=password -o PubkeyAuthentication=no <NetID>@amarel.rutgers.edu
```

> **🔒 YOUR TURN:** `ssh-copy-id` will prompt for your **Amarel password**.
> Type it once. This is the only time. **I cannot see what you type.**

**Windows (no `ssh-copy-id`) — run instead:**

```powershell
Get-Content $HOME\.ssh\id_ed25519_amarel.pub | ssh <NetID>@amarel.rutgers.edu "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

> **🔒 YOUR TURN:** `ssh` will prompt for your Amarel password once. Type it
> into the terminal.

**Verify it worked (no password should be required this time):**

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_amarel <NetID>@amarel.rutgers.edu 'echo ✓ key auth works'
```

**Success:** `✓ key auth works`.

**If you see** `Permission denied (publickey…)`: the key install didn't take. Have the user log in interactively (`ssh <NetID>@amarel.rutgers.edu`) and check that `~/.ssh/authorized_keys` on Amarel has a line ending in `amarel-vscode-…`. Permissions must be `600 ~/.ssh/authorized_keys` and `700 ~/.ssh`.

**Ask the user to paste the verify output, then advance.**

---

## Phase 4 — Save the passphrase to the OS keychain

**Goal:** Add the key to `ssh-agent` so future SSH calls don't prompt for the
passphrase. On macOS the agent persists the passphrase in the Keychain across
reboots; on Linux a session-scoped agent (gnome-keyring / KWallet) handles it.

**macOS — run:**

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_amarel
```

**Linux — run:**

```bash
ssh-add ~/.ssh/id_ed25519_amarel
```

**Windows — first ensure the agent is running, then add the key:**

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $HOME\.ssh\id_ed25519_amarel
```

> **🔒 YOUR TURN:** `ssh-add` will prompt for your **key passphrase** (the
> one you picked in Phase 1). After this, the OS keychain stores it.
> **I cannot see what you type.**

**Then append a `~/.ssh/config` block so VS Code's `ssh` always finds the right key** (substitute the user's NetID for `<NetID>`):

```bash
cat >> ~/.ssh/config <<EOF

# Added by amarel-vscode skill on $(date +%F)
Host amarel.rutgers.edu
  User <NetID>
  IdentityFile ~/.ssh/id_ed25519_amarel
  IdentitiesOnly yes
  AddKeysToAgent yes
  UseKeychain yes
EOF
chmod 600 ~/.ssh/config
```

> **Linux note:** omit the `UseKeychain yes` line — it's macOS-only.
>
> **Windows note:** the equivalent config file lives at `$HOME\.ssh\config` (use a text editor, or `Add-Content`).

**Confirm the key is loaded:**

```bash
ssh-add -l | grep amarel-vscode && echo "✓ key in agent"
```

**Wait for confirmation, then advance.**

---

## Phase 5 — Verify passwordless SSH end-to-end

**Goal:** Prove that a non-interactive `ssh` succeeds with no prompts.
This is what VS Code's Remote-SSH will use.

**Run:**

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 amarel.rutgers.edu 'echo ok; hostname; whoami'
```

**Success:** three lines — `ok`, an Amarel login-node hostname (e.g. `amarel1`), and your NetID.

**If it hangs or errors:** the agent doesn't have the key loaded — re-run Phase 4. If `ssh -v amarel.rutgers.edu` (without `BatchMode`) shows `Authentications that can continue: publickey,…` and then fails, the `authorized_keys` permissions on Amarel are wrong — run `ssh amarel.rutgers.edu 'chmod 600 ~/.ssh/authorized_keys; chmod 700 ~/.ssh'`.

**Wait for the three success lines, then advance.**

---

## Phase 6 — Download and verify the sysroot tarball

**Goal:** Fetch the prebuilt glibc-2.28 sysroot from this repo's GitHub
Release into `build/` and verify its SHA-256 against `assets/checksums.txt`.

**Run from inside the cloned `amarel-vscode` repo directory:**

```bash
mkdir -p build
curl -fL --progress-bar \
  https://github.com/solomonsjoseph/amarel-vscode/releases/latest/download/vscode-sysroot-x86_64-linux-gnu.tgz \
  -o build/vscode-sysroot-x86_64-linux-gnu.tgz
```

**Then verify SHA-256:**

```bash
EXPECTED=$(awk '$2=="vscode-sysroot-x86_64-linux-gnu.tgz" {print $1}' assets/checksums.txt)
ACTUAL=$(shasum -a 256 build/vscode-sysroot-x86_64-linux-gnu.tgz | awk '{print $1}')
if [ -z "$EXPECTED" ] || echo "$EXPECTED" | grep -qE '^0+$'; then
  echo "! No checksum recorded yet (maintainer hasn't populated assets/checksums.txt) — skipping verify"
elif [ "$EXPECTED" = "$ACTUAL" ]; then
  echo "✓ SHA-256 matches"
else
  echo "✗ SHA-256 MISMATCH — refusing to continue"; echo "  expected: $EXPECTED"; echo "  actual:   $ACTUAL"
fi
```

**Also verify the tarball isn't corrupt:**

```bash
tar tzf build/vscode-sysroot-x86_64-linux-gnu.tgz >/dev/null && echo "✓ tarball is well-formed" || echo "✗ tarball is corrupt — delete and re-download"
```

**Success:** `✓ SHA-256 matches` (or the `! No checksum recorded yet` note) **and** `✓ tarball is well-formed`.

**If you see** `✗ SHA-256 MISMATCH`: **STOP.** Do not extract. Either the download was tampered with or the maintainer's `checksums.txt` is stale. Tell the user to file an issue.

**If you see** `✗ tarball is corrupt`: `rm build/vscode-sysroot-x86_64-linux-gnu.tgz` and re-run Phase 6.

**Ask the user to paste the verify output, then advance.**

---

## Phase 7 — Deploy the sysroot on Amarel

**Goal:** Upload the tarball + `assets/sysroot.sh`, extract into
`~/.vscode-server/sysroot/`, and wire one line into `~/.bashrc`.

**Upload both files (still inside the repo dir):**

```bash
scp build/vscode-sysroot-x86_64-linux-gnu.tgz amarel.rutgers.edu:~/
scp assets/sysroot.sh amarel.rutgers.edu:~/
```

**Then extract + configure on Amarel via a single SSH heredoc:**

```bash
ssh amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail

# Idempotent cleanup of any prior half-installed server
if [ -d "$HOME/.vscode-server/sysroot" ]; then chmod -R u+w "$HOME/.vscode-server" 2>/dev/null || true; fi
rm -rf "$HOME/.vscode-server/cli" "$HOME/.vscode-server/extensions" 2>/dev/null || true

mkdir -p "$HOME/.vscode-server"
if [ ! -d "$HOME/.vscode-server/sysroot" ]; then
  tar zxf "$HOME/vscode-sysroot-x86_64-linux-gnu.tgz" -C "$HOME/.vscode-server"
fi
mv -f "$HOME/sysroot.sh" "$HOME/.vscode-server/sysroot.sh"
rm -f "$HOME/vscode-sysroot-x86_64-linux-gnu.tgz"

# Sanity checks
test -f "$HOME/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2" || { echo "ERR: linker missing"; exit 1; }
test -x "$HOME/.vscode-server/sysroot/usr/bin/patchelf"        || { echo "ERR: patchelf missing or not exec"; exit 1; }
test -f "$HOME/.vscode-server/sysroot.sh"                      || { echo "ERR: sysroot.sh missing"; exit 1; }

# Architecture guard
if command -v file >/dev/null 2>&1; then
  PE_INFO="$(file "$HOME/.vscode-server/sysroot/usr/bin/patchelf")"
  case "$PE_INFO" in
    *x86-64*|*x86_64*) : ;;
    *) echo "ERR: patchelf is not x86_64 — got: $PE_INFO" >&2; exit 1 ;;
  esac
fi

# Wire into ~/.bashrc (only if not already there)
if ! grep -q '\.vscode-server/sysroot\.sh' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'BRC'

# VS Code Server custom glibc workaround (added by amarel-vscode skill)
[ -f "$HOME/.vscode-server/sysroot.sh" ] && source "$HOME/.vscode-server/sysroot.sh"
BRC
fi

echo "✓ sysroot deployed"
REMOTE
```

**Success:** `✓ sysroot deployed`.

**If you see** `ERR: linker missing` / `patchelf missing` / `not x86_64`: the tarball is wrong-arch or corrupt — delete it locally and on Amarel (`ssh amarel.rutgers.edu 'rm -rf ~/.vscode-server/sysroot'`), then re-run Phases 6 and 7.

**Wait for the success line, then advance.**

---

## Phase 8 — Verify env vars survive a non-interactive SSH

**Goal:** Confirm `~/.bashrc` exports the three VS Code env vars even in
non-interactive shells (which is what VS Code's Remote-SSH uses).

**Run:**

```bash
ssh -o BatchMode=yes amarel.rutgers.edu 'echo "$VSCODE_SERVER_PATCHELF_PATH"'
```

**Success:** prints `/home/<NetID>/.vscode-server/sysroot/usr/bin/patchelf` — substitute the user's NetID for `<NetID>`.

**If you see** an empty line: `~/.bashrc` on Amarel has an early `return` for non-interactive shells that runs before the `source` line. Inspect with `ssh amarel.rutgers.edu 'head -20 ~/.bashrc'`. Move the `source` block to the very top of the file and re-run this phase.

**Wait for the correct path, then advance.**

---

## Phase 9 — Disable VS Code extension signature verification on Amarel

**Goal:** VS Code Server's VSIX signature check crashes ("signature
verification failed with UnknownError") when its node is patchelf'd against a
custom glibc on CentOS 7. The documented workaround is to merge
`"extensions.verifySignature": false` into the remote machine settings.
HTTPS to the marketplace still authenticates the download; only the
second-layer VSIX check is skipped.

**Run (the merge is idempotent and preserves any existing settings):**

```bash
ssh amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail
SETTINGS_DIR="$HOME/.vscode-server/data/Machine"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"

python3 - "$SETTINGS_FILE" <<'PY'
import json, os, sys
path = sys.argv[1]
data = {}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            sys.exit(f"ERR: {path} is not valid JSON ({exc}); refusing to overwrite")
    if not isinstance(data, dict):
        sys.exit(f"ERR: {path} root is not a JSON object; refusing to overwrite")
data["extensions.verifySignature"] = False
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=4); f.write("\n")
os.replace(tmp, path)
PY

# Post-write verification
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d.get('extensions.verifySignature') is False, d; print('✓ verified:', json.dumps(d))" "$SETTINGS_FILE"
REMOTE
```

**Success:** `✓ verified: {"extensions.verifySignature": false, ...}` (any pre-existing keys preserved).

**If you see** `ERR: ... is not valid JSON`: the user's existing `settings.json` is malformed. The script refused to touch it — that's correct. Have them `ssh amarel.rutgers.edu 'cat ~/.vscode-server/data/Machine/settings.json'`, fix the syntax in a text editor, then re-run this phase.

**Wait for the verified line, then advance.**

---

## Phase 10 — Connect from VS Code

**Goal:** The user finishes the setup inside the VS Code GUI. You can't do
this for them.

**Print these steps to the user verbatim:**

> 1. Open VS Code.
> 2. `Cmd+Shift+P` (Mac) / `Ctrl+Shift+P` (Win/Linux).
> 3. Type and run: **Remote-SSH: Connect to Host**
> 4. Pick `amarel.rutgers.edu` (or type `<NetID>@amarel.rutgers.edu`).
> 5. First time only: click **Allow** on the "OS unsupported" warning.
>
> After a moment the bottom-left status bar should show:
> **SSH: amarel.rutgers.edu** (green).

**If anything fails:** open *View → Output → Remote-SSH* and paste the log
back to me. Common issues:

- `expected GLIBC >= v2.28.0` → the sysroot deploy didn't take. Re-run Phase 8 to verify the env vars; if they're missing, fix `~/.bashrc` and re-run Phase 7.
- `Permission denied (publickey)` → re-run Phase 5 to confirm key auth works.
- `signature verification failed with UnknownError` when installing an extension → Phase 9 didn't run; re-run it.

**This is the end of the runbook.** If the status bar turns green, ask the
user to confirm and you're done.

---

## Security constraints — non-negotiable

You **MUST NOT**:

- Read or `cat` any file under `~/.ssh/id_*` (private key material).
- Invoke `security find-generic-password`, `Get-StoredCredential`, or any
  other tool that queries the OS keychain.
- Invoke `sshpass`, `expect`, or any helper that feeds a password to ssh via
  stdin pipe. Never suggest these to the user either.
- Add `-o PasswordAuthentication=yes` to any `ssh`/`scp` invocation you
  craft. Once key auth is in place (Phase 3), every command you hand the
  user uses `BatchMode=yes` for the verifies.
- Write any string the user typed during a password/passphrase prompt to a
  file, to memory, or back into the conversation transcript.
- Execute Phases 1–10 *yourself*. Your role is to hand the user commands
  and interpret their output. The user must run every command.

If the user reports their password was leaked or something looks suspicious,
stop and tell them to rotate their Amarel password via Rutgers OARC.

## Power-user path (one-shot script)

If the user wants the whole thing run as a single script instead of
step-by-step, point them at:

```bash
./scripts/setup.sh        # macOS / Linux
pwsh scripts/setup.ps1    # Windows
```

The script does Phases 0–10 in sequence with the same idempotency guarantees
and the same TTY-based prompts for passwords/passphrases. It does not
involve you (the LLM) at all. Recommend this path only if the user
explicitly asks for it.

## Without you (the LLM)

A teammate with no LLM at all can do the whole setup by running:

```bash
git clone https://github.com/solomonsjoseph/amarel-vscode.git
cd amarel-vscode
./scripts/setup.sh        # or pwsh scripts/setup.ps1 on Windows
```

The scripts are self-narrating. Your job as an agent is to walk the user
through the same logical phases manually, command by command, so they see
and consent to each operation. Don't bypass that by running the script for
them.

## References

- Repo + issues: <https://github.com/solomonsjoseph/amarel-vscode>
- Microsoft FAQ (the supported workaround pattern): <https://code.visualstudio.com/docs/remote/faq#_can-i-run-vs-code-server-on-older-linux-distributions>
- ursetto/vscode-sysroot (upstream of the sysroot tarball): <https://github.com/ursetto/vscode-sysroot>
- AGENTS.md convention: <https://agents.md>
