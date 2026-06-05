# AGENTS.md — canonical instructions for any LLM coding agent

This file is read automatically by:

- **OpenAI Codex CLI** (`codex`, project-level instructions)
- **Cursor** (newer versions, alongside `.cursor/rules/`)
- **Cline** (VS Code extension, alongside `.clinerules`)
- Most agent frameworks following the [AGENTS.md convention](https://agents.md)

For framework-specific entrypoints that ultimately defer to this file, see:

- `skills/amarel-vscode-setup/SKILL.md` — Claude Code (with YAML frontmatter for slash-command discovery)
- `GEMINI.md` — Google Gemini CLI / Gemini Code Assist

> **Claude Code users can also install this as a plugin** (Claude-Code-only):
> `/plugin marketplace add solomonsjoseph/amarel-vscode` then
> `/plugin install amarel-vscode@amarel-vscode`. This doesn't change any of the
> phase steps below.

If you're using a **bare LLM** (ChatGPT web, Claude.ai, a local Ollama model, etc.)
with no project-instruction system, see the **ChatGPT, Claude.ai, or any bare LLM** section in [`README.md`](README.md)
for a copy-paste prompt.

---

## What this repo does

Sets up VS Code Remote-SSH against the **Rutgers Amarel HPC cluster**. Amarel is
migrating from CentOS 7 (glibc 2.17) to **RHEL 9.6 (glibc 2.34)** on the new host
`amarel-new.hpc.rutgers.edu`. VS Code Server 1.99+ requires glibc 2.28, which
CentOS 7 cannot provide — so on the **legacy CentOS 7 host** we install a tarball
with glibc 2.28 + libstdc++ + patchelf into the user's `$HOME` and wire
`~/.bashrc` to point VS Code at it; on **RHEL 9.6** VS Code Server runs natively
and the sysroot is skipped (**Phase 5.5** detects which and routes). Once
connected, **Phase 11** also fixes the Source Control "no Git repository" failure
(legacy CentOS 7's git 1.8.3.1 is too old for VS Code's repo probe; RHEL 9.6's git
~2.43 passes natively) by pointing `git.path` at a modern git when needed, and
**Phase 12** optionally wires up GitHub auth + identity.

---

## How to run this skill (read this first)

> **Execution contract:**
> 1. This skill executes `[EXEC]` steps autonomously via its Bash tool; it never asks the user to run them.
> 2. All `[EXEC]` steps are noninteractive: SSH/SCP calls use `-o BatchMode=yes`; no interactive prompts are expected. **Key-auth denial scope (Phases 1–5):** before the key is loaded into the agent (Phase 4.1), the **skip probes** (Phase 1.0 Gate-1 and Phase 3.0) return `Permission denied (publickey,…)` *by construction* — this is an **expected routing signal**, not a failure (Phase 1.0 silences this probe's stderr; only its exit code routes SKIP/PROCEED). Treat an auth failure as a hard failure to escalate only (a) on any `[EXEC]` step in Phases 6–12, or (b) in Phases 1–5 if a denial persists **after** Phase 4.2 confirms the key is loaded (e.g. the Phase 4.2.1 dedupe should succeed once the key is loaded). Never re-run a `[TTY]` password/passphrase step (e.g. Phase 3.1) in response to an expected pre-load denial. Any *non-auth* error (network, missing tool, unexpected output) is always surfaced.
> 3. Key state discovered during execution (`LOCAL_OS`, `NetID`, `REPO_ROOT`, `USE_TARBALL`) is recorded at the phase that first establishes it and reused in all subsequent phases without re-deriving.
> 4. **Host lock (transition period):** Two valid targets — the new **`amarel-new.hpc.rutgers.edu`** (RHEL 9.6, the default this runbook uses) and the legacy **`amarel.rutgers.edu`** (CentOS 7, being retired). Commands below are written for `amarel-new.hpc.rutgers.edu`; if the user is deliberately on the legacy host, substitute `amarel.rutgers.edu` in every command. Do **not** substitute any *other* hostname — not `amarel2.rutgers.edu`, not any other `*.rutgers.edu` host. Phase 5.5 auto-detects the remote glibc and routes the sysroot work accordingly, so whichever of the two hosts the user targets is handled correctly.
> 5. **Verify; never take "done" on faith.** When a step hands off to the user (a `[TTY]` command, a GUI action, a `fresh` reset, a `gh` login) and they reply "done", run a read-only probe to confirm the *actual* outcome **before you advance or ask the next question** — the user saying it worked is not proof it worked. And before running any step, probe whether its outcome is already in place: if it is, **skip** it (a resume); if stale residue from a prior run remains where a `fresh` start should have cleaned it, **remove it first**. The skip-probes (Phases 1, 3, 4, 7, 9, 11, 12) already embody this — extend the same discipline to every hand-off, including the reset and the GitHub steps that historically advanced on the user's word alone.

**Two entry modes — decide before Phase 0.**
- **Full setup** (first-time VS Code-on-Amarel): run Phases 0 → 12 in order.
- **Targeted repair** (the user is *already connected* — status bar shows
  `SSH: amarel-new.hpc.rutgers.edu` — and only reports a **Source Control** problem
  ["no Git repository", the repo won't sync, "Initialize Repository" keeps
  appearing] or a **GitHub** push/auth problem): still run **Phase 0**
  (preflight), then **Phase 0.2** confirms key auth and routes you **straight to
  Phase 11** (Source Control) or **Phase 12** (GitHub). Do **not** drag an
  already-connected user back through key generation, the host-key prompt, or
  sysroot deployment (Phases 1–10).

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

**LLM operator rule — paste-safe TTY hand-offs (width budget).** A TTY command
longer than ~70 characters wraps in the rendered terminal; the copied text then
carries injected newlines **plus** the code-block indent, and the paste breaks
(the live run hit `ssh-copy-id: ERROR: Too many arguments` / split tokens this
way). Source being "one line" does NOT prevent this — line *length* vs terminal
*width* is the cause. Rule:
- TTY command <= ~70 chars → hand it inline as a single-line fenced block.
- TTY command > ~70 chars → first stage it to a wrapper script via `[EXEC]`
  (`~/.cache/amarel-vscode/step-<phase>.sh` with a `#!/usr/bin/env bash` shebang
  so it runs under bash regardless of the user's login shell; Windows:
  `$env:LOCALAPPDATA\amarel-vscode\step-<phase>.ps1`), then hand the user only
  the short launcher: `bash <path>` (macOS/Linux) or
  `pwsh -ep Bypass -File "<path>"` (Windows; `-ep` is short for
  `-ExecutionPolicy`). Quote the path.
  Launch via the interpreter (`bash`/`pwsh -File`), never `./file`. Remove the
  staged file in the next `[EXEC]` verify. Today only Phase 3.1 exceeds the budget.

**LLM operator rule — isolate the copy-paste payload.** The user must see at a
glance exactly what to copy, and copy *only* that. Whenever you hand over a
command to run or a value to type:
- Put it in its **own standalone fenced code block** — on its own line, nothing
  else inside the fence (no instructions, no comments, no success marker) and
  **no leading `>` blockquote prefix on the fence**. The reference pattern is the
  Phase 1.2 hand-off: the `> **🔒 YOUR TURN:** …` instruction is a blockquote,
  then the command sits in a separate fence *outside* the quote. Do **not** nest
  the fence inside the `>` quote — in a terminal that renders the command flush
  against the instruction prose and the user copies both.
- Keep every instruction ("run this", "type your passphrase when prompted",
  "paste the last 5 lines back") as prose **outside** the fence.
- Never embed a runnable command or paste-value inline in a sentence. Inline
  backticks are for *referring* to a command, not handing one over — if it's
  meant to be copied, it gets its own fence.
- One payload per fence. Two commands → two fences with a line of prose between,
  so the user can never select both as one blob.

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

The complete human touch-point list — everything not on this list is `[EXEC]`:

| # | Phase | Command / Action | Why human | OS |
|---|---|---|---|---|
| 1 | 1.2 | `ssh-keygen -t ed25519 …` | Passphrase prompt on TTY — LLM cannot see | All |
| 2 | 3.1 | `bash ~/.cache/amarel-vscode/step-3.1.sh` (staged ssh-copy-id) | **⚠ LAST AMAREL PASSWORD EVER** — password on TTY | All |
| 3 | 3.1.1 | `ssh -i ~/.ssh/id_ed25519_amarel -o IdentitiesOnly=yes <NetID>@amarel-new.hpc.rutgers.edu` | Key passphrase on TTY; confirms key installed | All |
| 4 | 4.1 | `ssh-add --apple-use-keychain …` / `ssh-add …` | Passphrase to agent on TTY | All |
| 5 | 10 | VS Code GUI — click Allow, watch status bar | No Bash equivalent | All |

**TTY budget:** macOS = 5 · Linux = 5 · Windows = 6 (Phase 4.1 Windows has two
mandatory steps: `Start-Service` + `ssh-add`. The Phase 4.4 `~/.zshrc` append
is `[EXEC]`, not a hand-off — see Phase 4.4).

**Linux keychain note:** The Linux per-session guarantee means zero prompts
within a single login session. A reboot-spanning guarantee requires persistent
keyring autostart that the skill cannot configure — the skill points the user
at their distro docs and continues.

### The 60-second map — orient the user before Phase 0 (print this)

New users don't know what's ahead, so before Phase 0 print this plain-English
map of the whole journey. Keep narrating as you go (each phase already prints a
one-line description), but this is the orientation that makes the rest make sense:

> **Here's the whole setup, start to finish — so you can follow along:**
> 1. **Keys (Phases 1–5)** — we create an SSH key just for Amarel and install it,
>    so you stop typing your Amarel password. You'll touch the terminal about 4
>    times (one extra on Windows): set a key passphrase, type your Amarel password
>    **once** (your last time ever), do a test login, and save the passphrase to
>    your keychain.
> 2. **The GLIBC fix (Phases 6–8, legacy CentOS 7 only)** — on the old host I
>    download a small "sysroot" (a newer glibc bundle) into your Amarel home and
>    point VS Code Server at it, which clears the `GLIBC >= 2.28` error. **On the
>    new RHEL 9 host (amarel-new) Phase 5.5 auto-detects this and skips it** —
>    nothing to install.
> 3. **Connect (Phases 9–10)** — on the legacy host I flip one VS Code setting,
>    then you connect from VS Code's **Remote-SSH** menu (on RHEL 9 you just
>    connect — no setting needed).
> 4. **Git & GitHub (Phases 11–12, optional)** — if you'll use Source Control, I
>    point VS Code at a modern git on Amarel; Phase 12 wires up GitHub if you push
>    from Amarel.
>
> You don't need to understand each command — before every step I'll tell you what
> it does and what success looks like, and **I check the result myself before
> moving on**, so you can't get silently stuck.

### Heads-up: your terminal moments

Tell the user up front (I run everything else myself via Bash). You will switch
to your terminal **four** times (macOS/Linux) or **five** times (Windows), in
this order:

1. **Phase 1.2** — `ssh-keygen`: set a key passphrase (typed twice).
2. **Phase 3.1** — install your key: your **last Amarel password ever**.
3. **Phase 3.1.1** — test login: your key passphrase.
4. **Phase 4.1** — `ssh-add`: your key passphrase, saved to the keychain.
   *(Windows: also `Start-Service ssh-agent` first — needs admin PowerShell.)*

I hand you each command when it's time and verify the result before advancing —
so we keep them one at a time rather than all at once. Nothing else needs your
terminal.

---

## Phase 0 — Preflight

**Goal:** Detect the user's local OS, confirm OpenSSH tools are present, and
confirm Amarel is reachable on the VPN. **Run these yourself via Bash.**

**macOS / Linux — run yourself:**

[EXEC]
```bash
case "$(uname -s)" in
  Darwin) echo "✓ OS: macOS" ;;
  Linux)  echo "✓ OS: Linux" ;;
  *)      echo "✗ OS: unsupported ($(uname -s))" ;;
esac
for c in ssh scp ssh-keygen ssh-add ssh-copy-id ssh-keyscan nc; do
  command -v "$c" >/dev/null && echo "✓ $c" || echo "✗ $c MISSING"
done
nc -z -w 5 amarel-new.hpc.rutgers.edu 22 && echo "✓ VPN: Amarel reachable" || echo "✗ VPN: cannot reach amarel-new.hpc.rutgers.edu:22"
```

**Windows PowerShell — run yourself:**

[EXEC]
```powershell
if ($IsWindows) { "✓ OS: Windows" } else { "✗ OS: not Windows" }
foreach ($c in 'ssh','scp','ssh-keygen','ssh-add','ssh-keyscan') {
  if (Get-Command $c -ErrorAction SilentlyContinue) { "✓ $c" } else { "✗ $c MISSING" }
}
if (Test-NetConnection amarel-new.hpc.rutgers.edu -Port 22 -InformationLevel Quiet) { "✓ VPN: Amarel reachable" } else { "✗ VPN: cannot reach amarel-new.hpc.rutgers.edu:22" }
```

**Success:** the OS line is `✓ OS: macOS`, `✓ OS: Linux`, or `✓ OS: Windows`,
and every other line begins with `✓`.

**If you see** `✗ ... MISSING`: on macOS/Linux install `openssh-client`; on
Windows install OpenSSH client via *Settings → Apps → Optional features*.
Windows lacks `ssh-copy-id` by default — Phase 3 has a proven workaround.

**If you see** `✗ VPN`: tell the user to connect to Rutgers VPN and stop —
nothing below will work without it.

**Record `LOCAL_OS` from the OS line, then ask the user for their NetID and advance.**

### 0.1 — Fresh start or resume? (ask the user — explain it, don't just ask)

Existing state from a previous run — an installed key, a deployed sysroot,
merged settings — makes the skip-probes in Phases 1, 3, 4, 7, 9, and 11 fire, so
the skill fast-forwards and can report success **without re-exercising those
steps**. That is the right behaviour for a normal resume, but it hides problems
when something has drifted: you changed your Amarel password, rotated keys, or a
prior run only half-finished. A new user has **no context to choose blindly** and
will often just pick `resume` — so spell out both choices in plain language
**before any setup work**, then offer:

> **🔒 YOUR TURN — fresh start or resume?**
>
> **First time setting this up on this computer?** There's nothing yet to wipe,
> so **`resume`** is the right answer — it simply runs every step from the
> beginning (there's just nothing to skip). You'd get the same result from
> `fresh`, only after a no-op cleanup.
>
> **Done this before, or a previous attempt half-finished?**
> - **`resume`** — keep what's already set up and skip what's already done.
>   Fastest. Pick this to continue a setup, or to fix one specific thing.
> - **`fresh`** — wipe everything this skill created (your local Amarel key, the
>   sysroot on Amarel, and the skill's settings) and rebuild from scratch. Pick
>   this if you changed your Amarel password, want to re-key, a prior run left
>   things broken, or you want a guaranteed-clean verification run.
>
> Not sure? **`resume` is the safe default** — the skill detects what's missing
> and fills only the gaps; it won't redo or break anything already working.

**If the user chose `fresh`:** run the **`full`** reset from the `## Fresh start`
section now — it removes the skill's `ssh_config` / `known_hosts` / `~/.zshrc`
entries, deletes the local `id_ed25519_amarel` key pair, and wipes everything the
skill deployed on Amarel (the `authorized_keys` line, the extracted
`~/.vscode-server/sysroot` + `sysroot.sh`, the `~/.bashrc` loader block, and the
Phase 11 `git-modern.sh` wrapper + `git.path`/`extensions.verifySignature`
settings), so **every** phase (1–11) re-runs from scratch. It never touches any
other SSH host or key.

**Then verify the reset actually cleaned up before starting Phase 1 — don't take
"done" on faith.** The Amarel-side wipe is best-effort (it's skipped if key auth
was already broken), so confirm the local artifacts are gone and tell the user
plainly what, if anything, the reset could not reach:

**macOS/Linux — run yourself:**

[VERIFY]
```bash
echo "Post-reset cleanliness check:"
test -f ~/.ssh/id_ed25519_amarel && echo "  ✗ local key pair still present" || echo "  ✓ local key pair removed"
ssh -G amarel-new.hpc.rutgers.edu 2>/dev/null | grep -qE '^identityfile.*id_ed25519_amarel' && echo "  ✗ ssh_config amarel block still present" || echo "  ✓ ssh_config amarel block removed"
grep -qE '^amarel(-new\.hpc)?\.rutgers\.edu ' ~/.ssh/known_hosts 2>/dev/null && echo "  ✗ known_hosts amarel entry still present" || echo "  ✓ known_hosts amarel entry removed"
grep -q 'id_ed25519_amarel' ~/.zshrc 2>/dev/null && echo "  ✗ ~/.zshrc loader still present" || echo "  ✓ ~/.zshrc loader removed"
```

**Windows PowerShell — run yourself:**

[VERIFY]
```powershell
"Post-reset cleanliness check:"
if (Test-Path "$HOME\.ssh\id_ed25519_amarel") { "  ✗ local key pair still present" } else { "  ✓ local key pair removed" }
if ((ssh -G amarel-new.hpc.rutgers.edu 2>$null) -match 'identityfile.*id_ed25519_amarel') { "  ✗ ssh_config amarel block still present" } else { "  ✓ ssh_config amarel block removed" }
if ((Get-Content "$HOME\.ssh\known_hosts" -ErrorAction SilentlyContinue) -match '^amarel(-new\.hpc)?\.rutgers\.edu ') { "  ✗ known_hosts amarel entry still present" } else { "  ✓ known_hosts amarel entry removed" }
```

- **All `✓`** → the local side is clean; begin Phase 1.
- **Any `✗`** → the reset didn't fully apply; re-run it (it's idempotent) before continuing.
- **Amarel-side residue:** if the reset printed `• Skipped Amarel cleanup …`, key
  auth was already gone, so the old key line, sysroot, and any earlier
  `git.path` / `git-modern.sh` may still be on Amarel. That's fine — Phases 3, 7,
  and 11 overwrite them — but **say so explicitly** rather than implying a
  spotless cluster, so the user isn't surprised when those phases run.

**If the user chose `resume` (or didn't answer):** continue to Phase 1 — the
skip-probes handle the rest. (Skip-probes *skip what is already correctly in
place*; they do **not** scrub stale residue — that is exactly what `fresh` is
for, so don't reach for a resume when the user actually needs a clean slate.)

### 0.2 — Targeted-repair fast path (already connected → Source Control / GitHub)

Use this **instead of** the 0.1 fresh/resume offer when the user is already
connected and only needs the Source Control or GitHub fix (see "Two entry
modes" above). It avoids re-running the SSH-key and sysroot phases.

Substitute the user's NetID, then probe key auth (run yourself):

[EXEC]
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_amarel -o IdentitiesOnly=yes <NetID>@amarel-new.hpc.rutgers.edu true && echo "READY" || echo "NEEDS_SETUP"
```

- `READY` → passwordless SSH works (the same auth VS Code Remote-SSH uses), so
  the user is genuinely set up. **Jump straight to Phase 11** (Source Control);
  if they only asked about GitHub, jump to **Phase 12**. Skip Phases 1–10.
- `NEEDS_SETUP` → passwordless SSH is not working (they aren't set up yet, or
  connected with a password). Fall back to the normal flow — start at **Phase
  0.1** (fresh/resume) and proceed through **Phase 1.0**'s skip probe; Phase 11
  still runs at the end.

This is the path for "I'm already connected but Source Control says *no Git
repository*" — recognise the symptom, confirm with the probe, and go straight to
the fix.

---

## Phase 1 — Generate the Amarel SSH key (idempotent)

**Goal:** Create `~/.ssh/id_ed25519_amarel` (dedicated key for Amarel only —
keeps it separate from any GitHub key).

### 1.0 — Full skip probe (run yourself)

Before anything, probe whether key auth already works **and** the `ssh_config`
block is fully correct. This uses `-i` **with `-o IdentitiesOnly=yes`** so ssh
offers only the Amarel key — otherwise an unrelated key in your agent could
authenticate and falsely satisfy the gate (`-i` alone does not restrict which
agent keys ssh offers).

**macOS/Linux — run yourself:**

[EXEC]
```bash
# Gate 1: key auth (stderr silenced — only the exit code routes SKIP/PROCEED;
# a pre-setup "Permission denied"/"Host key verification failed" here is normal)
ssh -o BatchMode=yes -o ConnectTimeout=5 \
    -i ~/.ssh/id_ed25519_amarel -o IdentitiesOnly=yes \
    <NetID>@amarel-new.hpc.rutgers.edu true 2>/dev/null
KEY_OK=$?

# Gate 2: ssh_config block has all required keys
CFG=$(ssh -G amarel-new.hpc.rutgers.edu 2>/dev/null)
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

[EXEC]
```powershell
& ssh -o BatchMode=yes -o ConnectTimeout=5 `
    -i "$HOME\.ssh\id_ed25519_amarel" -o IdentitiesOnly=yes `
    "<NetID>@amarel-new.hpc.rutgers.edu" true 2>&1 | Out-Null
$keyOk = ($LASTEXITCODE -eq 0)
$cfg = & ssh -G amarel-new.hpc.rutgers.edu 2>$null
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
[EXEC]
```bash
test -f ~/.ssh/id_ed25519_amarel && echo "EXISTS — skip 1.2" || echo "MISSING — run keygen"
```

**Windows PowerShell:**
[EXEC]
```powershell
if (Test-Path "$HOME\.ssh\id_ed25519_amarel") { "EXISTS — skip 1.2" } else { "MISSING — run keygen" }
```

If `EXISTS`, skip to Phase 2.

### 1.2 — Generate key (user TTY step)

> **🔒 YOUR TURN:** `ssh-keygen` will prompt twice for a passphrase. Pick a
> strong one — you'll type it exactly once more (Phase 4.1), then the OS
> keychain stores it forever. **I cannot see what you type.**

**macOS/Linux:**

[TTY]
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_amarel -C amarel-vscode
```

**Windows PowerShell:**

[TTY]
```powershell
ssh-keygen -t ed25519 -f $HOME\.ssh\id_ed25519_amarel -C amarel-vscode
```

**Operator note — do not "improve" the `-C` comment.** It is the fixed literal
`amarel-vscode` (no `$(whoami)`/`$(hostname)`/`$env:` substitution, no quotes).
Two reasons: (1) a quoted comment with a `$(…)` expansion wraps on paste and
orphans the `-C` flag (`ssh-keygen: option requires an argument -- C` — the live
run hit exactly this); (2) Phases 1.0, 4.0, and 4.2 identify the key by
`grep amarel-vscode` against `ssh-add -l` output, so the comment must contain
that exact token.

**Wait for user "done", then verify the pub key exists yourself:**

[EXEC]
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

[EXEC]
```bash
grep -qE "^amarel(-new\.hpc)?\.rutgers\.edu " ~/.ssh/known_hosts 2>/dev/null && echo "ALREADY TRUSTED — skip Phase 2" || echo "NEEDS VERIFICATION"
```

If `ALREADY TRUSTED`, skip to Phase 3.

### 2.1 — Scan and fingerprint (run yourself)

Scan to a fixed path under `~/.ssh/`, fingerprint that exact file, then append
only what was fingerprinted. A shell variable from `mktemp` will not survive
across separate ssh invocations — use a fixed path so steps 2.1 and 2.3 see
the same file.

**macOS/Linux:**

[EXEC]
```bash
ssh-keyscan -t ed25519 amarel-new.hpc.rutgers.edu 2>/dev/null > ~/.ssh/amarel_hostkey.pending
ssh-keygen -lf ~/.ssh/amarel_hostkey.pending
```

**Windows PowerShell:**

[EXEC]
```powershell
ssh-keyscan -t ed25519 amarel-new.hpc.rutgers.edu 2>$null | Set-Content "$HOME\.ssh\amarel_hostkey.pending"
ssh-keygen -lf "$HOME\.ssh\amarel_hostkey.pending"
```

**Show the fingerprint output to the user.**

### 2.2 — Verify the fingerprint (you auto-compare against the pin)

**Both transition hosts are pinned, so verify this yourself — do not make the user
eyeball it.** Compare the `SHA256:…` from 2.1 against the recorded reference for the
targeted host:

- **`amarel-new.hpc.rutgers.edu` (RHEL 9.6, default):**
  `SHA256:bKbfUNxVCu2nQvssMuNBFtzoR3J7BxXU5RSI9MjWi+E` (recorded 2026-06-05)
- **`amarel.rutgers.edu` (legacy CentOS 7):**
  `SHA256:cN6l3kR3jbdOv6Ofz1b+KNCt3LaOCj9bq6yeHoR3eLs` (recorded 2026-05-26)

Then act on the result:

- **Match** → tell the user `✓ matches the recorded <host> fingerprint — verified`
  and continue to **2.3**. No user prompt needed.
- **Mismatch** → **HARD STOP.** Show both the scanned and recorded values and tell
  the user this is a possible man-in-the-middle attack — **STOP and contact OARC**.
  Do **not** append the key or proceed.
- **Non-standard host** (a deliberate `AMAREL_HOST` that is neither pinned host) →
  there is no pin to check against, so fall back to the user:
  > **🔒 YOUR TURN:** No reference is recorded for this host. Compare the `SHA256:…`
  > above against Rutgers OARC's published value and confirm before continuing.

A security-conscious user may still cross-check the matched value against OARC. If
OARC confirms a key was legitimately rotated and gives you the new fingerprint
out-of-band, replace the pinned reference above and re-run Phase 2 — never update a
pin just because it stopped matching.

### 2.3 — Append exact temp file on user "yes" (run yourself)

**macOS/Linux:**

[EXEC]
```bash
cat ~/.ssh/amarel_hostkey.pending >> ~/.ssh/known_hosts && rm -f ~/.ssh/amarel_hostkey.pending && echo "✓ host key trusted"
```

**Windows PowerShell:**

[EXEC]
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

[EXEC]
```bash
ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_amarel -o IdentitiesOnly=yes <NetID>@amarel-new.hpc.rutgers.edu true 2>/dev/null && echo "ALREADY WORKS — skip Phase 3" || echo "NEEDS key install"
```

If `ALREADY WORKS`, skip to Phase 4.

### 3.1 — Install public key (user TTY step — LAST password entry ever)

**macOS / Linux.** This command is ~133+ chars and would wrap on paste, so
stage it to a short wrapper first (run yourself):

[EXEC]
```bash
mkdir -p ~/.cache/amarel-vscode
cat > ~/.cache/amarel-vscode/step-3.1.sh <<'EOF'
#!/usr/bin/env bash
ssh-copy-id -i ~/.ssh/id_ed25519_amarel.pub -o PreferredAuthentications=password -o PubkeyAuthentication=no <NetID>@amarel-new.hpc.rutgers.edu 2>&1 | grep -Ev "^Now try|^and check to make sure"
exit "${PIPESTATUS[0]}"
EOF
```

Then hand the user only the short runner (cannot wrap):

[TTY]
```bash
bash ~/.cache/amarel-vscode/step-3.1.sh
```

> **🔒 YOUR TURN:** the wrapper runs `ssh-copy-id`, which will prompt for your
> **Amarel password**. Type it once. This is the only time you will ever need it
> for VS Code. **I cannot see what you type.**

**Windows (no `ssh-copy-id`) — proven stdin-pipe pattern from `scripts/setup.ps1:213-220`:**

The `-tt` flag forces a TTY so Amarel's password prompt is visible. The pub
key is piped via stdin and read into a remote-side variable `KEY` with
`KEY="$(cat)"` so the key contents never have to be escaped into a
shell-quoted string. The `grep -qxF` guard prevents duplicate
authorized_keys entries. (Do **not** use `grep -qxF "$(cat)"` inline — that
would consume stdin into grep's argument and leave the append-cat empty.)

Stage the proven pipe-`pubkey`-into-`ssh -tt` block to a `.ps1` first (run
yourself). The `-tt` PTY allocation is what makes the password prompt appear —
it is preserved verbatim inside the wrapper:

[EXEC]
```powershell
$dir = "$env:LOCALAPPDATA\amarel-vscode"; New-Item -ItemType Directory -Force -Path $dir | Out-Null
@'
$remoteCmd = @"
KEY="`$(cat)"
umask 077
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
grep -qxF "`$KEY" ~/.ssh/authorized_keys || printf '%s\n' "`$KEY" >> ~/.ssh/authorized_keys
"@
Get-Content -Raw "$HOME\.ssh\id_ed25519_amarel.pub" | & ssh -tt -o PreferredAuthentications=password -o PubkeyAuthentication=no "<NetID>@amarel-new.hpc.rutgers.edu" $remoteCmd
'@ | Set-Content -Path "$dir\step-3.1.ps1" -Encoding UTF8
```

Then hand the user only the short launcher (quote the path — `$HOME` may contain
spaces):

[TTY]
```powershell
pwsh -ep Bypass -File "$env:LOCALAPPDATA\amarel-vscode\step-3.1.ps1"
```

> **🔒 YOUR TURN:** Amarel's password prompt will appear in the terminal.
> Type your password. **I cannot see what you type.**

### 3.1.1 — Verify login (user step)

> **🔒 YOUR TURN:** Run the login command for your OS and check that you get an Amarel shell prompt.

**macOS/Linux — copy this:**

[TTY]
```bash
ssh -i ~/.ssh/id_ed25519_amarel -o IdentitiesOnly=yes <NetID>@amarel-new.hpc.rutgers.edu
```

**Windows PowerShell — copy this:**

[TTY]
```powershell
ssh -i "$HOME\.ssh\id_ed25519_amarel" -o IdentitiesOnly=yes "<NetID>@amarel-new.hpc.rutgers.edu"
```

> SSH will prompt for your **key passphrase** (the one you set in Phase 1.2 — not your Amarel password). Enter it and check the result:
>
> - **Success:** you see an Amarel shell prompt like `[<NetID>@amarel1 ~]$`. Type `exit` and let me know.
> - **Failure:** `Permission denied (publickey,…)` — the key copy didn't take. Let me know and I'll diagnose.

**After the user confirms a successful login, remove the staged wrapper (run yourself):**

[EXEC]
```bash
rm -f ~/.cache/amarel-vscode/step-3.1.sh
```

Windows PowerShell:

[EXEC]
```powershell
Remove-Item -Force "$env:LOCALAPPDATA\amarel-vscode\step-3.1.ps1" -ErrorAction SilentlyContinue
```

**Wait for user confirmation before advancing.**

---

## Phase 4 — Save passphrase to OS keychain + write strict ssh_config

**Goal:** Add the key to `ssh-agent` so future SSH calls don't prompt for the
passphrase, and write a strict `ssh_config` block that VS Code will use.

### 4.0 — Check if key is already loaded (run yourself)

**macOS/Linux:**

[EXEC]
```bash
ssh-add -l 2>/dev/null | grep -q amarel-vscode && echo "LOADED — skip 4.1" || echo "NOT LOADED — run ssh-add"
```

**Windows PowerShell** (the `ssh-agent` service must be running — if `ssh-add -l` errors with "Could not open a connection", start it first via `Start-Service ssh-agent`):

[EXEC]
```powershell
$keyLoaded = (ssh-add -l 2>$null | Select-String -Quiet 'amarel-vscode')
if ($keyLoaded) { "LOADED — skip 4.1" } else { "NOT LOADED — run ssh-add" }
```

If `LOADED`, skip to 4.2.

### 4.1 — Add key to agent (user TTY step — passphrase saved to keychain)

**macOS:**

[TTY]
```bash
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_amarel
```

**macOS keychain-label note (for a clean future reverse-out):** `ssh-add` prints
a line like `Identity added: …/id_ed25519_amarel (amarel-vscode)`. You may
record that label from the visible stdout the user pastes back. **Do NOT** run
`security find-generic-password` or `security dump-keychain` to discover it —
those are on the security deny-list. The label is already in plain `ssh-add`
output; use that, never a keychain query.

**Linux:**

[TTY]
```bash
ssh-add ~/.ssh/id_ed25519_amarel
```

**Linux keychain note:** `ssh-add` saves the passphrase for this login session.
On reboot, you may need to re-enter once unless you configure gnome-keyring or
KWallet for persistent autostart. See your distro's documentation for that
one-time configuration. The skill sets up everything else automatically.

**Windows PowerShell — start the agent service, then add the key (user TTY step).**

The OpenSSH agent service must be running before `ssh-add`, and to keep SSH
passwordless across reboots the service should be set to auto-start.
Configuring or starting a Windows service needs an **Administrator** PowerShell
(right-click PowerShell → "Run as administrator"). This is advice, not a hard
rule — **you** choose whether to make the persistent change. Tell the user the
elevation requirement up front so they decide:

- **Recommended — auto-start on every boot** (the Windows equivalent of the
  macOS Keychain auto-load; keeps SSH passwordless after reboots). In an
  **Administrator** PowerShell:
  [TTY]
  ```powershell
  Get-Service ssh-agent | Set-Service -StartupType Automatic
  ```
- **Or skip that line** if you'd rather not make a persistent change — you'll
  just re-start the service yourself after each reboot.

Then start the service now and add your key (still an Administrator PowerShell):

[TTY]
```powershell
Start-Service ssh-agent
```

[TTY]
```powershell
ssh-add "$HOME\.ssh\id_ed25519_amarel"
```

> **🔒 YOUR TURN:** `ssh-add` will prompt for your key passphrase (from Phase
> 1.2). After this the keychain stores it (auto-start = across reboots; manual
> = this login session). **I cannot see what you type.** If `Set-Service` /
> `Start-Service` reports "Access is denied," your PowerShell isn't elevated —
> reopen it as Administrator and re-run.

**Wait for user "done".**

### 4.2 — Verify key loaded (run yourself)

**macOS/Linux:**

[VERIFY]
Command:  ssh-add -l | grep amarel-vscode
Pass:     line containing "amarel-vscode" printed
Fail:     no output / "The agent has no identities"
On fail:  re-run Phase 4.1 (ssh-add)
Advance:  Phase 4.2.1
```bash
ssh-add -l | grep amarel-vscode && echo "✓ key in agent"
```

**Windows PowerShell:**

[VERIFY]
Command:  ssh-add -l | Select-String 'amarel-vscode'
Pass:     line containing "amarel-vscode" printed
Fail:     no output
On fail:  re-run Phase 4.1 (ssh-add + Start-Service ssh-agent)
Advance:  Phase 4.2.1
```powershell
ssh-add -l 2>$null | Select-String 'amarel-vscode'
```

### 4.2.1 — Dedupe `authorized_keys` on Amarel (run yourself)

Now that the key is loaded in the agent, a `BatchMode` SSH authenticates — so
this dedupe actually runs (it was previously misplaced before the key load and
always failed). `ssh-copy-id` matches by full line, so whitespace/comment drift
across re-runs can append duplicate keys (the live run found three identical
copies). `sort -u` is idempotent:

[EXEC]
```bash
ssh -o BatchMode=yes -i ~/.ssh/id_ed25519_amarel -o IdentitiesOnly=yes <NetID>@amarel-new.hpc.rutgers.edu 'sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

**`-i … -o IdentitiesOnly=yes` is load-bearing here.** `ssh_config` isn't written
until Phase 4.3, so without it ssh offers *every* key in your agent; if you have
several, Amarel hits `MaxAuthTries` before your Amarel key is tried and returns a
**false** `Permission denied`. Pinning the identity makes ssh offer only the
Amarel key, so this reflects the real authorized_keys state.

If this *still* returns `Permission denied` with the identity pinned, the Amarel
key genuinely isn't in `~/.ssh/authorized_keys` — only then re-check the Phase
3.1 install (and confirm Phase 4.2 shows the key in the agent). Otherwise advance
to Phase 4.3.

### 4.3 — Write strict ssh_config (run yourself)

**Config file path:**
- macOS/Linux: `~/.ssh/config`
- Windows: `$HOME\.ssh\config`

**Parse any existing `Host amarel-new.hpc.rutgers.edu` block first:**

**macOS/Linux:**

[EXEC]
```bash
awk '/^Host amarel(-new\.hpc)?\.rutgers\.edu/{f=1;print;next} /^Host /{f=0} f' ~/.ssh/config 2>/dev/null || true
```

(Do **not** use an awk range like `/^Host amarel…/,/^Host [^ ]/` — the start line
also matches the end pattern, so on BSD awk the range collapses to just the header
line and you never see the block body.)

**Windows PowerShell:**

[EXEC]
```powershell
$lines = Get-Content "$HOME\.ssh\config" -ErrorAction SilentlyContinue
$inBlock = $false
foreach ($l in $lines) {
  if ($l -match '^Host amarel(-new\.hpc)?\.rutgers\.edu') { $inBlock = $true }
  elseif ($l -match '^Host ' -and $inBlock) { $inBlock = $false }
  if ($inBlock) { $l }
}
```

**Decision logic:**

- **If no `Host amarel-new.hpc.rutgers.edu` block exists** → append the canonical block below.
- **If a block exists but is missing or has wrong values for `User`, `IdentityFile`, `IdentitiesOnly`, `AddKeysToAgent`, `ControlMaster`, or (macOS only) `UseKeychain`** → surface the diff to the user and ask them to edit the file manually (do not blindly overwrite — they may have custom `ProxyCommand`, `LocalForward`, etc.). Re-verify after user "done".

**Canonical block to append if absent:**

```
Host amarel-new.hpc.rutgers.edu
    User <NetID>
    IdentityFile ~/.ssh/id_ed25519_amarel
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes
    ControlMaster auto
    ControlPath ~/.ssh/control-%r@%h:%p
    ControlPersist 10m
```

*macOS only:* include `UseKeychain yes`. Linux and Windows: omit it. `ControlMaster`/`ControlPath`/`ControlPersist` apply to all platforms — they multiplex VS Code's multiple SSH channels over one authenticated socket, eliminating repeated key negotiation.

**Append command (macOS/Linux):**

[EXEC]
```bash
cat >> ~/.ssh/config <<'EOF'

Host amarel-new.hpc.rutgers.edu
    User <NetID>
    IdentityFile ~/.ssh/id_ed25519_amarel
    IdentitiesOnly yes
    AddKeysToAgent yes
    UseKeychain yes
    ControlMaster auto
    ControlPath ~/.ssh/control-%r@%h:%p
    ControlPersist 10m
EOF
chmod 600 ~/.ssh/config
```

*(Linux: omit the `UseKeychain yes` line.)*

**Append command (Windows PowerShell):**

Follows the same parse → diff → ask logic as macOS/Linux above. If the
`Host amarel-new.hpc.rutgers.edu` block is absent, append; if it is present with
mismatching values, surface the diff and ask the user to edit manually.
Note: `UseKeychain yes` is **macOS-only** and is OMITTED on Windows. `ControlMaster` is not supported on Windows OpenSSH — omit all three Control* lines on Windows.

[EXEC]
```powershell
$cfg = @"

Host amarel-new.hpc.rutgers.edu
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

[VERIFY]
Command:  ssh -G amarel-new.hpc.rutgers.edu | grep -E …
Pass:     all five lines present: user <NetID>, identityfile id_ed25519_amarel, identitiesonly yes, addkeystoagent yes, controlmaster auto
Fail:     any of the five lines missing or wrong value
On fail:  re-edit ~/.ssh/config per decision logic above; re-verify
Advance:  Phase 4.4 (macOS) or Phase 5 (Linux/Windows)
```bash
ssh -G amarel-new.hpc.rutgers.edu | grep -E '^(user|identityfile|identitiesonly|addkeystoagent|controlmaster) '
```

Must show `user <NetID>`, `identityfile ~/.ssh/id_ed25519_amarel`,
`identitiesonly yes`, `addkeystoagent yes`, `controlmaster auto`.

**Wait for verification to pass, then advance.**

### 4.4 — macOS Sequoia keychain regression fix (macOS only)

macOS 15 (Sequoia) broke persistent keychain auto-load: `UseKeychain yes` no
longer reloads the key into the agent automatically after a reboot. Without
this fix, the first `ssh` after a reboot prompts for the passphrase again.

**Self-guarding append (run yourself, macOS only).** One atomic command: the
`grep -qF` guard and the append are a single statement, so any number of
re-runs yields exactly one copy (this replaced a probe-then-append pattern that
could double-append across sessions). It is **not** a TTY hand-off — the
appended `ssh-add` reads the passphrase silently from the Keychain:

[EXEC]
```bash
grep -qF '# Amarel HPC — re-load SSH key from Keychain' ~/.zshrc 2>/dev/null || cat >> ~/.zshrc <<'EOF'

# Amarel HPC — re-load SSH key from Keychain on each shell (macOS Sequoia fix)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_amarel 2>/dev/null
EOF
```

The appended `ssh-add` runs at each future shell startup and reads the
passphrase silently from the macOS Keychain. The `2>/dev/null` suppresses
"identity already added" when the key is already loaded.

**Verify (run yourself after user "done"):**

[EXEC]
```bash
grep -q 'id_ed25519_amarel' ~/.zshrc && echo "✓ ~/.zshrc updated" || echo "✗ line missing — re-run the append above"
```

*Linux:* skip — the agent is session-scoped and this pattern doesn't help.  
*Windows:* skip — the ssh-agent service persists across sessions without this workaround.

**Wait for verification to pass, then advance.**

---

## Phase 5 — Verify passwordless SSH end-to-end

**Goal:** Prove that a non-interactive `ssh` succeeds with no prompts.
This is what VS Code's Remote-SSH will use. **Run yourself.**

[VERIFY]
Command:  ssh -o BatchMode=yes -o ConnectTimeout=10 amarel-new.hpc.rutgers.edu 'echo ok; hostname; whoami'
Pass:     three lines: "ok", Amarel hostname (e.g. amarel1.amarel-new.hpc.rutgers.edu), NetID
Fail:     hangs, "Permission denied", or fewer than three lines
On fail:  re-run Phase 4.2 verify and Phase 4.3 ssh_config validation
Advance:  Phase 6
```bash
ssh -o BatchMode=yes -o ConnectTimeout=10 amarel-new.hpc.rutgers.edu 'echo ok; hostname; whoami'
```

**Success:** three lines — `ok`, an Amarel login-node hostname (e.g.
`amarel1.amarel-new.hpc.rutgers.edu`), and the NetID.

**If it hangs or errors:** key auth is not fully working. Re-run Phase 4.2
verify and Phase 4.3 ssh_config validation. For a deeper diagnostic, **hand
the user** this command — it is interactive (no `BatchMode`), so they (not
the agent) run it to surface a real password prompt or full handshake trace:

> **🔒 YOUR TURN — diagnostic only:** `ssh -v amarel-new.hpc.rutgers.edu` (interactive; shows the full SSH handshake)

If their output shows `Authentications that can continue: publickey,…` and
then fails, the `authorized_keys` permissions on Amarel are wrong — the
agent can fix that autonomously:

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'chmod 600 ~/.ssh/authorized_keys; chmod 700 ~/.ssh'
```

**Wait for the three success lines, then advance.**

---

## Phase 5.5 — Detect the remote platform (choose native vs legacy)

**Goal:** Amarel is mid-migration from **CentOS 7.9 (glibc 2.17)** to **RHEL 9.6
(glibc 2.34)**. VS Code Server 1.99+ needs glibc ≥ 2.28, so the custom-glibc
sysroot (Phases 6–8) and the signature workaround (Phase 9) are needed **only on
the legacy CentOS 7 host**. Decide which host the user is on by probing the
**remote glibc** (not the hostname), then route. **Run this yourself.**

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'ldd --version 2>/dev/null | head -1; . /etc/os-release 2>/dev/null; printf "OSREL=%s-%s\n" "${ID:-?}" "${VERSION_ID:-?}"'
```

Read the glibc version from the first line (e.g. `ldd (GNU libc) 2.34`):

- **glibc ≥ 2.28 → `PLATFORM=NATIVE` (RHEL 9).** **Skip Phases 6, 7, 8, and 9
  entirely** — there is no sysroot to install and no signature workaround to
  apply. Go straight to **Phase 10** (Connect), then **Phase 11** (Source
  Control) and optional **Phase 12**.
- **glibc < 2.28 → `PLATFORM=LEGACY` (CentOS 7).** Continue with Phase 6 as
  written.
- **Probe inconclusive** (no glibc line, or an SSH hiccup): default to
  **LEGACY** and say so — installing the sysroot on an RHEL 9 host is harmless
  (at worst unused), whereas skipping it on a real CentOS 7 host is not.

> **Why route on glibc, not the hostname?** During the transition a DNS alias may
> resolve either way; the glibc version is what VS Code Server actually gates on,
> so it is the reliable signal. Record `PLATFORM` and reuse it in Phases 6–11.

### 5.5b — NATIVE only: strip any legacy sysroot residue (run this yourself)

> **Do this on `PLATFORM=NATIVE` before connecting; skip it on LEGACY.** If this
> `$HOME` was *ever* set up against the legacy CentOS 7 host, `~/.bashrc` still
> sources the custom-glibc loader (`~/.vscode-server/sysroot.sh`, which exports
> `VSCODE_SERVER_CUSTOM_GLIBC_*`). VS Code **honors those env vars on RHEL 9** and
> pops a *"You are about to connect to an OS version that is unsupported by Visual
> Studio Code"* dialog — and forces the sysroot code path — even though native
> glibc 2.34 needs none of it. Remove the loader, the sysroot, and any server that
> was patchelf'd against it (it would fail to start natively). `data/` is kept.

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
set -u
cleaned=0
if [ -f "$HOME/.bashrc" ] && grep -q 'vscode-server/sysroot\.sh' "$HOME/.bashrc" 2>/dev/null; then
  sed -i.bak -e '/# VS Code Server custom glibc workaround/d' -e '\#vscode-server/sysroot\.sh#d' "$HOME/.bashrc"; cleaned=1
fi
if [ -e "$HOME/.vscode-server/sysroot" ] || [ -e "$HOME/.vscode-server/sysroot.sh" ] || [ -e "$HOME/sysroot.sh" ]; then
  rm -rf "$HOME/.vscode-server/sysroot" "$HOME/.vscode-server/sysroot.sh" "$HOME/sysroot.sh"; cleaned=1
fi
if [ "$cleaned" = 1 ]; then
  rm -rf "$HOME/.vscode-server/bin" "$HOME/.vscode-server/cli" 2>/dev/null
  echo "✓ Removed legacy sysroot residue — VS Code will reinstall natively"
else
  echo "✓ No legacy sysroot residue — clean native host"
fi
REMOTE
```

**Success marker:** either `✓ Removed legacy sysroot residue …` or `✓ No legacy
sysroot residue …`. Then continue to **Phase 5.5c**.

### 5.5c — NATIVE only: add `amarel.rutgers.edu` alias to `ssh_config` (run this yourself)

VS Code's **Recents** tab caches hostnames. A user who previously connected via
`amarel.rutgers.edu` (the legacy CentOS 7 host) will see that stale entry in the
dropdown and land on the old host (glibc 2.17 → `GLIBC >= 2.28` error) even after
a clean NATIVE setup. Adding an alias makes any click on the old hostname
transparently redirect to `amarel-new.hpc.rutgers.edu` — so stale Recents entries
and copy-pasted commands both work without hitting the wrong host.

**Only run on `PLATFORM=NATIVE`.** Check whether the alias block already exists
first, then append if absent:

**macOS/Linux:**

[EXEC]
```bash
grep -qE '^Host amarel\.rutgers\.edu' ~/.ssh/config 2>/dev/null && echo "ALIAS_EXISTS — skip 5.5c" || {
cat >> ~/.ssh/config <<EOF

Host amarel.rutgers.edu
    HostName amarel-new.hpc.rutgers.edu
    User <NetID>
    IdentityFile ~/.ssh/id_ed25519_amarel
    IdentitiesOnly yes
EOF
echo "✓ alias added"
}
ssh -G amarel.rutgers.edu | grep '^hostname '
```

**Windows PowerShell:**

[EXEC]
```powershell
$cfg = "$HOME\.ssh\config"
if ((Get-Content $cfg -ErrorAction SilentlyContinue) -match '^Host amarel\.rutgers\.edu') {
  "ALIAS_EXISTS — skip 5.5c"
} else {
  Add-Content -Path $cfg -Value "`nHost amarel.rutgers.edu`n    HostName amarel-new.hpc.rutgers.edu`n    User <NetID>`n    IdentityFile ~/.ssh/id_ed25519_amarel`n    IdentitiesOnly yes"
  "✓ alias added"
}
& ssh -G amarel.rutgers.edu | Select-String '^hostname '
```

**Success marker:** `hostname amarel-new.hpc.rutgers.edu`. Then continue to **Phase 10** (Connect).

---

## Phase 6 — Locate the sysroot tarball

> **⚙️ Legacy CentOS 7 only — auto-skipped on RHEL 9.6.** If Phase 5.5 reported
> `PLATFORM=NATIVE`, skip Phases 6–9 and continue at **Phase 10**.

**Goal:** Find a valid sysroot tarball locally before downloading. **Run
all probes yourself.**

**Establish `REPO_ROOT` once (run yourself before any 6.x step).** The skill
is always cloned as a git repo, so resolve the repo root from `git` rather
than assuming the LLM's cwd:

**macOS/Linux:**

[EXEC]
```bash
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$REPO_ROOT" ]; then
  echo "ABORT: this skill must be invoked from inside the amarel-vscode git checkout" >&2
  exit 1
fi
```

**Windows PowerShell:**

[EXEC]
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

[EXEC]
```bash
TARBALL="$REPO_ROOT/build/vscode-sysroot-x86_64-linux-gnu.tgz"
if [ -f "$TARBALL" ] && tar tzf "$TARBALL" >/dev/null 2>&1; then
  echo "FOUND: $TARBALL"; USE_TARBALL="$TARBALL"
else
  echo "NOT FOUND in build/"
fi
```

**Windows PowerShell:**

[EXEC]
```powershell
$tarball = "$REPO_ROOT\build\vscode-sysroot-x86_64-linux-gnu.tgz"
if ((Test-Path $tarball) -and (tar tzf $tarball > $null 2>&1; $LASTEXITCODE -eq 0)) {
  "FOUND: $tarball"; $USE_TARBALL = $tarball
} else { "NOT FOUND in build/" }
```

If found and valid, skip to 6.4.

### 6.1 — Local search (run yourself)

Search local storage before downloading. On macOS, `mdfind` queries the
Spotlight index which covers the full filesystem — if it returns nothing,
proceed directly to 6.2; do not run the slow `find` sweeps. On Linux/Windows,
run the home-directory sweep instead.

**macOS** — Spotlight search (run yourself):

[EXEC]
```bash
mdfind -name 'vscode-sysroot-x86_64-linux-gnu.tgz' 2>/dev/null
```

- **1+ matches** → validate with `tar tzf <path> >/dev/null` and use it; skip 6.2.
- **0 matches** → Spotlight found nothing on this machine; proceed to **6.2**.

**Linux** — home sweep (run yourself; skip on macOS):

[EXEC]
```bash
find ~ -name 'vscode-sysroot-x86_64-linux-gnu.tgz' 2>/dev/null
```

- **1 match** → validate and use it; skip 6.2.
- **0 matches** → proceed to **6.2**.

**Windows PowerShell** — home sweep (run yourself):

[EXEC]
```powershell
Get-ChildItem -Path $HOME -Recurse -Filter vscode-sysroot-x86_64-linux-gnu.tgz -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
```

- **1 match** → validate and use it; skip 6.2.
- **0 matches** → proceed to **6.2**.

### 6.2 — Download from GitHub Release (run yourself if still missing)

**macOS/Linux:**

[EXEC]
```bash
mkdir -p "$REPO_ROOT/build"
curl -fL https://github.com/solomonsjoseph/amarel-vscode/releases/latest/download/vscode-sysroot-x86_64-linux-gnu.tgz \
  -o "$REPO_ROOT/build/vscode-sysroot-x86_64-linux-gnu.tgz"
```

**Windows PowerShell:**

[EXEC]
```powershell
New-Item -ItemType Directory -Force -Path "$REPO_ROOT\build" | Out-Null
Invoke-WebRequest -Uri https://github.com/solomonsjoseph/amarel-vscode/releases/latest/download/vscode-sysroot-x86_64-linux-gnu.tgz `
  -OutFile "$REPO_ROOT\build\vscode-sysroot-x86_64-linux-gnu.tgz" -UseBasicParsing
```

**Verify SHA-256 against `assets/checksums.txt`:**

[VERIFY]
Command:  sha256 compare against assets/checksums.txt
Pass:     "✓ SHA-256 matches"
Warn:     "WARN: checksum not recorded" — proceed but note
Fail:     "ABORT: SHA-256 MISMATCH"
On fail:  do not extract; tell user to file an issue; re-download
Advance:  Phase 6.4
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

[VERIFY]
Command:  Get-FileHash compare against checksums.txt
Pass:     "✓ SHA-256 matches"
Warn:     "WARN: checksum not recorded" — proceed but note
Fail:     "ABORT: SHA-256 MISMATCH"
On fail:  do not extract; tell user to file an issue; re-download
Advance:  Phase 6.4
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

[EXEC]
```bash
uname -m
```

**Windows PowerShell:**

[EXEC]
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

[VERIFY] — exit code 0 = "✓ tarball is well-formed"; non-zero = delete and re-download from 6.2
```bash
tar tzf "$REPO_ROOT/build/vscode-sysroot-x86_64-linux-gnu.tgz" >/dev/null && echo "✓ tarball is well-formed" || echo "✗ tarball is corrupt — delete and re-download"
```

**Windows PowerShell:**

[VERIFY] — exit code 0 = "✓ tarball is well-formed"; non-zero = delete and re-download from 6.2
```powershell
tar tzf "$REPO_ROOT\build\vscode-sysroot-x86_64-linux-gnu.tgz" > $null 2>&1
if ($LASTEXITCODE -eq 0) { "✓ tarball is well-formed" } else { "✗ tarball is corrupt — delete and re-download" }
```

**Wait for `✓ tarball is well-formed`, then advance.**

---

## Phase 7 — Deploy the sysroot on Amarel

> **⚙️ Legacy CentOS 7 only — auto-skipped on RHEL 9.6** (Phase 5.5 `PLATFORM=NATIVE`).

**Goal:** Upload the tarball and `assets/sysroot.sh`, extract into
`~/.vscode-server/sysroot/`, run hard verification gates, and auto-remediate
any failures. **All autonomous `ssh`/`scp` from here use `-o BatchMode=yes`.**

> **Local vs remote command note:** `scp`/`ssh` invocation lines below differ
> per OS (Windows uses backslash paths; `~` doesn't expand at the call site —
> use `$HOME` or `$env:USERPROFILE`). The remote commands inside heredocs
> execute on Amarel and are identical across all local OSes.

### 7.1 — Upload tarball (run yourself)

**macOS/Linux:**

[EXEC]
```bash
scp -o BatchMode=yes "$REPO_ROOT/build/vscode-sysroot-x86_64-linux-gnu.tgz" <NetID>@amarel-new.hpc.rutgers.edu:~/
```

**Windows PowerShell:**

[EXEC]
```powershell
scp -o BatchMode=yes "$REPO_ROOT\build\vscode-sysroot-x86_64-linux-gnu.tgz" "<NetID>@amarel-new.hpc.rutgers.edu:~/"
```

### 7.2 — Upload sysroot.sh (run yourself)

**macOS/Linux:**

[EXEC]
```bash
scp -o BatchMode=yes "$REPO_ROOT/assets/sysroot.sh" <NetID>@amarel-new.hpc.rutgers.edu:~/
```

**Windows PowerShell:**

[EXEC]
```powershell
scp -o BatchMode=yes "$REPO_ROOT\assets\sysroot.sh" "<NetID>@amarel-new.hpc.rutgers.edu:~/"
```

### 7.3 — Fallback: fetch sysroot.sh via curl if 7.2 fails (run yourself)

If the `scp` of `sysroot.sh` fails (as happened in the canonical manual run),
fetch it directly on Amarel and verify its content before installing:

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
set -euo pipefail
[ -d "$HOME/.vscode-server" ] && chmod -R u+w "$HOME/.vscode-server" 2>/dev/null || true
rm -rf "$HOME/.vscode-server" "$HOME/.vscode-server-insiders" "$HOME/.vscode-cli"
REMOTE
```

### 7.6 — Extract sysroot (run yourself)

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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

[VERIFY]
Command:  remote 3-gate check (files, exports, patchelf ≥ 0.18)
Pass:     "✓ all verification gates passed"
Fail:     "FAIL: <gate-names>" on stderr
On fail:  route to Phase 7.8 branch matching failed gate(s); re-run 7.7 after remedy
Advance:  Phase 8
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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

[EXEC]
```bash
EXPECTED_SHA=$(awk '$2=="patchelf-0.18.0-x86_64.tar.gz" {print $1}' "$REPO_ROOT/assets/checksums.txt")
```

Then run the upgrade (note: unquoted `<<REMOTE` so `${EXPECTED_SHA}`
expands locally; `\$` on remote-only vars keeps them deferred to Amarel):

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<REMOTE
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

> **⚙️ Legacy CentOS 7 only — auto-skipped on RHEL 9.6** (Phase 5.5 `PLATFORM=NATIVE`).

**Goal:** Append the sysroot loader to `~/.bashrc` on Amarel (idempotent),
then verify the env var survives a non-interactive shell. **All steps run
yourself via `ssh -o BatchMode=yes`.**

> **`.bashrc` vs `.bash_profile`:** VS Code Remote-SSH spawns a non-interactive
> non-login bash shell, which sources `~/.bashrc`, **not** `~/.bash_profile`.
> The skill uses `.bashrc` exclusively.

### 8.1 — Idempotent append (run yourself)

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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

[VERIFY]
Command:  ssh -o BatchMode=yes … 'echo "$VSCODE_SERVER_PATCHELF_PATH"'
Pass:     prints /home/<NetID>/.vscode-server/sysroot/usr/bin/patchelf
Fail:     empty line
On fail:  inspect ~/.bashrc (Phase 8.3); move source line above any early return
Advance:  Phase 9
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'echo "$VSCODE_SERVER_PATCHELF_PATH"'
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

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'head -30 ~/.bashrc'
```

If the heredoc append didn't land cleanly (as happened in the canonical manual
run), give the user this manual fallback:

> **🔒 YOUR TURN:** SSH into Amarel — copy this:

[TTY]
```bash
ssh <NetID>@amarel-new.hpc.rutgers.edu
```

> Once you have the Amarel shell prompt, open `~/.bashrc` in an editor — copy this:

[TTY]
```bash
nano ~/.bashrc
```

> Scroll to the very end and add these two lines (copy the block below):

```
# VS Code Server custom glibc workaround
[ -f "$HOME/.vscode-server/sysroot.sh" ] && source "$HOME/.vscode-server/sysroot.sh"
```

> Save and exit: nano → Ctrl+O, Enter, Ctrl+X. Or vim → Esc, `:wq`, Enter.

Then re-run 8.2 to confirm.

**Wait for the correct path, then advance.**

---

## Phase 9 — Disable VS Code extension signature verification on Amarel

> **⚙️ Legacy CentOS 7 only — auto-skipped on RHEL 9.6.** The crash this works
> around only happens when the node binary is patchelf'd against the custom
> glibc; on RHEL 9 the server is unpatched, so signed extensions install
> normally. (If a RHEL 9 user ever hits `signature verification failed`, apply
> this same merge by hand.)

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

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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
- `TOOL=python3` or `TOOL=jq`, `STATE=SET` → setting already correct; Phase 9.1 runs regardless (idempotent) — proceed to 9.1.
- `TOOL=python3` or `TOOL=jq`, `STATE=NOT_SET` or `STATE=ABSENT` → proceed to
  9.1 using the matching tool branch.
- `STATE=PARSE_ERROR` → settings.json is malformed (distinct from missing
  tool); ask user how to proceed — either back up and overwrite, or have them
  fix the JSON manually. **Note:** `python3`/`jq` also report this for a *valid*
  JSON-with-comments (JSONC) file, which VS Code allows — inspect the file
  (`cat`, see 9.2) before assuming real corruption. A clean first install has no
  settings.json yet (`STATE=ABSENT`), so this only arises on re-runs.

> **Skip probe disabled — run on every execution.** The `verifySignature` fix is required for VS Code Server 1.99+ on CentOS 7 regardless of prior state.

### 9.1 — Merge setting (run yourself)

Pick the branch matching the `TOOL=…` token from 9.0. Both branches are
atomic (write to a tempfile on the same filesystem, then rename) and
idempotent.

**TOOL=python3 branch:**

[MANDATORY][EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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

[MANDATORY][EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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

[VERIFY]
Command:  tool-agnostic verifySignature=false check
Pass:     "VERIFIED"
Fail:     "FAIL_VERIFY" or "TOOL_MISSING"
On fail:  inspect settings.json (cat command in 9.2); fix JSON syntax or re-run 9.1
Advance:  Phase 10
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
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

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'cat ~/.vscode-server/data/Machine/settings.json'
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
> 4. From the list, pick the host **`amarel-new.hpc.rutgers.edu`**. The list shows host
>    *aliases* from your SSH config, so this is just `amarel-new.hpc.rutgers.edu` — your
>    NetID is already baked into the config; you do **not** type `NetID@host`.
> 5. First time only: click **Allow** on the "OS unsupported" warning.
> 6. Open View → Output, dropdown → Remote-SSH. Watch for `Server started`.
> 7. Bottom-left status bar shows **SSH: amarel-new.hpc.rutgers.edu** (green).
>
> ⚠️ **Pick the right entry.** The dropdown may also list a separate
> **`rutgers.edu`** entry (a different host that this skill did **not** create).
> **Do not click `rutgers.edu`** — it will not connect to Amarel. Always choose
> **`amarel-new.hpc.rutgers.edu`**. (That stray `rutgers.edu` entry is harmless for now;
> cleaning it out of your SSH config is a separate fix we'll do later.)

**Common failures (linked recovery branches; none run on a clean first install):**

- `expected GLIBC >= v2.28.0` → Phase 8 didn't take. Re-run 8.2; fix `~/.bashrc` if env var empty (8.3).
- `signature verification failed with UnknownError` on "Install in SSH" → run **Phase 9**. If Phase 9 reports `TOOL=NONE`, have the user add `module load python` to `~/.bashrc` (above any non-interactive `return`) so python3 reaches non-interactive shells, then re-trigger Phase 9.
- `Could not find pty 4 on pty host` → harmless cosmetic noise (seen in canonical manual run). Ignore.
- VS Code prompts for password → SSH key auth not fully working. Re-run Phase 4.2 verify and Phase 4.3 ssh_config validation.
- VS Code server segfaults / patching fails after Allow → likely patchelf issue; **Phase 7.7 should have caught this**, but re-run 7.7 → 7.8 if needed.
- Repeated install failures even after the above → recovery branch **Phase 7.5** (wipe). Opt-in only.
- Source Control panel shows *"doesn't have a Git repository / Initialize Repository"* on a folder that **is** a clone → the server is using CentOS 7's stock git 1.8.3.1. Continue to **Phase 11**.

**Once the status bar is green, the core sysroot setup is done.** If you'll use
git / Source Control in VS Code on Amarel, continue to **Phase 11** (and the
optional **Phase 12** for GitHub). If not, you're finished here.

---

## Phase 11 — Source Control: point VS Code at a modern git

> **On RHEL 9.6 (amarel-new):** the system git is already modern (~2.43), so VS
> Code's probe passes and this phase writes nothing — the 11.0.1 skip-probe
> reports `SYSTEM_GIT_OK` and you continue to Phase 12. The Lmod `git-modern.sh`
> wrapper below is a **legacy CentOS 7** mechanism (stock git 1.8.3.1).

**Goal:** Make VS Code's Source Control panel detect your cloned repos. VS Code
Server resolves bare `git` from its **non-interactive PATH**, which on Amarel
(CentOS 7) is the OS-stock `/usr/bin/git` = **git 1.8.3.1**. VS Code's
repository-detection probe runs `git rev-parse --git-dir --git-common-dir`, and
`--git-common-dir` was introduced in **git 2.5** — so on 1.8.3.1 the probe fails
and VS Code registers **0 repositories** (the panel shows *"The folder currently
open doesn't have a Git repository / Initialize Repository"* even on a real
clone). The fix: set the machine-scoped **`git.path`** in the remote Machine
settings to a modern git on Amarel. **Run the `[EXEC]` steps yourself over `ssh
-o BatchMode=yes`** — this reuses the exact `settings.json` file and merge ladder
from Phase 9.

> **When this matters:** only once you open a git repo on Amarel in VS Code. If
> Source Control already shows your branch and changes, `git.path` is already
> correct — skip to Phase 12 (or finish). This phase is independent of the
> "unsupported OS" banner, which is harmless once the sysroot is in place.

### 11.0 — Probe: which git does the server see? (run yourself)

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'command -v git; git --version'
```

**Success marker:** if this prints `git version 1.8.x` (or anything below 2.5),
the fix is likely needed — continue to **11.0.1**, which decides for certain. If it
already prints `git version 2.5`+ **and** Source Control already works, 11.0.1 will
confirm you can skip straight to Phase 12.

### 11.0.1 — Already configured and working? (skip-probe — run yourself)

Don't re-apply the fix when it's already in place — and detect the case where IT
later upgraded Amarel's git so the fix is no longer needed. This runs VS Code's
exact repo-detection probe (`git rev-parse --git-dir --git-common-dir`, in a clean
server-like env + throwaway repo) against (1) the `git.path` already in
`settings.json`, then (2) the server's default git, and reports which:

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
set -uo pipefail
SETTINGS_FILE="$HOME/.vscode-server/data/Machine/settings.json"
ge25() { awk -v v="${1:-0.0}" 'BEGIN{split(v,a,"."); exit !(((a[1]+0)>2)||((a[1]+0)==2&&(a[2]+0)>=5))}'; }
# VS Code's exact repo-detection probe through a given git, in a clean server-like
# env + throwaway repo. Passes only if that git works AND is >= 2.5.
probe() {
  local g="$1" ver repo rc
  ver="$(env -i PATH=/usr/bin:/bin HOME="$HOME" "$g" --version 2>/dev/null | awk '/^git version/{print $3; exit}')"
  ge25 "$ver" || return 1
  repo="$(mktemp -d "${TMPDIR:-/tmp}/amarel-scm.XXXXXX")"
  /usr/bin/git init -q "$repo" 2>/dev/null || true
  ( cd "$repo" && env -i PATH=/usr/bin:/bin HOME="$HOME" "$g" rev-parse --git-dir --git-common-dir ) >/dev/null 2>&1
  rc=$?; rm -rf "$repo"; return $rc
}
# Read the git.path VS Code would use (python3 -> jq -> dependency-free sed).
GP=""
if [ -f "$SETTINGS_FILE" ]; then
  if command -v python3 >/dev/null 2>&1; then
    GP="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("git.path",""))' "$SETTINGS_FILE" 2>/dev/null)"
  elif command -v jq >/dev/null 2>&1; then
    GP="$(jq -r '."git.path" // empty' "$SETTINGS_FILE" 2>/dev/null)"
  fi
  [ -n "$GP" ] || GP="$(sed -n 's/.*"git\.path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SETTINGS_FILE" 2>/dev/null | head -n1)"
fi
if [ -n "$GP" ] && probe "$GP"; then
  echo "ALREADY_OK: git.path is set and passes the probe ($GP) — skip 11.1"
elif probe git; then
  echo "SYSTEM_GIT_OK: the server's default git is already >= 2.5 and passes — no git.path needed"
elif [ -n "$GP" ]; then
  echo "NEEDS_FIX: git.path is set ($GP) but no longer passes (module moved/updated?) — run 11.1"
else
  echo "NEEDS_FIX: no working modern git configured — run 11.1"
fi
REMOTE
```

Routing:

- `ALREADY_OK` → the configured `git.path` already satisfies VS Code's probe — the
  "present git is already good enough → skip" case, **including after an IT git
  update that your config still clears**. **Skip 11.1**; go to **11.2**'s live
  confirm (the automated check already passed here), or on to Phase 12.
- `SYSTEM_GIT_OK` → IT upgraded Amarel's *default* git to ≥ 2.5, so no `git.path`
  override is needed at all → **skip the whole fix → Phase 12**.
- `NEEDS_FIX` → nothing is configured yet, **or** a previously-working `git.path`
  stopped passing (e.g. IT retired the exact module build) → **run 11.1** to
  (re)detect and write it.

### 11.1 — Detect a modern git and write `git.path` (run yourself)

**Run this only when 11.0.1 reported `NEEDS_FIX`.** One idempotent remote block: it initialises Lmod in the non-interactive shell,
adds Amarel's community module tree (`/projects/community/modulefiles`, where the
git modules actually live), and loads a modern `git` module. It then **prefers the
modern git's absolute path**: if that binary runs standalone in a **clean,
server-like environment** (no module libraries needed — true on Amarel), it points
`git.path` straight at the binary — fastest, and it can **never silently fall back
to the stock git** the way a `module load; exec git` wrapper can. Only if the
binary needs its module environment to run does it write the
`~/.vscode-server/git-modern.sh` wrapper (which re-creates that environment, then
execs the modern git **by absolute path** — never a bare `git` — so a failed
module load still can't resolve to CentOS 7's git 1.8.3.1). Either way it merges
`"git.path"` into `~/.vscode-server/data/Machine/settings.json` (preserving
`extensions.verifySignature` and every other key). If no git ≥ 2.5 can be found at
all, it stops with `NO_MODERN_GIT`.

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
set -uo pipefail
VSROOT="$HOME/.vscode-server"
SETTINGS_DIR="$VSROOT/data/Machine"
SETTINGS_FILE="$SETTINGS_DIR/settings.json"
WRAPPER="$VSROOT/git-modern.sh"

# git >= 2.5 ? (needs --git-common-dir, which VS Code's repo probe uses)
ge25() { awk -v v="${1:-0.0}" 'BEGIN{split(v,a,"."); exit !(((a[1]+0)>2)||((a[1]+0)==2&&(a[2]+0)>=5))}'; }

# Make Lmod usable in THIS non-interactive shell, then load a modern git.
if ! command -v module >/dev/null 2>&1; then
  for i in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
    [ -f "$i" ] && . "$i" 2>/dev/null && break
  done
fi
# Amarel's git modules live in the community tree, NOT on the default MODULEPATH;
# add it before `module load git`, or the load silently finds nothing and we drop
# to NO_MODERN_GIT even though a modern git is sitting right there.
if command -v module >/dev/null 2>&1; then
  [ -d /projects/community/modulefiles ] && module use /projects/community/modulefiles 2>/dev/null || true
  module load git >/dev/null 2>&1 || true
fi
MODERN_GIT="$(command -v git 2>/dev/null || true)"
MODERN_VER="$([ -n "$MODERN_GIT" ] && "$MODERN_GIT" --version 2>/dev/null | awk '/^git version/{print $3; exit}')"
# Version when the modern git runs in a CLEAN, server-like env (no Lmod, no
# module libs) -- exactly how VS Code Server invokes it. Empty/old here means the
# binary needs its module environment to run.
CLEAN_VER="$([ -n "$MODERN_GIT" ] && env -i PATH=/usr/bin:/bin HOME="$HOME" "$MODERN_GIT" --version 2>/dev/null | awk '/^git version/{print $3; exit}')"

mkdir -p "$VSROOT"
if [ -n "$MODERN_GIT" ] && ge25 "$CLEAN_VER"; then
  # Best case (true on Amarel): the modern git is self-sufficient -- it runs
  # standalone with no module libraries -- so point git.path straight at the
  # binary. No per-call Lmod cost, and (unlike a `module load; exec git` wrapper)
  # it can NEVER silently fall back to the stock git if a future module load
  # fails -- a missing binary fails loudly instead.
  rm -f "$WRAPPER"
  GITPATH="$MODERN_GIT"
  CHOSEN="absolute path $MODERN_GIT -> git $MODERN_VER (runs standalone; no wrapper needed)"
elif [ -n "$MODERN_GIT" ] && ge25 "$MODERN_VER"; then
  # The modern git works only with its module environment (it needs libraries the
  # module provides -- CLEAN_VER came back empty/old). Write a wrapper that
  # re-creates that env, then execs the modern git by its ABSOLUTE path (never a
  # bare `git`), so a failed module load still can't resolve to stock 1.8.3.1.
  cat > "$WRAPPER" <<WRAP
#!/usr/bin/env bash
# Written by amarel-vscode. VS Code Server calls this as git.path in a
# non-interactive context where Lmod is not initialised. Set up the module
# environment (this git needs its module libraries), then exec the modern git by
# ABSOLUTE path -- never bare 'git', so a failed module load can't make VS Code
# silently fall back to the CentOS 7 stock git (1.8.3.1). Keep stdout clean:
# only git may write to it (some Lmod sites log to stdout).
{
  if ! command -v module >/dev/null 2>&1; then
    for i in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
      [ -f "\$i" ] && . "\$i" 2>/dev/null && break
    done
  fi
  if command -v module >/dev/null 2>&1; then
    [ -d /projects/community/modulefiles ] && module use /projects/community/modulefiles 2>/dev/null
    module load git 2>/dev/null
  fi
} >/dev/null 2>&1
exec "${MODERN_GIT}" "\$@"
WRAP
  chmod +x "$WRAPPER"
  WRAP_VER="$(env -i PATH=/usr/bin:/bin HOME="$HOME" bash "$WRAPPER" --version 2>/dev/null | awk '/^git version/{print $3; exit}')"
  if ge25 "$WRAP_VER"; then
    GITPATH="$WRAPPER"; CHOSEN="wrapper (module env) -> git $WRAP_VER [binary needs module libs]"
  else
    rm -f "$WRAPPER"
    echo "NO_MODERN_GIT" >&2
    echo "Found git $MODERN_VER but it would not run via the module wrapper in a clean env." >&2
    echo "Run 'module use /projects/community/modulefiles && module spider git' on Amarel, then set git.path manually (Phase 11.3)." >&2
    exit 3
  fi
else
  rm -f "$WRAPPER"
  echo "NO_MODERN_GIT" >&2
  echo "No git >= 2.5 found (system git: $(/usr/bin/git --version 2>/dev/null))." >&2
  echo "Run 'module use /projects/community/modulefiles && module spider git' on Amarel, then set git.path manually (Phase 11.3)." >&2
  exit 3
fi

# Merge git.path into the remote Machine settings.json (preserve all other keys).
mkdir -p "$SETTINGS_DIR"
if ! command -v python3 >/dev/null 2>&1; then
  command -v module >/dev/null 2>&1 && { module load python3 2>/dev/null || module load python 2>/dev/null || true; }
fi
if command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS_FILE" "$GITPATH" <<'PY' || { echo "ERR: settings.json merge failed" >&2; exit 1; }
import json, os, sys
path, gp = sys.argv[1], sys.argv[2]
data = {"extensions.verifySignature": False}
if os.path.exists(path) and os.path.getsize(path) > 0:
    with open(path) as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            sys.exit(f"ERR: {path} is not valid JSON ({exc}); refusing to overwrite")
    if not isinstance(data, dict):
        sys.exit(f"ERR: {path} root is not a JSON object; refusing to overwrite")
data["git.path"] = gp
tmp = path + ".tmp"
with open(tmp, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")
os.replace(tmp, path)
PY
elif command -v jq >/dev/null 2>&1; then
  TMP="$(mktemp "$SETTINGS_DIR/settings.json.XXXXXX")"
  trap 'rm -f "$TMP"' EXIT
  if [ -s "$SETTINGS_FILE" ]; then
    jq --arg gp "$GITPATH" '. + {"git.path": $gp}' "$SETTINGS_FILE" > "$TMP" \
      || { echo "ERR: $SETTINGS_FILE is not valid JSON; refusing to overwrite" >&2; exit 1; }
  else
    jq -n --arg gp "$GITPATH" '{"extensions.verifySignature": false, "git.path": $gp}' > "$TMP"
  fi
  mv -f "$TMP" "$SETTINGS_FILE"
else
  echo "ERR: neither python3 nor jq on Amarel; cannot merge settings.json" >&2
  exit 1
fi
echo "✓ git.path set: $CHOSEN"
REMOTE
```

**Success marker:** `✓ git.path set: …` (it tells you whether it chose the
wrapper or an absolute path). The merge is idempotent — re-running is safe.
Continue to **11.2** to verify the fix end-to-end.

**If you see `NO_MODERN_GIT`:** Amarel exposes no git ≥ 2.5 the script could
auto-load. Use the 11.3 fallback.

### 11.2 — Verify the fix

**First, an automated check (run yourself).** This reproduces VS Code's exact
repo-detection probe — `git rev-parse --git-dir --git-common-dir` — through the
`git.path` you just wrote, inside a throwaway repo in a clean server-like
environment, and returns a clear PASS/FAIL. It is the deterministic "does the fix
actually work?" test; you don't have to eyeball the GUI to know.

[VERIFY]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'REMOTE'
set -uo pipefail
SETTINGS_FILE="$HOME/.vscode-server/data/Machine/settings.json"
ge25() { awk -v v="${1:-0.0}" 'BEGIN{split(v,a,"."); exit !(((a[1]+0)>2)||((a[1]+0)==2&&(a[2]+0)>=5))}'; }
# Read the git.path VS Code will actually use.
GP=""
if command -v python3 >/dev/null 2>&1; then
  GP="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("git.path",""))' "$SETTINGS_FILE" 2>/dev/null)"
elif command -v jq >/dev/null 2>&1; then
  GP="$(jq -r '."git.path" // empty' "$SETTINGS_FILE" 2>/dev/null)"
fi
# Last-resort parse if neither python3 nor jq is on this shell (Amarel paths have no quotes/backslashes).
[ -n "$GP" ] || GP="$(sed -n 's/.*"git\.path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SETTINGS_FILE" 2>/dev/null | head -n1)"
[ -n "$GP" ] || { echo "FAIL: git.path is not set in $SETTINGS_FILE -- run 11.1 first." >&2; exit 1; }
GP_VER="$(env -i PATH=/usr/bin:/bin HOME="$HOME" "$GP" --version 2>/dev/null | awk '/^git version/{print $3; exit}')"
STOCK_VER="$(/usr/bin/git --version 2>/dev/null | awk '/^git version/{print $3; exit}')"
# Throwaway repo; run VS Code's exact probe with cwd = repo (as VS Code does).
TESTREPO="$(mktemp -d "${TMPDIR:-/tmp}/amarel-scm.XXXXXX")"
trap 'rm -rf "$TESTREPO"' EXIT
/usr/bin/git init -q "$TESTREPO" 2>/dev/null || true
if ( cd "$TESTREPO" && env -i PATH=/usr/bin:/bin HOME="$HOME" "$GP" rev-parse --git-dir --git-common-dir ) >/dev/null 2>&1 && ge25 "$GP_VER"; then
  GP_OK=1
else
  GP_OK=0
fi
echo "VS Code repo-detection probe: git rev-parse --git-dir --git-common-dir"
echo "  via git.path : git ${GP_VER:-<none>}  ->  $([ $GP_OK = 1 ] && echo PASS || echo FAIL)   [$GP]"
echo "  stock git    : git ${STOCK_VER:-?} (too old for --git-common-dir; the bug Phase 11 fixes)"
if [ $GP_OK = 1 ]; then
  echo "✓ Source Control fix VERIFIED -- VS Code will detect repositories."
else
  echo "✗ git.path does NOT satisfy the probe -- re-run 11.1, or use the 11.3 fallback." >&2
  exit 1
fi
REMOTE
```

**Success marker:** `✓ Source Control fix VERIFIED …`, with the `via git.path`
line showing `PASS`. A `FAIL` there (or `git.path is not set`) means re-run 11.1,
or use the 11.3 fallback if Amarel exposes no modern git. (The `stock git` line is
informational — it shows the old `/usr/bin/git` version VS Code would otherwise
use.)

**Then confirm it live (your turn).**

> **🔒 YOUR TURN:** In your connected VS Code window, open the Command Palette
> (`Cmd/Ctrl+Shift+P`) and run **Developer: Reload Window**.

After it reloads, open the Source Control panel, then check **View → Output** and
pick **Git** in the dropdown.

- **Success:** Source Control shows your branch + changes; the Git Output shows
  `Using git "2.x"` and `repositories (1)`. You're done with Phase 11.
- **Still empty:** paste the first ~10 lines of the Git Output back to me.

### 11.3 — Fallback: set `git.path` by hand (only if 11.1 said `NO_MODERN_GIT`)

Find the module name yourself:

[TTY]
```bash
ssh <NetID>@amarel-new.hpc.rutgers.edu 'bash -lc "module use /projects/community/modulefiles; module avail git"'
```

(`bash -lc` so Lmod is initialised, and `module use …` so Amarel's community
git modules are visible — a bare `module spider git` finds nothing without it.)
Paste the output back and I'll re-run 11.1 loading the exact module
(`module load git/<version>`). Or set it in the GUI: VS Code **Settings** →
switch to the **Remote [SSH: amarel-new.hpc.rutgers.edu]** tab → search `git.path` → set
it to the modern git's absolute path (or to a wrapper that runs `module load
git`) → **Developer: Reload Window**.

---

## Phase 12 — (Optional) GitHub authentication & git identity

**Goal:** Let git on Amarel authenticate to GitHub without password prompts and
commit with an identity GitHub accepts. **Skip this phase entirely if you only
edit files and never push to GitHub from Amarel.**

These steps run **in a terminal on Amarel** — use VS Code's integrated terminal
(**Terminal → New Terminal** in your connected window) so `gh` and `git` are
Amarel's, not your laptop's. The device-flow code and the resulting token are
handled by `gh`; **I never see them.**

### 12.0 — Is `gh` available, and are you already signed in? (run yourself)

One probe answers both: it finds `gh` (adding Amarel's community module tree if
needed, same as Phase 11), prints the version, then checks `gh auth status` —
so we run the sign-in step **only if you are not already logged in**.

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'command -v gh >/dev/null 2>&1 || { for i in /etc/profile.d/modules.sh /etc/profile.d/lmod.sh /usr/share/lmod/lmod/init/bash; do [ -f "$i" ] && . "$i" 2>/dev/null && break; done; command -v module >/dev/null 2>&1 && { module use /projects/community/modulefiles 2>/dev/null; module load gh 2>/dev/null; }; }; if command -v gh >/dev/null 2>&1; then gh --version | head -1; gh auth status >/dev/null 2>&1 && echo AUTHED || echo NEEDS_LOGIN; else echo NO_GH; fi'
```

- `gh version …` + **`AUTHED`** → already signed in to GitHub. **Skip 12.1.** Go
  to 12.2 to make sure the git credential helper is wired (safe to re-run), then
  12.3 for identity.
- `gh version …` + **`NEEDS_LOGIN`** → `gh` is present but not authenticated →
  run **12.1**. If `gh` only resolved via the module, tell the user to run
  `module use /projects/community/modulefiles && module load gh` in the Amarel
  terminal first so `gh` is on PATH for 12.1.
- `NO_GH` → GitHub CLI isn't installed. Either `module spider gh` to find a
  module, or fall back to a Personal Access Token with git's `store`/`cache`
  helper (ask me) — then skip to 12.3.

### 12.1 — Sign in to GitHub (your turn — device flow, no browser on Amarel)

**Only if 12.0 reported `NEEDS_LOGIN`.** If it said `AUTHED`, you're already
signed in — skip to 12.2.

> **🔒 YOUR TURN:** In the VS Code integrated terminal **on Amarel**, run the
> command below. `gh` prints a one-time code and a URL — open the URL on your
> laptop, paste the code, approve. `BROWSER=` stops it trying to launch a
> browser on the headless cluster.

[TTY]
```bash
BROWSER= gh auth login --hostname github.com --git-protocol https
```

Choose **HTTPS** and **Login with a web browser** when prompted.

**When the user says they finished the device flow, verify it yourself before
advancing — don't take "done" on faith. Re-run the 12.0 probe (it reads only
login state, never the token):**

[VERIFY]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'command -v gh >/dev/null 2>&1 || { for i in /etc/profile.d/modules.sh /etc/profile.d/lmod.sh /usr/share/lmod/lmod/init/bash; do [ -f "$i" ] && . "$i" 2>/dev/null && break; done; command -v module >/dev/null 2>&1 && { module use /projects/community/modulefiles 2>/dev/null; module load gh 2>/dev/null; }; }; gh auth status >/dev/null 2>&1 && echo AUTHED || echo NEEDS_LOGIN'
```

- `AUTHED` → login worked; advance to 12.2.
- `NEEDS_LOGIN` → the device flow didn't complete (or `gh` resolved only via the
  module — then tell them to run `module use /projects/community/modulefiles && module load gh`
  in the Amarel terminal first); have them re-run 12.1, then re-probe.

### 12.2 — Wire `gh` as git's credential helper

**Skip-probe first (run yourself — is it already wired? don't re-ask on a resume):**

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'git config --global --get-regexp "^credential\." 2>/dev/null | grep -qi "gh auth git-credential" && echo "ALREADY_WIRED — skip 12.2" || echo "NEEDS_SETUP_GIT"'
```

`ALREADY_WIRED` → the credential helper is already in place; skip to 12.3.
`NEEDS_SETUP_GIT` → hand the user the command below.

> **🔒 YOUR TURN:** still in the Amarel terminal — copy this. It must run
> **after** 12.1; it scopes the credential helper to `github.com` only.

[TTY]
```bash
gh auth setup-git
```

**After they say done, verify the helper is wired (run yourself — reads only the helper *command*, never a token):**

[VERIFY]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'git config --global --get-regexp "^credential\." 2>/dev/null | grep -qi "gh auth git-credential" && echo "✓ gh wired as git credential helper" || echo "✗ helper not set — re-run 12.2 (it must run after a successful 12.1)"'
```

### 12.3 — Set your git identity

**Skip-probe first (run yourself — is the identity already set? don't re-ask on a resume):**

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'n=$(git config --global user.name); e=$(git config --global user.email); if [ -n "$n" ] && [ -n "$e" ]; then case "$e" in *@users.noreply.github.com) echo "ALREADY_SET: $n <$e> — skip 12.3";; *) echo "SET_BUT_CHECK: $n <$e> — set, but NOT a no-reply address";; esac; else echo "NEEDS_IDENTITY"; fi'
```

- `ALREADY_SET …` → name + email are set and the email is a no-reply address; skip to 12.4 (or finish).
- `SET_BUT_CHECK …` → identity is set but the email isn't a no-reply address. Fine **if** GitHub email privacy is off; if it's on, pushes will hit **GH007**. Show the user the current value and let them decide whether to update it with the commands below.
- `NEEDS_IDENTITY` → not set; continue below.

Git needs a name + email to stamp commits. **Which email depends on your GitHub
account — not every user has email privacy on, so pick the case that fits:**

- **Email privacy ON** (GitHub → Settings → Emails → *"Keep my email address
  private"* is checked): you **must** use your GitHub **no-reply** address, or
  every push is rejected with **GH007** (12.4). It's shown on that same Emails
  page and looks like `12345678+yourname@users.noreply.github.com`.
- **Email privacy OFF:** you *may* use your real email — but the no-reply address
  still works and keeps your email out of public commit history, so it's the safe
  default either way.

**Recommended (works for everyone):** set your name and your no-reply address:

[TTY]
```bash
git config --global user.name "Your Name"
```

[TTY]
```bash
git config --global user.email "12345678+yourname@users.noreply.github.com"
```

Prefer your real email and you've confirmed privacy is OFF? Substitute it in the
second command — just know that turning privacy ON later will start rejecting
pushes until you switch to no-reply.

**After the user says they're done, verify the identity is set and flag any GH007
risk (run yourself). The email is stamped into every public commit — it is not a
secret — so reading it back is fine; unlike tokens, which the skill never reads:**

[VERIFY]
```bash
ssh -o BatchMode=yes <NetID>@amarel-new.hpc.rutgers.edu 'n=$(git config --global user.name); e=$(git config --global user.email); if [ -n "$n" ] && [ -n "$e" ]; then echo "✓ identity: $n <$e>"; case "$e" in *@users.noreply.github.com) echo "  (no-reply — safe whether or not email privacy is on)";; *) echo "  ⚠ not a no-reply address — if GitHub email privacy is ON, pushes will hit GH007 (see 12.4); switch to your no-reply address if so";; esac; else echo "✗ identity incomplete — re-run 12.3"; fi'
```

### 12.4 — If a push is rejected with `GH007` (private email)

After setting the no-reply email (12.3), re-stamp the offending commit, then push:

[TTY]
```bash
git commit --amend --reset-author --no-edit
```

Then `git push` again. If more than one commit carries the wrong address, use an
interactive rebase (`git rebase -i`) and re-stamp each, or `git filter-repo`.

**This is the end of the runbook.**

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
- Write a typed password/passphrase into a **staged wrapper script**
  (`~/.cache/amarel-vscode/step-*.sh`, `…\amarel-vscode\step-*.ps1`). Those are
  *command* files — they hold only flags, paths, the NetID, the host, and (on
  Windows) the public `.pub` key. The secret is always entered live at the
  prompt, never written to disk.
- Read, `cat`, or echo any GitHub token or `gh` credential (Phase 12): not
  `~/.config/gh/hosts.yml`, not the device-flow code, not a Personal Access
  Token. `gh auth login` stores and uses the token itself; the user types the
  device code into a browser on their own machine. Never paste a PAT into a
  command you run for them — hand them the command to run themselves.

If the user reports their password was leaked or something looks suspicious,
stop and tell them to rotate their Amarel password via Rutgers OARC.

---

## Fresh start (reset before a clean run)

This is what the **Phase 0.1** "fresh start" offer runs, and you can also use it
standalone any time a prior partial run left duplicate or stale state. It wipes
**only** what this skill creates and never touches any other SSH host (e.g. a
personal `Host rutgers.edu`) or any other key, and never reads private-key
contents. Two modes (the script takes one argument):

- **`config`** (default — `bash reset.sh`): cleans config-level state only —
  the `~/.zshrc` block, the skill's `Host amarel-new.hpc.rutgers.edu` `ssh_config`
  block, the `known_hosts` entries, and dedupes Amarel's `authorized_keys`.
  Leaves your key pair and the deployed sysroot in place.
- **`full`** (`bash reset.sh full`): a complete wipe of everything the skill
  created. On top of `config`, it deletes the local `id_ed25519_amarel` key pair
  and, in one SSH call (while key auth still works), removes the skill's key from
  Amarel's `authorized_keys`, deletes the deployed `~/.vscode-server/sysroot` +
  `sysroot.sh` (and any leftover upload), strips the `~/.bashrc` loader block,
  **removes the installed server binaries (`~/.vscode-server/bin` + `cli`) so a
  server patchelf'd against the now-deleted sysroot can't linger and break the
  next (native) connect, removes the Phase 11 `~/.vscode-server/git-modern.sh`
  wrapper, and strips the skill-written `git.path` and `extensions.verifySignature`
  keys from the remote Machine `settings.json`** (so it returns to its pre-skill
  state — `data/` and any keys you added yourself are preserved) — forcing **every** phase (1–11) to re-run from
  scratch (you'll set a new passphrase, enter your Amarel password once more,
  re-deploy the sysroot, and re-apply the Source Control fix). This is the mode
  the Phase 0.1 "fresh start" offer uses. The Amarel-side wipe pins the Amarel key
  (`-i … -o IdentitiesOnly=yes`) so it runs even when your agent holds other keys or
  no `ssh_config` block exists yet (a manual setup) — important, because if it were
  skipped, a previously hand-applied `git.path` / `git-modern.sh` would survive and
  make the next run look "already fixed" rather than a true clean test. It's still
  best-effort: if key auth is genuinely broken it's skipped, and Phases 3/7/11
  rebuild that state anyway.

Substitute the real NetID for `<NetID>`. Because the reset logic is long, stage
it to `~/.cache/amarel-vscode/reset.sh` via `[EXEC]` first (same width-budget
rule as Phase 3.1), with `<NetID>` substituted:

[EXEC]
```bash
mkdir -p ~/.cache/amarel-vscode
cat > ~/.cache/amarel-vscode/reset.sh <<'EOF'
#!/usr/bin/env bash
set -u
MODE="${1:-config}"   # "config" (default) or "full" (also deletes the key pair)

# 1) FULL or CONFIG: Amarel-side cleanup/dedupe first, while SSH config and keys are fully intact!
# Pin the Amarel key with -i + IdentitiesOnly so this SSH authenticates even when the
# ssh_config block is absent (e.g. a manual setup) or the agent holds other keys (without
# it, several agent keys can exhaust Amarel's MaxAuthTries -> false denial -> cleanup skipped
# -> a manually-applied git.path/git-modern.sh survives and contaminates the next test).
if [ "$MODE" = "full" ]; then
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_amarel -o IdentitiesOnly=yes <NetID>@amarel-new.hpc.rutgers.edu 'bash -se' <<'AMAREL' 2>/dev/null
set -u
sed -i.bak "/amarel-vscode/d" ~/.ssh/authorized_keys 2>/dev/null
rm -rf ~/.vscode-server/sysroot ~/.vscode-server/sysroot.sh ~/sysroot.sh ~/vscode-sysroot-x86_64-linux-gnu.tgz ~/.vscode-server/bin ~/.vscode-server/cli
rm -f ~/.vscode-server/git-modern.sh
[ -f ~/.bashrc ] && sed -i.bak -e "/# VS Code Server custom glibc workaround/d" -e "\#vscode-server/sysroot\.sh#d" ~/.bashrc
# Return the remote Machine settings.json to its pre-skill state: drop ONLY the
# two keys the skill wrote (git.path, extensions.verifySignature); keep user keys.
SETTINGS="$HOME/.vscode-server/data/Machine/settings.json"
if [ -f "$SETTINGS" ]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$SETTINGS" <<'PY' 2>/dev/null || true
import json, os, sys
p = sys.argv[1]
if os.path.exists(p) and os.path.getsize(p) > 0:
    try:
        with open(p) as f: d = json.load(f)
    except Exception:
        raise SystemExit(0)
    if isinstance(d, dict):
        for k in ("git.path", "extensions.verifySignature"): d.pop(k, None)
        tmp = p + ".tmp"
        with open(tmp, "w") as f:
            json.dump(d, f, indent=4); f.write("\n")
        os.replace(tmp, p)
PY
  elif command -v jq >/dev/null 2>&1; then
    TMP="$(mktemp)"; jq 'del(."git.path", ."extensions.verifySignature")' "$SETTINGS" > "$TMP" 2>/dev/null && mv -f "$TMP" "$SETTINGS" || rm -f "$TMP"
  fi
fi
AMAREL
  then
    echo "✓ Amarel: skill key, sysroot, ~/.bashrc loader, git-modern.sh, and git.path/verifySignature settings removed"
  else
    echo "• Skipped Amarel cleanup (key auth not active — Phase 3/7 re-install, or clean manually)"
  fi
else
  # CONFIG: dedupe authorized_keys on Amarel (same identity-pinning rationale as above)
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -i ~/.ssh/id_ed25519_amarel -o IdentitiesOnly=yes <NetID>@amarel-new.hpc.rutgers.edu 'sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys' 2>/dev/null; then
    echo "✓ Amarel authorized_keys deduped"
  else
    echo "• Skipped Amarel dedupe (key auth not set up yet — that's fine)"
  fi
fi

# 2) Remove the Amarel ssh-add block from ~/.zshrc (marker + the line after it)
[ -f ~/.zshrc ] && sed -i.bak '/# Amarel HPC — re-load SSH key from Keychain/,+1d' ~/.zshrc && echo "✓ ~/.zshrc cleaned"

# 3) Remove ONLY the skill-authored Host amarel-new.hpc.rutgers.edu block from ~/.ssh/config
if [ -f ~/.ssh/config ]; then
  cp ~/.ssh/config ~/.ssh/config.bak
  awk '
    /^Host[ \t]+amarel(-new\.hpc)?\.rutgers\.edu[ \t]*$/ { skip=1; next }
    skip==1 {
      if ($0 ~ /^Host[ \t]/) { skip=0 }
      else if ($0 ~ /^[ \t]/ || $0 ~ /^[ \t]*$/) { next }
      else { skip=0 }
    }
    { print }
  ' ~/.ssh/config.bak > ~/.ssh/config && chmod 600 ~/.ssh/config && echo "✓ ~/.ssh/config: amarel block removed (others kept)"
fi

# 4) Remove all amarel-new.hpc.rutgers.edu lines (any algorithm) from known_hosts
[ -f ~/.ssh/known_hosts ] && sed -E -i.bak '/^amarel(-new\.hpc)?\.rutgers\.edu /d' ~/.ssh/known_hosts && echo "✓ known_hosts: amarel entries removed"

# 5) Wiping agent keys and local key pair if FULL
if [ "$MODE" = "full" ]; then
  # Remove stale amarel-vscode keys from ssh-agent
  if ssh-add -l 2>/dev/null | grep -q "amarel-vscode"; then
    ssh-add -L | grep "amarel-vscode" | while read -r key; do
      temp_pub=$(mktemp)
      echo "$key" > "$temp_pub"
      ssh-add -d "$temp_pub" 2>/dev/null
      rm -f "$temp_pub"
    done
    echo "✓ Stale amarel-vscode keys removed from ssh-agent"
  fi
  # Delete the local Amarel key pair
  rm -f ~/.ssh/id_ed25519_amarel ~/.ssh/id_ed25519_amarel.pub && echo "✓ local Amarel key pair deleted"
fi
echo "Reset ($MODE) complete. Re-run the skill from Phase 0."
EOF
```

Then hand the user the short launcher. For the Phase 0.1 "fresh start" offer use
the `full` form; for a config-only repair omit the argument:

> **🔒 YOUR TURN — macOS / Linux.** Full reset (re-keys — what "fresh start" uses) — copy this:

[TTY]
```bash
bash ~/.cache/amarel-vscode/reset.sh full
```

Config-only reset (keeps your key pair) — copy this instead:

[TTY]
```bash
bash ~/.cache/amarel-vscode/reset.sh
```

**Windows PowerShell:** stage an equivalent `reset.ps1` to
`$env:LOCALAPPDATA\amarel-vscode\reset.ps1` (skip the macOS-only `~/.zshrc`
step):

[EXEC]
```powershell
$dir = "$env:LOCALAPPDATA\amarel-vscode"; New-Item -ItemType Directory -Force -Path $dir | Out-Null
@'
param([string]$Mode = 'config')   # 'config' (default) or 'full' (also deletes the key pair)
Set-StrictMode -Version Latest

# 1) FULL or CONFIG: Amarel-side cleanup/dedupe first, while SSH config and keys are fully intact!
if ($Mode -eq 'full') {
  & ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$HOME\.ssh\id_ed25519_amarel" -o IdentitiesOnly=yes <NetID>@amarel-new.hpc.rutgers.edu "sed -i.bak '/amarel-vscode/d' ~/.ssh/authorized_keys 2>/dev/null; rm -rf ~/.vscode-server/sysroot ~/.vscode-server/sysroot.sh ~/sysroot.sh ~/vscode-sysroot-x86_64-linux-gnu.tgz ~/.vscode-server/bin ~/.vscode-server/cli; rm -f ~/.vscode-server/git-modern.sh; [ -f ~/.bashrc ] && sed -i.bak -e '/# VS Code Server custom glibc workaround/d' -e '\#vscode-server/sysroot\.sh#d' ~/.bashrc; if command -v python3 >/dev/null 2>&1; then python3 -c 'import json,os;p=os.path.expanduser(`"~/.vscode-server/data/Machine/settings.json`");d=(json.load(open(p)) if os.path.exists(p) and os.path.getsize(p)>0 else {});d=(d if isinstance(d,dict) else {});[d.pop(k,None) for k in (`"git.path`",`"extensions.verifySignature`")];open(p,`"w`").write(json.dumps(d,indent=4)+chr(10))' 2>/dev/null; elif command -v jq >/dev/null 2>&1; then jq 'del(.`"git.path`", .`"extensions.verifySignature`")' ~/.vscode-server/data/Machine/settings.json > ~/.vscode-server/data/Machine/settings.json.tmp 2>/dev/null && mv -f ~/.vscode-server/data/Machine/settings.json.tmp ~/.vscode-server/data/Machine/settings.json; fi; true" 2>$null
  if ($LASTEXITCODE -eq 0) { "✓ Amarel: skill key, sysroot, ~/.bashrc loader, git-modern.sh, and git.path/verifySignature settings removed" } else { "• Skipped Amarel cleanup (key auth not active — Phase 3/7 re-install, or clean manually)" }
} else {
  & ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$HOME\.ssh\id_ed25519_amarel" -o IdentitiesOnly=yes <NetID>@amarel-new.hpc.rutgers.edu "sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys" 2>$null
  if ($LASTEXITCODE -eq 0) { "✓ Amarel authorized_keys deduped" } else { "• Skipped Amarel dedupe (key auth not set up yet — that's fine)" }
}

# 2) Remove ONLY the skill-authored Host amarel-new.hpc.rutgers.edu block from $HOME\.ssh\config
$config = "$HOME\.ssh\config"
if (Test-Path $config) {
  Copy-Item $config "$config.bak" -Force
  $out = [System.Collections.Generic.List[string]]::new()
  $skip = $false
  foreach ($line in Get-Content $config) {
    if ($line -match '^Host[ \t]+amarel(-new\.hpc)?\.rutgers\.edu[ \t]*$') { $skip = $true; continue }
    if ($skip) {
      if ($line -match '^Host[ \t]') { $skip = $false }
      elseif ($line -match '^[ \t]' -or $line -match '^[ \t]*$') { continue }
      else { $skip = $false }
    }
    if (-not $skip) { $out.Add($line) }
  }
  Set-Content -Path $config -Value $out -Encoding UTF8
  "✓ ${config}: amarel block removed (others kept)"
}

# 3) Remove all amarel-new.hpc.rutgers.edu lines (any algorithm) from known_hosts
$knownHosts = "$HOME\.ssh\known_hosts"
if (Test-Path $knownHosts) {
  Copy-Item $knownHosts "$knownHosts.bak" -Force
  $filtered = Get-Content $knownHosts | Where-Object { $_ -notmatch '^amarel(-new\.hpc)?\.rutgers\.edu ' }
  Set-Content -Path $knownHosts -Value $filtered -Encoding UTF8
  "✓ known_hosts: amarel entries removed"
}

# 4) Wiping agent keys and local key pair if FULL
if ($Mode -eq 'full') {
  # Remove stale amarel-vscode keys from ssh-agent
  if (ssh-add -l 2>$null | Select-String "amarel-vscode") {
    $tempFile = [System.IO.Path]::GetTempFileName()
    ssh-add -L | Select-String "amarel-vscode" | ForEach-Object {
      $_ | Set-Content $tempFile -Encoding Ascii
      & ssh-add -d $tempFile 2>$null
    }
    Remove-Item $tempFile -ErrorAction SilentlyContinue
    "✓ Stale amarel-vscode keys removed from ssh-agent"
  }
  # Delete local key pair
  Remove-Item -Force "$HOME\.ssh\id_ed25519_amarel","$HOME\.ssh\id_ed25519_amarel.pub" -ErrorAction SilentlyContinue
  "✓ local Amarel key pair deleted"
}
"Reset ($Mode) complete. Re-run the skill from Phase 0."
'@ | Set-Content -Path "$dir\reset.ps1" -Encoding UTF8
```

Then hand the user (use the `full` form for the Phase 0.1 "fresh start" offer):

> **🔒 YOUR TURN — Windows.** Full reset (re-keys — what "fresh start" uses) — copy this:

[TTY]
```powershell
pwsh -ep Bypass -File "$env:LOCALAPPDATA\amarel-vscode\reset.ps1" full
```

Config-only reset (keeps your key pair) — copy this instead:

[TTY]
```powershell
pwsh -ep Bypass -File "$env:LOCALAPPDATA\amarel-vscode\reset.ps1"
```

After the reset, start again at Phase 0.

## Power-user path (one-shot script)

If the user wants the whole thing run as a single script instead of
step-by-step, point them at:

```bash
./scripts/setup.sh        # macOS / Linux
pwsh scripts/setup.ps1    # Windows
```

The script does Phases 0–10 (plus the 9.5 git.path / Source Control step) in sequence with the same idempotency guarantees
and the same TTY-based prompts for passwords/passphrases. It does not
involve you (the LLM) at all. Recommend this path only if the user
explicitly asks for it.

## References

- Repo + issues: <https://github.com/solomonsjoseph/amarel-vscode>
- Microsoft FAQ (the supported workaround pattern): <https://code.visualstudio.com/docs/remote/faq#_can-i-run-vs-code-server-on-older-linux-distributions>
- ursetto/vscode-sysroot (upstream of the sysroot tarball): <https://github.com/ursetto/vscode-sysroot>
- AGENTS.md convention: <https://agents.md>

