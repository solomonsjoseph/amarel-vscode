---
name: amarel-vscode-setup
description: |
  Set up VS Code Remote-SSH against the Rutgers Amarel HPC cluster (CentOS 7,
  glibc 2.17) using a custom-glibc sysroot. Walks the user through the setup
  one terminal command at a time, waiting for their confirmation between
  phases. Handles SSH key auth, OS keychain integration, sysroot deployment
  to the user's $HOME on Amarel, ~/.bashrc wiring, and the VS Code Server
  extension-signature workaround. Idempotent and safe to re-run. Requires
  Rutgers VPN connection and a valid Amarel account.
---

# amarel-vscode-setup

> **Note:** This file is the Claude Code entry point. The same runbook lives
> in [`AGENTS.md`](AGENTS.md) for other agents (Codex, Gemini, Cursor, Cline).
> If you update one, keep them in sync.

You are guiding a developer through installing VS Code Remote-SSH access to
the Rutgers Amarel HPC cluster. Amarel runs CentOS 7 (glibc 2.17), while VS
Code Server 1.99+ requires glibc 2.28 — so this skill deploys a custom-built
sysroot into the user's `$HOME` on Amarel and configures `~/.bashrc` to point
VS Code at it.

## How to run this skill (read this first)

**Phases 1–5 are the SSH key auth dance.** Run each step via Bash yourself
whenever you can — hand the user a command only when it requires a passphrase
or password typed at a TTY, or involves a GUI action. After each TTY-bound
step, wait for the user to confirm it is done, then run a verifying probe
yourself. **Phase 1.0 probes Phases 1–5 in one shot: if key auth already
works AND the `ssh_config` block is correct, skip Phases 1–5 entirely.**

**Platform-neutrality note (applies to every phase):** *Local* commands
(executed on the user's Mac/Linux/Windows box) need per-OS variants — the
runbook provides both bash and PowerShell forms. *Remote* commands (sent into
Amarel via `ssh ... 'bash -se' <<'REMOTE' ... REMOTE`) are platform-neutral:
the here-string travels via stdin and bash executes on Amarel regardless of
local OS. So Phases 7.4–7.8 and 8.1 remote heredocs need no Windows variant;
only the local `ssh`/`scp` invocation line differs.

### Per-phase protocol

For every phase below:

1. Print a one-line description of what the phase does.
2. Give the user the exact command(s) in a fenced code block they can copy.
3. Tell them what success looks like (the success marker).
4. Tell them what to paste back to you (last few lines is usually enough).
5. **Wait for the user's response before advancing.** Do not chain phases.
6. If the user pastes an error, diagnose using the "if you see…" notes in
   that phase, suggest the fix, and have them re-run the phase. Phases are
   idempotent.

**LLM operator rule — single-line TTY hand-offs.** Never present a multi-line or
`\`-continued command in a "🔒 YOUR TURN" block. Terminal paste mangles backslash
continuations (the live run hit exactly this: `ssh-copy-id: ERROR: Too many
arguments`). Collapse every command the user must type to a single line — they all
fit well under 200 chars.

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

### TTY budget

| | First run | Re-run |
|---|---|---|
| Phase 0 | 0 TTY prompts | 0 |
| Phases 1–5 (key auth) | 1 `ssh-keygen` event (2 passphrase prompts — confirm pattern) + 1 Amarel password + 1 passphrase-to-agent | 0 if Phase 1.0 probe passes; on macOS/Windows the keychain persists across reboot; **on Linux the agent may re-prompt for the passphrase once per login session** unless gnome-keyring/KWallet autostart is configured |
| Phases 6–9 | 0 | 0 |
| Phase 10 | 0 (key auth in VS Code) | 0 |

**Linux keychain note:** The Linux per-session guarantee means zero prompts
within a single login session. A reboot-spanning guarantee requires persistent
keyring autostart that the skill cannot configure — the skill points the user
at their distro docs and continues.

---

## Phase 0 — Preflight

**Goal:** Detect the user's local OS, confirm OpenSSH tools are present, and
confirm Amarel is reachable on the VPN. **Run these yourself via Bash.**

**macOS / Linux — run yourself:**

```bash
case "$(uname -s)" in
  Darwin) echo "✓ OS: macOS" ;;
  Linux)  echo "✓ OS: Linux" ;;
  *)      echo "✗ OS: unsupported ($(uname -s))" ;;
esac
for c in ssh scp ssh-keygen ssh-add ssh-copy-id ssh-keyscan nc; do
  command -v "$c" >/dev/null && echo "✓ $c" || echo "✗ $c MISSING"
done
nc -z -w 5 amarel.rutgers.edu 22 && echo "✓ VPN: Amarel reachable" || echo "✗ VPN: cannot reach amarel.rutgers.edu:22"
```

**Windows PowerShell — run yourself:**

```powershell
if ($IsWindows) { "✓ OS: Windows" } else { "✗ OS: not Windows" }
foreach ($c in 'ssh','scp','ssh-keygen','ssh-add','ssh-keyscan') {
  if (Get-Command $c -ErrorAction SilentlyContinue) { "✓ $c" } else { "✗ $c MISSING" }
}
if (Test-NetConnection amarel.rutgers.edu -Port 22 -InformationLevel Quiet) { "✓ VPN: Amarel reachable" } else { "✗ VPN: cannot reach amarel.rutgers.edu:22" }
```

**Success:** the OS line is `✓ OS: macOS`, `✓ OS: Linux`, or `✓ OS: Windows`,
and every other line begins with `✓`.

**If you see** `✗ ... MISSING`: on macOS/Linux install `openssh-client`; on
Windows install OpenSSH client via *Settings → Apps → Optional features*.
Windows lacks `ssh-copy-id` by default — Phase 3 has a proven workaround.

**If you see** `✗ VPN`: tell the user to connect to Rutgers VPN and stop —
nothing below will work without it.

**Record `LOCAL_OS` from the OS line, then ask the user for their NetID and advance.**

---

## Phase 1 — Generate the Amarel SSH key (idempotent)

**Goal:** Create `~/.ssh/id_ed25519_amarel` (dedicated key for Amarel only —
keeps it separate from any GitHub key).

### 1.0 — Full skip probe (run yourself)

Before anything, probe whether key auth already works **and** the `ssh_config`
block is fully correct. This uses `-i` explicitly so success via an unrelated
loaded key does not falsely satisfy the gate.

**macOS/Linux — run yourself:**

```bash
# Gate 1: key auth
ssh -o BatchMode=yes -o ConnectTimeout=5 \
    -i ~/.ssh/id_ed25519_amarel \
    <NetID>@amarel.rutgers.edu true 2>&1
KEY_OK=$?

# Gate 2: ssh_config block has all required keys
CFG=$(ssh -G amarel.rutgers.edu 2>/dev/null)
echo "$CFG" | grep -qE '^identityfile.*id_ed25519_amarel' && \
echo "$CFG" | grep -qE '^identitiesonly yes' && \
echo "$CFG" | grep -qE '^addkeystoagent yes' && \
echo "$CFG" | grep -qE '^user <NetID>$' && CONFIG_OK=0 || CONFIG_OK=1

if [ "$KEY_OK" -eq 0 ] && [ "$CONFIG_OK" -eq 0 ]; then
  echo "SKIP: key auth + ssh_config already correct — skipping Phases 1–5"
else
  echo "PROCEED: running key auth setup"
fi
```

**Windows PowerShell — run yourself:**

```powershell
& ssh -o BatchMode=yes -o ConnectTimeout=5 `
    -i "$HOME\.ssh\id_ed25519_amarel" `
    "<NetID>@amarel.rutgers.edu" true 2>&1 | Out-Null
$keyOk = ($LASTEXITCODE -eq 0)
$cfg = & ssh -G amarel.rutgers.edu 2>$null
$configOk = ($cfg -match 'identityfile.*id_ed25519_amarel') -and
            ($cfg -match 'identitiesonly yes') -and
            ($cfg -match 'addkeystoagent yes') -and
            ($cfg -match '^user <NetID>$')
if ($keyOk -and $configOk) { "SKIP: key auth + ssh_config already correct — skipping Phases 1–5" }
else { "PROCEED: running key auth setup" }
```

If output is `SKIP`, jump to **Phase 6**. Otherwise continue.

### 1.1 — Check if key exists (run yourself)

**macOS/Linux:**
```bash
test -f ~/.ssh/id_ed25519_amarel && echo "EXISTS — skip 1.2" || echo "MISSING — run keygen"
```

**Windows PowerShell:**
```powershell
if (Test-Path "$HOME\.ssh\id_ed25519_amarel") { "EXISTS — skip 1.2" } else { "MISSING — run keygen" }
```

If `EXISTS`, skip to Phase 2.

### 1.2 — Generate key (user TTY step)

> **🔒 YOUR TURN:** `ssh-keygen` will prompt twice for a passphrase. Pick a
> strong one — you'll type it exactly once more (Phase 4.1), then the OS
> keychain stores it forever. **I cannot see what you type.**

**macOS/Linux:**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_amarel -C "amarel-vscode-$(whoami)@$(hostname)"
```

**Windows PowerShell:**

```powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\id_ed25519_amarel" -C "amarel-vscode-$env:USERNAME@$env:COMPUTERNAME"
```

**Wait for user "done", then verify the pub key exists yourself:**

```bash
ls -l ~/.ssh/id_ed25519_amarel.pub
```

Then advance to Phase 2.

---

## Phase 2 — Verify Amarel's host fingerprint

**Goal:** Pin Amarel's SSH host key in `~/.ssh/known_hosts` after the user
verifies the fingerprint out-of-band. This is the only protection against
MITM on first connection.

### 2.0 — Check known_hosts (run yourself)

```bash
grep -qE "^amarel\.rutgers\.edu " ~/.ssh/known_hosts 2>/dev/null && echo "ALREADY TRUSTED — skip Phase 2" || echo "NEEDS VERIFICATION"
```

If `ALREADY TRUSTED`, skip to Phase 3.

### 2.1 — Scan and fingerprint (run yourself)

Scan to a fixed path under `~/.ssh/`, fingerprint that exact file, then append
only what was fingerprinted. A shell variable from `mktemp` will not survive
across separate ssh invocations — use a fixed path so steps 2.1 and 2.3 see
the same file.

**macOS/Linux:**

```bash
ssh-keyscan -t ed25519 amarel.rutgers.edu 2>/dev/null > ~/.ssh/amarel_hostkey.pending
ssh-keygen -lf ~/.ssh/amarel_hostkey.pending
```

**Windows PowerShell:**

```powershell
ssh-keyscan -t ed25519 amarel.rutgers.edu 2>$null | Set-Content "$HOME\.ssh\amarel_hostkey.pending"
ssh-keygen -lf "$HOME\.ssh\amarel_hostkey.pending"
```

**Show the fingerprint output to the user.**

### 2.2 — User fingerprint verification

> **🔒 YOUR TURN:** Compare the `SHA256:…` value above against Rutgers OARC's
> published fingerprint. The reference fingerprint recorded on 2026-05-26 is:
>
> ```
> SHA256:cN6l3kR3jbdOv6Ofz1b+KNCt3LaOCj9bq6yeHoR3eLs
> ```
>
> **Only continue if your output matches. A mismatch means a possible
> man-in-the-middle attack — STOP and contact OARC.**
>
> If OARC confirms the host key was legitimately rotated and gives you the new
> fingerprint out-of-band, replace the reference value above with the confirmed
> one and re-run Phase 2. Never update the pin just because it stopped matching.

### 2.3 — Append exact temp file on user "yes" (run yourself)

**macOS/Linux:**

```bash
cat ~/.ssh/amarel_hostkey.pending >> ~/.ssh/known_hosts && rm -f ~/.ssh/amarel_hostkey.pending && echo "✓ host key trusted"
```

**Windows PowerShell:**

```powershell
Add-Content -Path "$HOME\.ssh\known_hosts" -Value (Get-Content "$HOME\.ssh\amarel_hostkey.pending")
Remove-Item "$HOME\.ssh\amarel_hostkey.pending"
"✓ host key trusted"
```

**Wait for confirmation, then advance.**

---

## Phase 3 — Install your public key on Amarel

**Goal:** Copy `id_ed25519_amarel.pub` into Amarel's `~/.ssh/authorized_keys`
so future logins use the key instead of a password.

### 3.0 — Re-probe key auth (run yourself)

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_amarel <NetID>@amarel.rutgers.edu true 2>/dev/null && echo "ALREADY WORKS — skip Phase 3" || echo "NEEDS key install"
```

If `ALREADY WORKS`, skip to Phase 4.

### 3.1 — Install public key (user TTY step — LAST password entry ever)

**macOS / Linux:**

```bash
ssh-copy-id -i ~/.ssh/id_ed25519_amarel.pub -o PreferredAuthentications=password -o PubkeyAuthentication=no <NetID>@amarel.rutgers.edu
```

> **🔒 YOUR TURN:** `ssh-copy-id` will prompt for your **Amarel password**.
> Type it once. This is the only time you will ever need it for VS Code.
> **I cannot see what you type.**

**Windows (no `ssh-copy-id`) — proven stdin-pipe pattern from `scripts/setup.ps1:213-220`:**

The `-tt` flag forces a TTY so Amarel's password prompt is visible. The pub
key is piped via stdin and read into a remote-side variable `KEY` with
`KEY="$(cat)"` so the key contents never have to be escaped into a
shell-quoted string. The `grep -qxF` guard prevents duplicate
authorized_keys entries. (Do **not** use `grep -qxF "$(cat)"` inline — that
would consume stdin into grep's argument and leave the append-cat empty.)

```powershell
$remoteCmd = @'
KEY="$(cat)"
umask 077
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
grep -qxF "$KEY" ~/.ssh/authorized_keys || printf '%s\n' "$KEY" >> ~/.ssh/authorized_keys
'@
Get-Content -Raw "$HOME\.ssh\id_ed25519_amarel.pub" | & ssh -tt `
    -o PreferredAuthentications=password -o PubkeyAuthentication=no `
    "<NetID>@amarel.rutgers.edu" $remoteCmd
```

> **🔒 YOUR TURN:** Amarel's password prompt will appear in the terminal.
> Type your password. **I cannot see what you type.**

### 3.1.1 — Verify login (user step)

`ssh-copy-id` itself recommends this: try logging in right now to confirm the key was accepted.

> **🔒 YOUR TURN:** Run the login command and check that you get an Amarel shell prompt:
>
> **macOS/Linux:**
> ```bash
> ssh -i ~/.ssh/id_ed25519_amarel <NetID>@amarel.rutgers.edu
> ```
> **Windows PowerShell:**
> ```powershell
> ssh -i "$HOME\.ssh\id_ed25519_amarel" "<NetID>@amarel.rutgers.edu"
> ```
>
> SSH will prompt for your **key passphrase** (the one you set in Phase 1.2 — not your Amarel password). Enter it and check the result:
>
> - **Success:** you see an Amarel shell prompt like `[<NetID>@amarel1 ~]$`. Type `exit` and let me know.
> - **Failure:** `Permission denied (publickey,…)` — the key copy didn't take. Let me know and I'll diagnose.

**Wait for user confirmation before advancing.**

### 3.1.5 — Dedupe `authorized_keys` (run yourself)

`ssh-copy-id` matches by full line, so a re-run with any whitespace or comment
drift can append a duplicate key — the live-run cleanup found three identical
copies accumulated across sessions. After 3.1, collapse duplicates idempotently:

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Best-effort only: on a first run with a passphrase-protected key this `BatchMode`
ssh can't authenticate yet (the agent isn't loaded until Phase 4.1), so it may
print `Permission denied (publickey,…)`. That's harmless here — it re-runs and
cleans up duplicates after Phase 4 (same interaction the 3.2 note explains).
Don't treat it as a failure.

### 3.2 — Verify key auth (run yourself)

```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_amarel <NetID>@amarel.rutgers.edu 'echo ok' && echo "✓ key auth works"
```

**Expected-failure note (passphrase keys):** under `-o BatchMode=yes` this probe
**cannot unlock a passphrase-encrypted key** until the agent is loaded in Phase
4.1, so on a first run it returns `Permission denied (publickey,…)`. That is
**expected** — do not treat it as a key-install failure. Proceed to Phase 4; the
canonical end-to-end verification is **Phase 5** (after the agent holds the key).

**Only treat this as a real problem** if `Permission denied` persists **after**
Phase 4.2 shows the key loaded in the agent. In that case the key install didn't
take: log in interactively (`ssh <NetID>@amarel.rutgers.edu`) and check that
`~/.ssh/authorized_keys` on Amarel has a line ending in `amarel-vscode-…`, with
permissions `600 ~/.ssh/authorized_keys` and `700 ~/.ssh`.

**Wait for confirmation, then advance.**

---

## Phase 4 — Save passphrase to OS keychain + write strict ssh_config

**Goal:** Add the key to `ssh-agent` so future SSH calls don't prompt for the
passphrase, and write a strict `ssh_config` block that VS Code will use.

### 4.0 — Check if key is already loaded (run yourself)

**macOS/Linux:**

```bash
ssh-add -l 2>/dev/null | grep -q amarel-vscode && echo "LOADED — skip 4.1" || echo "NOT LOADED — run ssh-add"
```

**Windows PowerShell** (the `ssh-agent` service must be running — if `ssh-add -l` errors with "Could not open a connection", start it first via `Start-Service ssh-agent`):

```powershell
$keyLoaded = (ssh-add -l 2>$null | Select-String -Quiet 'amarel-vscode')
if ($keyLoaded) { "LOADED — skip 4.1" } else { "NOT LOADED — run ssh-add" }
```

If `LOADED`, skip to 4.2.

### 4.1 — Add key to agent (user TTY step — passphrase saved to keychain)

**macOS:**

```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_amarel
```

**macOS keychain-label note (for a clean future reverse-out):** `ssh-add` prints
a line like `Identity added: …/id_ed25519_amarel (amarel-vscode-…)`. You may
record that label from the visible stdout the user pastes back. **Do NOT** run
`security find-generic-password` or `security dump-keychain` to discover it —
those are on the security deny-list. The label is already in plain `ssh-add`
output; use that, never a keychain query.

**Linux:**

```bash
ssh-add ~/.ssh/id_ed25519_amarel
```

**Linux keychain note:** `ssh-add` saves the passphrase for this login session.
On reboot, you may need to re-enter once unless you configure gnome-keyring or
KWallet for persistent autostart. See your distro's documentation for that
one-time configuration. The skill sets up everything else automatically.

**Windows PowerShell — start agent service, then add key:**

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent; ssh-add "$HOME\.ssh\id_ed25519_amarel"
```

> **🔒 YOUR TURN:** `ssh-add` will prompt for your key passphrase (the one
> from Phase 1.2). After this, the OS keychain stores it permanently (macOS /
> Windows) or for this session (Linux). **I cannot see what you type.**

**Wait for user "done".**

### 4.2 — Verify key loaded (run yourself)

**macOS/Linux:**

```bash
ssh-add -l | grep amarel-vscode && echo "✓ key in agent"
```

**Windows PowerShell:**

```powershell
ssh-add -l 2>$null | Select-String 'amarel-vscode'
```

### 4.3 — Write strict ssh_config (run yourself)

**Config file path:**
- macOS/Linux: `~/.ssh/config`
- Windows: `$HOME\.ssh\config`

**Parse any existing `Host amarel.rutgers.edu` block first:**

**macOS/Linux:**

```bash
awk '/^Host amarel\.rutgers\.edu/{f=1;print;next} /^Host /{f=0} f' ~/.ssh/config 2>/dev/null || true
```

(Do **not** use an awk range like `/^Host amarel…/,/^Host [^ ]/` — the start line
also matches the end pattern, so on BSD awk the range collapses to just the header
line and you never see the block body.)

**Windows PowerShell:**

```powershell
$lines = Get-Content "$HOME\.ssh\config" -ErrorAction SilentlyContinue
$inBlock = $false
foreach ($l in $lines) {
  if ($l -match '^Host amarel\.rutgers\.edu') { $inBlock = $true }
  elseif ($l -match '^Host ' -and $inBlock) { $inBlock = $false }
  if ($inBlock) { $l }
}
```

**Decision logic:**

- **If no `Host amarel.rutgers.edu` block exists** → append the canonical block below.
- **If a block exists but is missing or has wrong values for `User`, `IdentityFile`, `IdentitiesOnly`, `AddKeysToAgent`, or (macOS only) `UseKeychain`** → surface the diff to the user and ask them to edit the file manually (do not blindly overwrite — they may have custom `ProxyCommand`, `LocalForward`, etc.). Re-verify after user "done".

**Canonical block to append if absent:**

```
Host amarel.rutgers.edu
    User <NetID>
    IdentityFile ~/.ssh/id_ed25519_amarel
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes
```

*macOS only:* include `UseKeychain yes`. Linux and Windows: omit it.

**Append command (macOS/Linux):**

```bash
cat >> ~/.ssh/config <<'EOF'

Host amarel.rutgers.edu
    User <NetID>
    IdentityFile ~/.ssh/id_ed25519_amarel
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes
EOF
chmod 600 ~/.ssh/config
```

*(Linux: omit the `UseKeychain yes` line.)*

**Append command (Windows PowerShell):**

Follows the same parse → diff → ask logic as macOS/Linux above. If the
`Host amarel.rutgers.edu` block is absent, append; if it is present with
mismatching values, surface the diff and ask the user to edit manually.
Note: `UseKeychain yes` is **macOS-only** and is OMITTED on Windows.

```powershell
$cfg = @"

Host amarel.rutgers.edu
    User <NetID>
    IdentityFile ~/.ssh/id_ed25519_amarel
    IdentitiesOnly yes
    AddKeysToAgent yes
"@
Add-Content -Path "$HOME\.ssh\config" -Value $cfg
```

**Windows note:** Windows OpenSSH enforces its own per-file ACL check — do NOT
run `chmod` or `icacls` on this file. If Windows OpenSSH rejects the config,
surface the error and ask the user to fix ACLs via Properties → Security
manually, or run `Repair-AuthorizedKeyPermission`.

**Verify resolved config on all OSes (run yourself):**

```bash
ssh -G amarel.rutgers.edu | grep -E '^(user|identityfile|identitiesonly|addkeystoagent) '
```

Must show `user <NetID>`, `identityfile ~/.ssh/id_ed25519_amarel`,
`identitiesonly yes`, `addkeystoagent yes`.

**Wait for verification to pass, then advance.**

---

## Phase 5 — Verify passwordless SSH end-to-end

**Goal:** Prove that a non-interactive `ssh` succeeds with no prompts.
This is what VS Code's Remote-SSH will use. **Run yourself.**

```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 amarel.rutgers.edu 'echo ok; hostname; whoami'
```

**Success:** three lines — `ok`, an Amarel login-node hostname (e.g.
`amarel1.amarel.rutgers.edu`), and the NetID.

**If it hangs or errors:** key auth is not fully working. Re-run Phase 4.2
verify and Phase 4.3 ssh_config validation. For a deeper diagnostic, **hand
the user** this command — it is interactive (no `BatchMode`), so they (not
the agent) run it to surface a real password prompt or full handshake trace:

> **🔒 YOUR TURN — diagnostic only:** `ssh -v amarel.rutgers.edu` (interactive; shows the full SSH handshake)

If their output shows `Authentications that can continue: publickey,…` and
then fails, the `authorized_keys` permissions on Amarel are wrong — the
agent can fix that autonomously:

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'chmod 600 ~/.ssh/authorized_keys; chmod 700 ~/.ssh'
```

**Wait for the three success lines, then advance.**

---

## Phase 6 — Locate the sysroot tarball

**Goal:** Find a valid sysroot tarball locally before downloading. **Run
all probes yourself.**

**Establish `REPO_ROOT` once (run yourself before any 6.x step).** The skill
is always cloned as a git repo, so resolve the repo root from `git` rather
than assuming the LLM's cwd:

**macOS/Linux:**

```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  echo "ABORT: this skill must be invoked from inside the amarel-vscode git checkout" >&2
  exit 1
fi
```

**Windows PowerShell:**

```powershell
$REPO_ROOT = git rev-parse --show-toplevel 2>$null
if (-not $REPO_ROOT) {
  Write-Error "ABORT: this skill must be invoked from inside the amarel-vscode git checkout"
  exit 1
}
```

Every `assets/checksums.txt`, `assets/sysroot.sh`, and `build/…` path below
is resolved relative to `REPO_ROOT` so the agent's cwd does not matter.

### 6.0 — Check repo `build/` directory (run yourself)

**macOS/Linux:**

```bash
TARBALL="$REPO_ROOT/build/vscode-sysroot-x86_64-linux-gnu.tgz"
if [ -f "$TARBALL" ] && tar tzf "$TARBALL" >/dev/null 2>&1; then
  echo "FOUND: $TARBALL"; USE_TARBALL="$TARBALL"
else
  echo "NOT FOUND in build/"
fi
```

**Windows PowerShell:**

```powershell
$tarball = "$REPO_ROOT\build\vscode-sysroot-x86_64-linux-gnu.tgz"
if ((Test-Path $tarball) -and (tar tzf $tarball > $null 2>&1; $LASTEXITCODE -eq 0)) {
  "FOUND: $tarball"; $USE_TARBALL = $tarball
} else { "NOT FOUND in build/" }
```

If found and valid, skip to 6.4.

### 6.1 — Local search (run yourself)

Search wide **before** any build fallback — the live run jumped to the Docker
build too fast. Run these cheapest-first; stop at the first that finds a match.

**macOS** (Spotlight index is fastest; `mdfind` is macOS-only):

```bash
mdfind -name 'vscode-sysroot-x86_64-linux-gnu.tgz' 2>/dev/null
```

**macOS/Linux** (home sweep, then a bounded full sweep only if home misses):

```bash
find ~ -name 'vscode-sysroot-x86_64-linux-gnu.tgz' 2>/dev/null
find / -name 'vscode-sysroot-x86_64-linux-gnu.tgz' -not -path '*/Library/*' -not -path '/private/var/*' 2>/dev/null
```

**Windows PowerShell:**

```powershell
Get-ChildItem -Path $HOME -Recurse -Filter vscode-sysroot-x86_64-linux-gnu.tgz -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
```

- **1 match** → validate with `tar tzf <path> >/dev/null` then use it.
- **2+ matches** → surface the list to the user and ask which to use.
- **0 matches after all of the above** → **ask the user** "Do you have a
  `vscode-sysroot` clone or tarball anywhere I haven't looked (external drive,
  iCloud Drive, another machine)?" **before** advancing to 6.2/6.3. Do not
  silently fall through to a 30–60 min build.

### 6.2 — Download from GitHub Release (run yourself if still missing)

**macOS/Linux:**

```bash
mkdir -p "$REPO_ROOT/build"
curl -fL https://github.com/solomonsjoseph/amarel-vscode/releases/latest/download/vscode-sysroot-x86_64-linux-gnu.tgz \
  -o "$REPO_ROOT/build/vscode-sysroot-x86_64-linux-gnu.tgz"
```

**Windows PowerShell:**

```powershell
New-Item -ItemType Directory -Force -Path "$REPO_ROOT\build" | Out-Null
Invoke-WebRequest -Uri https://github.com/solomonsjoseph/amarel-vscode/releases/latest/download/vscode-sysroot-x86_64-linux-gnu.tgz `
  -OutFile "$REPO_ROOT\build\vscode-sysroot-x86_64-linux-gnu.tgz" -UseBasicParsing
```

**Verify SHA-256 against `assets/checksums.txt`:**

```bash
_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}
EXPECTED=$(awk '$2=="vscode-sysroot-x86_64-linux-gnu.tgz" {print $1}' "$REPO_ROOT/assets/checksums.txt")
ACTUAL=$(_sha256 "$REPO_ROOT/build/vscode-sysroot-x86_64-linux-gnu.tgz")
if echo "$EXPECTED" | grep -qE '^0+$'; then
  echo "WARN: checksum not recorded in assets/checksums.txt — proceeding"
elif [ "$EXPECTED" = "$ACTUAL" ]; then
  echo "✓ SHA-256 matches"
else
  echo "ABORT: SHA-256 MISMATCH — possible download corruption or MITM"
  echo "  expected: $EXPECTED"; echo "  actual:   $ACTUAL"
  exit 1
fi
```

**Windows PowerShell checksum verify:**

```powershell
$expected = (Select-String -Path "$REPO_ROOT\assets\checksums.txt" -Pattern 'vscode-sysroot-x86_64-linux-gnu\.tgz').Line.Split()[0]
$actual   = (Get-FileHash -Algorithm SHA256 "$REPO_ROOT\build\vscode-sysroot-x86_64-linux-gnu.tgz").Hash.ToLower()
if ($expected -match '^0+$') { "WARN: checksum not recorded — proceeding" }
elseif ($expected -eq $actual) { "✓ SHA-256 matches" }
else { "ABORT: SHA-256 MISMATCH"; exit 1 }
```

**If ABORT:** do not extract. Tell the user to file an issue against the repo.

### 6.3 — Rare fallback: build locally (inform user only)

Reached only if 6.2 can't download a Release. **First detect the local CPU
architecture** — the build path differs sharply by arch:

**macOS/Linux:**

```bash
uname -m
```

**Windows PowerShell:**

```powershell
$env:PROCESSOR_ARCHITECTURE
```

**If `arm64` / `aarch64` (e.g. Apple Silicon):** do **NOT** offer the local
Docker build. The live run proved it fails — the ursetto Dockerfile builds
crosstool-NG/GMP from source under QEMU-emulated `linux/amd64`, and GMP's
`./configure` can't run its compiler feature-tests under qemu-user (dies after
~7 min with `could not find a working compiler`). Escalate instead, in order of
effort:
> 1. **Publish a Release (recommended, durable fix):** the maintainer runs the
>    planned `.github/workflows/build-and-release.yml` workflow (to be added) on a
>    native `ubuntu-latest` (x86_64) runner — it builds and uploads the tarball +
>    SHA-256s. Then 6.2 downloads it.
> 2. Build on a **native x86_64 Linux host** (cloud VM / Intel Mac) and copy the
>    tarball back into `<repo>/build/`.
> 3. (Discouraged) attempt the QEMU build anyway, knowing it typically dies in
>    the GMP stage.

**If `x86_64` (Intel Mac / Linux):** the local Docker build is viable — offer
`./scripts/build-sysroot.sh` (requires Docker Desktop; 10–20 min). Still requires
explicit user opt-in; **never auto-run it.**

### 6.4 — Final validation before Phase 7 (run yourself)

**macOS/Linux:**

```bash
tar tzf "$REPO_ROOT/build/vscode-sysroot-x86_64-linux-gnu.tgz" >/dev/null && echo "✓ tarball is well-formed" || echo "✗ tarball is corrupt — delete and re-download"
```

**Windows PowerShell:**

```powershell
tar tzf "$REPO_ROOT\build\vscode-sysroot-x86_64-linux-gnu.tgz" > $null 2>&1
if ($LASTEXITCODE -eq 0) { "✓ tarball is well-formed" } else { "✗ tarball is corrupt — delete and re-download" }
```

**Wait for `✓ tarball is well-formed`, then advance.**

---

## Phase 7 — Deploy the sysroot on Amarel

**Goal:** Upload the tarball and `assets/sysroot.sh`, extract into
`~/.vscode-server/sysroot/`, run hard verification gates, and auto-remediate
any failures. **All autonomous `ssh`/`scp` from here use `-o BatchMode=yes`.**

> **Local vs remote command note:** `scp`/`ssh` invocation lines below differ
> per OS (Windows uses backslash paths; `~` doesn't expand at the call site —
> use `$HOME` or `$env:USERPROFILE`). The remote commands inside heredocs
> execute on Amarel and are identical across all local OSes.

### 7.1 — Upload tarball (run yourself)

**macOS/Linux:**

```bash
scp -o BatchMode=yes "$REPO_ROOT/build/vscode-sysroot-x86_64-linux-gnu.tgz" <NetID>@amarel.rutgers.edu:~/
```

**Windows PowerShell:**

```powershell
scp -o BatchMode=yes "$REPO_ROOT\build\vscode-sysroot-x86_64-linux-gnu.tgz" "<NetID>@amarel.rutgers.edu:~/"
```

### 7.2 — Upload sysroot.sh (run yourself)

**macOS/Linux:**

```bash
scp -o BatchMode=yes "$REPO_ROOT/assets/sysroot.sh" <NetID>@amarel.rutgers.edu:~/
```

**Windows PowerShell:**

```powershell
scp -o BatchMode=yes "$REPO_ROOT\assets\sysroot.sh" "<NetID>@amarel.rutgers.edu:~/"
```

### 7.3 — Fallback: fetch sysroot.sh via curl if 7.2 fails (run yourself)

If the `scp` of `sysroot.sh` fails (as happened in the canonical manual run),
fetch it directly on Amarel and verify its content before installing:

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail
curl -fsSL https://raw.githubusercontent.com/ursetto/vscode-sysroot/main/sysroot.sh -o ~/sysroot.sh
# Reject anything missing the expected 3-export shape (defense vs upstream compromise)
EXPECTED='^export VSCODE_SERVER_(CUSTOM_GLIBC_LINKER|CUSTOM_GLIBC_PATH|PATCHELF_PATH)='
count=$(grep -cE "$EXPECTED" ~/sysroot.sh || true)
if [ "$count" -ne 3 ]; then
  echo "ERROR: fetched sysroot.sh missing one of the 3 required exports (got $count)" >&2
  rm -f ~/sysroot.sh
  exit 1
fi
echo "✓ sysroot.sh content verified ($count exports)"
REMOTE
```

If this also fails, escalate to the user. Do NOT proceed to 7.4 with an
unverified file.

### 7.4 — Probe existing-and-healthy sysroot (run yourself)

Mechanical health probe: checks the two anchor files exist and patchelf is
≥ 0.18. Emits exactly one token (`OK_HEALTHY` or `NEEDS_INSTALL`) so the
agent can route without parsing version strings:

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -uo pipefail
test -f ~/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2 || { echo NEEDS_INSTALL; exit 0; }
test -f ~/.vscode-server/sysroot.sh                       || { echo NEEDS_INSTALL; exit 0; }
PE=$(~/.vscode-server/sysroot/usr/bin/patchelf --version 2>/dev/null | awk '{print $NF}')
[ -z "$PE" ] && { echo NEEDS_INSTALL; exit 0; }
awk -v v="$PE" 'BEGIN{split(v,a,"."); exit !((a[1]>0)||(a[1]==0&&a[2]>=18))}' \
  && echo OK_HEALTHY || echo NEEDS_INSTALL
REMOTE
```

Routing:

- `OK_HEALTHY` → skip 7.5 and 7.6 (sysroot already deployed and patchelf is current). Advance to **7.7** for verification, then Phase 8.
- `NEEDS_INSTALL` → continue with 7.5 (only on user opt-in) / 7.6 (extract).

### 7.5 — Recovery branch: wipe (USER opt-in only — NOT default critical path)

Reach this ONLY when 7.4 shows broken/partial state. Ask the user before wiping:

> "The existing `~/.vscode-server` appears partially installed. Should I wipe it and start fresh? Reply yes to confirm."

On explicit user "yes":

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail
[ -d "$HOME/.vscode-server" ] && chmod -R u+w "$HOME/.vscode-server" 2>/dev/null || true
rm -rf "$HOME/.vscode-server" "$HOME/.vscode-server-insiders" "$HOME/.vscode-cli"
REMOTE
```

### 7.6 — Extract sysroot (run yourself)

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail
mkdir -p "$HOME/.vscode-server"
tar zxf "$HOME/vscode-sysroot-x86_64-linux-gnu.tgz" -C "$HOME/.vscode-server"
if [ -f "$HOME/sysroot.sh" ]; then
  mv -f "$HOME/sysroot.sh" "$HOME/.vscode-server/sysroot.sh"
fi
# Hard sanity gates — fail here, not after rm
test -f "$HOME/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2"
test -x "$HOME/.vscode-server/sysroot/usr/bin/patchelf"
test -f "$HOME/.vscode-server/sysroot.sh"
rm -f "$HOME/vscode-sysroot-x86_64-linux-gnu.tgz"
echo "✓ sysroot extracted"
REMOTE
```

### 7.7 — Hard verify: three independent gates (run yourself)

Collect all failures before deciding on a remedy. Uses `-uo pipefail` (NOT
`-euo`) so all three gates run even if one fails:

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -uo pipefail
FAILS=""

# (a) Three files present and non-zero
if ! ls -l ~/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2 \
            ~/.vscode-server/sysroot/usr/bin/patchelf \
            ~/.vscode-server/sysroot.sh >/dev/null 2>&1; then
  FAILS="${FAILS}files "
fi

# (b) Three expected exports present in sysroot.sh
if [ -f ~/.vscode-server/sysroot.sh ]; then
  EXPECTED='^export VSCODE_SERVER_(CUSTOM_GLIBC_LINKER|CUSTOM_GLIBC_PATH|PATCHELF_PATH)='
  count=$(grep -cE "$EXPECTED" ~/.vscode-server/sysroot.sh 2>/dev/null); count=${count:-0}
  [ "$count" -eq 3 ] || FAILS="${FAILS}exports "
else
  FAILS="${FAILS}exports "
fi

# (c) patchelf >= 0.18 (per assets/sysroot.sh:11-12 + Microsoft FAQ)
if [ -x ~/.vscode-server/sysroot/usr/bin/patchelf ]; then
  PE_VER=$(~/.vscode-server/sysroot/usr/bin/patchelf --version 2>/dev/null | awk '{print $NF}')
  if ! awk -v v="$PE_VER" 'BEGIN { split(v, a, "."); exit !((a[1]>0) || (a[1]==0 && a[2]>=18)) }'; then
    FAILS="${FAILS}patchelf "
  fi
else
  FAILS="${FAILS}patchelf "
fi

if [ -n "$FAILS" ]; then
  echo "FAIL: $FAILS" >&2; exit 1
fi
echo "✓ all verification gates passed"
REMOTE
```

Parse the `FAIL:` line and route to the matching 7.8 branch. One or more
gates may fire simultaneously.

### 7.8 — Targeted recovery: branch by failed gate (run yourself)

**`files` failed → re-extract.** Re-run 7.1 (re-upload tarball if missing on
Amarel) and 7.6 (extract). If still failing, escalate to the user.

**`exports` failed → re-deploy sysroot.sh.** First re-run **7.2** (or its
**7.3** curl fallback with the content-verify gate) so a fresh
`~/sysroot.sh` exists on Amarel. Only then run the move below — the `[ -f ]`
guard makes it safe if a partial earlier run already consumed the source
file:

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail
if [ -f "$HOME/sysroot.sh" ]; then
  mv -f "$HOME/sysroot.sh" "$HOME/.vscode-server/sysroot.sh"
else
  echo "ERROR: ~/sysroot.sh not present on Amarel — re-run 7.2 (or 7.3) first" >&2
  exit 1
fi
REMOTE
```

Re-run 7.7.

**`patchelf` failed → in-place upgrade with SHA-256 verify.**

First, read the expected SHA from `assets/checksums.txt` on the local
machine. The unquoted `<<REMOTE` heredoc below expands `${EXPECTED_SHA}`
from the local shell before the script is sent to bash on Amarel, so no
template substitution is needed — just make sure the local assignment
runs immediately before the heredoc:

```bash
EXPECTED_SHA=$(awk '$2=="patchelf-0.18.0-x86_64.tar.gz" {print $1}' "$REPO_ROOT/assets/checksums.txt")
```

Then run the upgrade (note: unquoted `<<REMOTE` so `${EXPECTED_SHA}`
expands locally; `\$` on remote-only vars keeps them deferred to Amarel):

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<REMOTE
set -euo pipefail
cd /tmp
curl -fsSL https://github.com/NixOS/patchelf/releases/download/0.18.0/patchelf-0.18.0-x86_64.tar.gz -o patchelf-0.18.tgz
EXPECTED_SHA="${EXPECTED_SHA}"
if [ "\$EXPECTED_SHA" = "0000000000000000000000000000000000000000000000000000000000000000" ]; then
  echo "WARN: patchelf SHA-256 not recorded in assets/checksums.txt — proceeding unverified" >&2
else
  ACTUAL_SHA=\$(sha256sum patchelf-0.18.tgz | awk '{print \$1}')
  if [ "\$ACTUAL_SHA" != "\$EXPECTED_SHA" ]; then
    echo "ERROR: patchelf SHA-256 mismatch (expected \$EXPECTED_SHA, got \$ACTUAL_SHA)" >&2
    rm -f patchelf-0.18.tgz; exit 1
  fi
fi
mkdir -p patchelf-extract && tar zxf patchelf-0.18.tgz -C patchelf-extract
chmod u+w ~/.vscode-server/sysroot/usr/bin/patchelf
cp patchelf-extract/bin/patchelf ~/.vscode-server/sysroot/usr/bin/patchelf
~/.vscode-server/sysroot/usr/bin/patchelf --version
rm -rf /tmp/patchelf-0.18.tgz /tmp/patchelf-extract
REMOTE
```

After whichever remedy fires, re-run 7.7. If 7.7 still fails after one
remediation pass → escalate to the user (do not loop).

---

## Phase 8 — Wire `~/.bashrc` and verify env var

**Goal:** Append the sysroot loader to `~/.bashrc` on Amarel (idempotent),
then verify the env var survives a non-interactive shell. **All steps run
yourself via `ssh -o BatchMode=yes`.**

> **`.bashrc` vs `.bash_profile`:** VS Code Remote-SSH spawns a non-interactive
> non-login bash shell, which sources `~/.bashrc`, **not** `~/.bash_profile`.
> The skill uses `.bashrc` exclusively.

### 8.1 — Idempotent append (run yourself)

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail
if ! grep -q 'vscode-server/sysroot\.sh' "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<'BRC'

# VS Code Server custom glibc workaround
[ -f "$HOME/.vscode-server/sysroot.sh" ] && source "$HOME/.vscode-server/sysroot.sh"
BRC
fi
REMOTE
```

### 8.2 — Verify env var (run yourself)

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'echo "$VSCODE_SERVER_PATCHELF_PATH"'
```

**Success:** prints `/home/<NetID>/.vscode-server/sysroot/usr/bin/patchelf`.

### 8.3 — Nano fallback (if 8.2 prints empty)

Two causes seen in practice: (a) `~/.bashrc` has an early `return` for
non-interactive shells that runs before the `source` line — move the `source`
block above any such `return`; (b) the manual run's append landed mis-indented
right after an NVM/`PATH` line when typed interactively, so the loader never
ran. The nano fallback below sidesteps both by letting the user place two clean
lines at the end of the file.

Inspect first:

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'head -30 ~/.bashrc'
```

If the heredoc append didn't land cleanly (as happened in the canonical manual
run), give the user this manual fallback:

> **🔒 YOUR TURN:** SSH into Amarel and open `~/.bashrc` in a text editor:
>
> ```bash
> ssh <NetID>@amarel.rutgers.edu
> nano ~/.bashrc
> ```
>
> Scroll to the very end and add these two lines:
>
> ```
> # VS Code Server custom glibc workaround
> [ -f "$HOME/.vscode-server/sysroot.sh" ] && source "$HOME/.vscode-server/sysroot.sh"
> ```
>
> Save and exit: nano → Ctrl+O, Enter, Ctrl+X. Or vim → Esc, `:wq`, Enter.

Then re-run 8.2 to confirm.

**Wait for the correct path, then advance.**

---

## Phase 9 — Disable VS Code extension signature verification on Amarel

**Goal (default-on, probe-to-skip):** VS Code Server's VSIX signature check
crashes on CentOS 7 with the custom glibc node. The fix is to merge
`"extensions.verifySignature": false` into the remote machine settings.
HTTPS to the marketplace still authenticates the download; only the
second-layer VSIX check is skipped. **Run all steps yourself.**

CentOS 7 ships **python2** by default; `python3` typically requires
`module load python` or EPEL. Phase 9 therefore probes for `python3` first
and falls back to `jq`, matching the ladder in `scripts/setup.sh` (~L486-L518).
Each Phase 9 remote shell also makes a best-effort attempt to `module load
python` itself (sourcing the modules init first, since `module` is normally
login-shell-only). If neither `python3` nor `jq` is available even after that
(most fresh HPC accounts have python2 only), the agent will tell you to add
`module load python` to `~/.bashrc` — above any non-interactive `return`, so it
reaches the non-interactive shells the agent and VS Code use — then re-trigger
Phase 9.

### 9.0 — Probe (run yourself)

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -uo pipefail
F="$HOME/.vscode-server/data/Machine/settings.json"

# JSON tool detection (needed for 9.1 atomic merge).
# CentOS 7 ships python2 by default; python3 requires `module load python` or EPEL.
# Best-effort: surface python3 in THIS non-interactive shell. `module` is usually
# only defined for login shells, so source the modules init first, then load.
if ! command -v python3 >/dev/null 2>&1; then
  [ -f /etc/profile.d/modules.sh ] && . /etc/profile.d/modules.sh 2>/dev/null || true
  if command -v module >/dev/null 2>&1; then
    module load python3 2>/dev/null || module load python 2>/dev/null || true
  fi
fi
if command -v python3 >/dev/null 2>&1; then
  TOOL=python3
elif command -v jq >/dev/null 2>&1; then
  TOOL=jq
else
  echo "TOOL=NONE"
  exit 0
fi
echo "TOOL=$TOOL"

# Settings file state.
if [ ! -f "$F" ]; then
  echo "STATE=ABSENT"
  exit 0
fi

case "$TOOL" in
  python3)
    python3 - "$F" <<'PY' 2>/dev/null || echo "STATE=PARSE_ERROR"
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("STATE=PARSE_ERROR"); sys.exit(0)
print("STATE=SET" if d.get("extensions.verifySignature") is False else "STATE=NOT_SET")
PY
    ;;
  jq)
    if   jq -e '."extensions.verifySignature" == false' "$F" >/dev/null 2>&1; then echo "STATE=SET"
    elif jq -e '.' "$F" >/dev/null 2>&1; then echo "STATE=NOT_SET"
    else echo "STATE=PARSE_ERROR"; fi
    ;;
esac
REMOTE
```

Parse the two tokens (`TOOL=…` and `STATE=…`) from the output:

- `TOOL=NONE` → even after the best-effort `module load` above, neither python3
  nor jq is reachable from a non-interactive shell. A one-off `module load python`
  in an *interactive* session will **not** help — the agent's `ssh … 'bash -se'`
  opens a fresh non-interactive shell each time. **Escalate with the durable fix:**
  have the user add `module load python` (or `python3`) to `~/.bashrc` *above* any
  early non-interactive `return` (same spot as the Phase 8 loader), then re-trigger
  Phase 9. Or contact OARC to enable `python3`/`jq`. Do not attempt 9.1.
- `TOOL=python3` or `TOOL=jq`, `STATE=SET` → already configured; **skip 9.1**,
  advance to Phase 10.
- `TOOL=python3` or `TOOL=jq`, `STATE=NOT_SET` or `STATE=ABSENT` → proceed to
  9.1 using the matching tool branch.
- `STATE=PARSE_ERROR` → settings.json is malformed (distinct from missing
  tool); ask user how to proceed — either back up and overwrite, or have them
  fix the JSON manually. **Note:** `python3`/`jq` also report this for a *valid*
  JSON-with-comments (JSONC) file, which VS Code allows — inspect the file
  (`cat`, see 9.2) before assuming real corruption. A clean first install has no
  settings.json yet (`STATE=ABSENT`), so this only arises on re-runs.

### 9.1 — Merge setting (run yourself)

Pick the branch matching the `TOOL=…` token from 9.0. Both branches are
atomic (write to a tempfile on the same filesystem, then rename) and
idempotent.

**TOOL=python3 branch:**

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail
mkdir -p "$HOME/.vscode-server/data/Machine"
if ! command -v python3 >/dev/null 2>&1; then
  [ -f /etc/profile.d/modules.sh ] && . /etc/profile.d/modules.sh 2>/dev/null || true
  if command -v module >/dev/null 2>&1; then
    module load python3 2>/dev/null || module load python 2>/dev/null || true
  fi
fi
python3 - <<'PY'
import json, os, tempfile
p = os.path.expanduser("~/.vscode-server/data/Machine/settings.json")
try:
    d = json.load(open(p))
except Exception:
    d = {}
d["extensions.verifySignature"] = False
with tempfile.NamedTemporaryFile("w", dir=os.path.dirname(p), delete=False) as t:
    json.dump(d, t, indent=4)
    tmp = t.name
os.replace(tmp, p)
PY
REMOTE
```

**TOOL=jq branch:**

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail
DIR="$HOME/.vscode-server/data/Machine"
F="$DIR/settings.json"
mkdir -p "$DIR"
TMP=$(mktemp "$DIR/settings.json.XXXXXX")
trap 'rm -f "$TMP"' EXIT   # don't leave a stray settings.json.XXXXXX if jq fails
if [ -f "$F" ]; then
  jq '. + {"extensions.verifySignature": false}' "$F" > "$TMP"
else
  printf '{"extensions.verifySignature": false}\n' | jq '.' > "$TMP"
fi
mv -f "$TMP" "$F"
REMOTE
```

Note: `mktemp` is invoked **inside** `$DIR` so the subsequent `mv` is
atomic on the same filesystem (rename across filesystems is not atomic).

### 9.2 — Verify (tool-agnostic)

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'bash -se' <<'REMOTE'
set -uo pipefail
F="$HOME/.vscode-server/data/Machine/settings.json"
if ! command -v python3 >/dev/null 2>&1; then
  [ -f /etc/profile.d/modules.sh ] && . /etc/profile.d/modules.sh 2>/dev/null || true
  if command -v module >/dev/null 2>&1; then
    module load python3 2>/dev/null || module load python 2>/dev/null || true
  fi
fi
if command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["extensions.verifySignature"] is False' "$F" \
    && echo VERIFIED || { echo FAIL_VERIFY; exit 1; }
elif command -v jq >/dev/null 2>&1; then
  jq -e '."extensions.verifySignature" == false' "$F" >/dev/null \
    && echo VERIFIED || { echo FAIL_VERIFY; exit 1; }
else
  echo "TOOL_MISSING"; exit 1
fi
REMOTE
```

**Success:** `VERIFIED` (any pre-existing keys preserved).

**If you see `STATE=PARSE_ERROR` from 9.0, or `FAIL_VERIFY` here**: the
user's existing `settings.json` is malformed. Inspect it (benign read-only,
agent-autonomous):

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'cat ~/.vscode-server/data/Machine/settings.json'
```

Show the user the contents, have them fix the JSON syntax in a text editor,
then re-run 9.1.

**Tell the user to reload the VS Code window** if a Remote-SSH window is
already open (otherwise no action needed).

**Advance to Phase 10.**

---

## Phase 10 — Connect from VS Code

**Goal:** The user finishes the setup inside the VS Code GUI.

**Print these steps to the user verbatim:**

> 1. Open VS Code.
> 2. `Cmd+Shift+P` (Mac) / `Ctrl+Shift+P` (Win/Linux).
> 3. Type and run: **Remote-SSH: Connect to Host**.
> 4. Pick `<NetID>@amarel.rutgers.edu` (or type it).
> 5. First time only: click **Allow** on the "OS unsupported" warning.
> 6. Open View → Output, dropdown → Remote-SSH. Watch for `Server started`.
> 7. Bottom-left status bar shows **SSH: amarel.rutgers.edu** (green).

**Common failures (linked recovery branches; none run on a clean first install):**

- `expected GLIBC >= v2.28.0` → Phase 8 didn't take. Re-run 8.2; fix `~/.bashrc` if env var empty (8.3).
- `signature verification failed with UnknownError` on "Install in SSH" → run **Phase 9**. If Phase 9 reports `TOOL=NONE`, have the user add `module load python` to `~/.bashrc` (above any non-interactive `return`) so python3 reaches non-interactive shells, then re-trigger Phase 9.
- `Could not find pty 4 on pty host` → harmless cosmetic noise (seen in canonical manual run). Ignore.
- VS Code prompts for password → SSH key auth not fully working. Re-run Phase 4.2 verify and Phase 4.3 ssh_config validation.
- VS Code server segfaults / patching fails after Allow → likely patchelf issue; **Phase 7.7 should have caught this**, but re-run 7.7 → 7.8 if needed.
- Repeated install failures even after the above → recovery branch **Phase 7.5** (wipe). Opt-in only.

**This is the end of the runbook.** If the status bar turns green, ask the
user to confirm and you're done.

---

## Security constraints — non-negotiable

**You MUST NOT execute** `ssh-keygen` (Phase 1.2), `ssh-copy-id` (Phase 3.1),
`ssh-add` (Phase 4.1), **or any command that prompts for a password or
passphrase on a TTY**. These accept the secret on a TTY you cannot see — you
must hand them to the user. **You MUST add `-o BatchMode=yes`** to every
`ssh` / `scp` you (the agent) issue from Phase 5 onward, so a broken keychain
or wrong config fails loudly instead of hanging at a prompt. Every other phase
you may run via Bash directly.

You **MUST NOT**:

- Read or `cat` any file under `~/.ssh/id_*` (private key material).
- Invoke `security find-generic-password`, `Get-StoredCredential`, or any
  other tool that queries the OS keychain.
- Invoke `sshpass`, `expect`, or any helper that feeds a password to ssh via
  stdin pipe. Never suggest these to the user either.
- Add `-o PasswordAuthentication=yes` to any autonomous `ssh`/`scp` invocation.
- Write any string the user typed during a password/passphrase prompt to a
  file, to memory, or back into the conversation transcript.

If the user reports their password was leaked or something looks suspicious,
stop and tell them to rotate their Amarel password via Rutgers OARC.

---

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

## References

- Repo + issues: <https://github.com/solomonsjoseph/amarel-vscode>
- Microsoft FAQ (the supported workaround pattern): <https://code.visualstudio.com/docs/remote/faq#_can-i-run-vs-code-server-on-older-linux-distributions>
- ursetto/vscode-sysroot (upstream of the sysroot tarball): <https://github.com/ursetto/vscode-sysroot>
