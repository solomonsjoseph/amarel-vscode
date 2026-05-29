# Runbook Idempotency & Paste-Safety Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply seven fixes to the Amarel VS Code setup runbook so TTY commands can't corrupt on paste, file appends never duplicate, and dead/always-failing phases are removed — keeping `SKILL.md` and `AGENTS.md` in sync.

**Architecture:** Two parallel prose runbooks (`SKILL.md` = Claude Code entry point with YAML frontmatter; `AGENTS.md` = framework-neutral mirror) are edited section-by-section. There is no unit-test suite; verification is (a) `grep` assertions on each file, (b) a self-contained bash dummy-data harness that proves arg integrity and append idempotency, and (c) SKILL↔AGENTS parity checks. The 0–10 phase numbering is load-bearing and must not be renumbered (per `CLAUDE.md`); the removed Phase 3.2 simply disappears and the relocated dedupe becomes Phase 4.2.1.

**Tech Stack:** Markdown runbooks, bash/zsh + PowerShell snippets, OpenSSH, `grep`/`awk`/`sed`, `git`.

**Source spec:** `docs/superpowers/specs/2026-05-29-skill-runbook-idempotency-and-paste-safety-fixes-design.md`

---

## File map

| File | Responsibility | Touched by tasks |
|---|---|---|
| `SKILL.md` | Claude Code runbook (authoritative text) | 1–8 |
| `AGENTS.md` | Framework-neutral mirror — identical logical changes | 1–8 |
| `README.md` | Troubleshooting table — scan for Phase 3.2 / 3.1.5 refs | 9 |
| `docs/superpowers/plans/.../*.md` | This plan | — |

**Mirror rule (applies to every task):** `AGENTS.md` carries the same content with framework-neutral phrasing and a ~+18-to-+20-line offset (it has no YAML frontmatter and a longer execution-contract block). For each task: apply the SKILL.md edit, then open the matching `AGENTS.md` section (anchor strings are given per task), confirm its current wording, and apply the **same new text**. Task 9 verifies parity.

**Convention reminders (from `CLAUDE.md` / the runbook):**
- The agent substitutes the real NetID for every `<NetID>` before showing or writing a command. In staged heredocs below, `<NetID>` is a literal placeholder the agent replaces at write time.
- "🔒 YOUR TURN" marks a step the user types into. `[EXEC]` = agent runs via Bash; `[TTY]` = handed to the user.
- Host lock: the only target is `amarel.rutgers.edu`.

---

## Task 1: Paste-safe TTY hand-offs (Phase 3.1 wrapper + operator note + security note + TTY-budget row)

This is the priority fix. Long TTY commands wrap in the rendered terminal and corrupt on paste; we stage the one over-budget command (Phase 3.1) into a short wrapper the user runs.

**Files:**
- Modify: `SKILL.md` (operator note ~L61-65; Phase 3.1 macOS/Linux ~L360-365; Phase 3.1 Windows ~L380-390; Phase 3.1.1 cleanup ~L424; Security constraints ~L1559-1568; TTY budget row ~L103)
- Modify: `AGENTS.md` (operator note ~L67-71; Phase 3.1 ~L368-396; Security ~L1559-; TTY budget ~L103)

- [ ] **Step 1: Replace the operator note in `SKILL.md` with the width-budget rule**

Old string (exact):

```
**LLM operator rule — single-line TTY hand-offs.** Never present a multi-line or
`\`-continued command in a "🔒 YOUR TURN" block. Terminal paste mangles backslash
continuations (the live run hit exactly this: `ssh-copy-id: ERROR: Too many
arguments`). Collapse every command the user must type to a single line — they all
fit well under 200 chars.
```

New string:

```
**LLM operator rule — paste-safe TTY hand-offs (width budget).** A TTY command
longer than ~70 characters wraps in the rendered terminal; the copied text then
carries injected newlines **plus** the code-block indent, and the paste breaks
(the live run hit `ssh-copy-id: ERROR: Too many arguments` / split tokens this
way). Source being "one line" does NOT prevent this — line *length* vs terminal
*width* is the cause. Rule:
- TTY command ≤ ~70 chars → hand it inline as a single-line fenced block.
- TTY command > ~70 chars → first stage it to a wrapper script via `[EXEC]`
  (`~/.cache/amarel-vscode/step-<phase>.sh` with a `#!/usr/bin/env bash` shebang
  so it runs under bash regardless of the user's login shell; Windows:
  `$env:LOCALAPPDATA\amarel-vscode\step-<phase>.ps1`), then hand the user only
  the short launcher: `bash <path>` (macOS/Linux) or
  `pwsh -ExecutionPolicy Bypass -File "<path>"` (Windows). Quote the path.
  Launch via the interpreter (`bash`/`pwsh -File`), never `./file`. Remove the
  staged file in the next `[EXEC]` verify. Today only Phase 3.1 exceeds the budget.
```

- [ ] **Step 2: Replace the Phase 3.1 macOS/Linux TTY block in `SKILL.md` with stage-then-run**

Old string (exact):

````
**macOS / Linux:**

[TTY]
```bash
ssh-copy-id -i ~/.ssh/id_ed25519_amarel.pub -o PreferredAuthentications=password -o PubkeyAuthentication=no <NetID>@amarel.rutgers.edu
```

> **🔒 YOUR TURN:** `ssh-copy-id` will prompt for your **Amarel password**.
> Type it once. This is the only time you will ever need it for VS Code.
> **I cannot see what you type.**
````

New string:

````
**macOS / Linux.** This command is ~133+ chars and would wrap on paste, so
stage it to a short wrapper first (run yourself):

[EXEC]
```bash
mkdir -p ~/.cache/amarel-vscode
cat > ~/.cache/amarel-vscode/step-3.1.sh <<'EOF'
#!/usr/bin/env bash
ssh-copy-id -i ~/.ssh/id_ed25519_amarel.pub -o PreferredAuthentications=password -o PubkeyAuthentication=no <NetID>@amarel.rutgers.edu
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
````

- [ ] **Step 3: Replace the Phase 3.1 Windows block in `SKILL.md` with stage-then-run**

Old string (exact):

````
[TTY]
```powershell
$remoteCmd = @'
KEY="$(cat)"
umask 077
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
grep -qxF "$KEY" ~/.ssh/authorized_keys || printf '%s\n' "$KEY" >> ~/.ssh/authorized_keys
'@
Get-Content -Raw "$HOME\.ssh\id_ed25519_amarel.pub" | & ssh -tt -o PreferredAuthentications=password -o PubkeyAuthentication=no "<NetID>@amarel.rutgers.edu" $remoteCmd
```

> **🔒 YOUR TURN:** Amarel's password prompt will appear in the terminal.
> Type your password. **I cannot see what you type.**
````

New string:

````
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
Get-Content -Raw "$HOME\.ssh\id_ed25519_amarel.pub" | & ssh -tt -o PreferredAuthentications=password -o PubkeyAuthentication=no "<NetID>@amarel.rutgers.edu" $remoteCmd
'@ | Set-Content -Path "$dir\step-3.1.ps1" -Encoding UTF8
```

Then hand the user only the short launcher (quote the path — `$HOME` may contain
spaces):

[TTY]
```powershell
pwsh -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\amarel-vscode\step-3.1.ps1"
```

> **🔒 YOUR TURN:** Amarel's password prompt will appear in the terminal.
> Type your password. **I cannot see what you type.**
````

(Note for the implementer: inside the outer `@'...'@` literal, the inner here-string `$(cat)` and `$KEY` are escaped as `` `$(cat) `` and `` `$KEY `` so they survive being written to the file and are expanded only when the user runs `step-3.1.ps1`. `$remoteCmd` and `$HOME` are intended to expand at run time too, so they are left with a single `$` — verify by reading the generated file back.)

- [ ] **Step 4: Add staged-file cleanup at the end of Phase 3.1.1 in `SKILL.md`**

Find the end of Phase 3.1.1 (the line `**Wait for user confirmation before advancing.**`, ~L424). Insert immediately **before** it:

````
**After the user confirms a successful login, remove the staged wrapper (run yourself):**

[EXEC]
```bash
rm -f ~/.cache/amarel-vscode/step-3.1.sh
```

````

(Windows note to add in the same insert: on Windows, instead remove
`"$env:LOCALAPPDATA\amarel-vscode\step-3.1.ps1"` via
`Remove-Item -Force "$env:LOCALAPPDATA\amarel-vscode\step-3.1.ps1"`.)

- [ ] **Step 5: Add the security reaffirmation bullet in `SKILL.md`**

In the "## Security constraints — non-negotiable" list, find the last bullet:

```
- Write any string the user typed during a password/passphrase prompt to a
  file, to memory, or back into the conversation transcript.
```

Insert a new bullet immediately after it:

```
- Write a typed password/passphrase into a **staged wrapper script**
  (`~/.cache/amarel-vscode/step-*.sh`, `…\amarel-vscode\step-*.ps1`). Those are
  *command* files — they hold only flags, paths, the NetID, the host, and (on
  Windows) the public `.pub` key. The secret is always entered live at the
  prompt, never written to disk.
```

- [ ] **Step 6: Update the Phase 3.1 row in the TTY budget table in `SKILL.md`**

Old string (exact):

```
| 2 | 3.1 | `ssh-copy-id -i … <NetID>@amarel.rutgers.edu` | **⚠ LAST AMAREL PASSWORD EVER** — password on TTY | All |
```

New string:

```
| 2 | 3.1 | `bash ~/.cache/amarel-vscode/step-3.1.sh` (staged ssh-copy-id) | **⚠ LAST AMAREL PASSWORD EVER** — password on TTY | All |
```

- [ ] **Step 7: Mirror all of the above into `AGENTS.md`**

Anchors in `AGENTS.md`: operator note begins `**LLM operator rule — single-line TTY hand-offs.**` (~L67); Phase 3.1 macOS/Linux command at ~L370; Phase 3.1 Windows `$remoteCmd` block at ~L382-395; Security list near ~L1559; TTY budget row at ~L103. Apply the identical new text from Steps 1–6 (framework-neutral wording is already identical here). Read each section first to capture its exact current string, then Edit.

- [ ] **Step 8: Verify both files**

Run:
```bash
cd "$(git rev-parse --show-toplevel)"
for f in SKILL.md AGENTS.md; do
  echo "== $f =="
  grep -c 'cache/amarel-vscode/step-3.1.sh' "$f"          # expect >=2 (stage + run + budget)
  grep -c 'LOCALAPPDATA\\amarel-vscode\\step-3.1.ps1' "$f" # expect >=1
  grep -c 'paste-safe TTY hand-offs (width budget)' "$f"   # expect 1
  grep -c 'staged wrapper script' "$f"                     # expect 1 (security bullet)
done
```
Expected: every count ≥ its target; no zeros.

- [ ] **Step 9: Commit**

```bash
git add SKILL.md AGENTS.md
git commit -m "fix: paste-safe TTY hand-off for Phase 3.1 via staged wrapper script

Long ssh-copy-id command wrapped on paste and corrupted into broken tokens.
Stage it to ~/.cache/amarel-vscode/step-3.1.sh (bash shebang) and hand the
user a short 'bash <path>'. Adds width-budget operator rule, Windows .ps1
variant preserving the -tt pipe, cleanup in 3.1.1, security reaffirmation,
and TTY-budget row update.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Self-guarding `~/.zshrc` append (Phase 4.4)

Make the macOS Sequoia keychain append idempotent in a single atomic command so re-runs can never duplicate it.

**Files:**
- Modify: `SKILL.md` Phase 4.4 (~L685-715)
- Modify: `AGENTS.md` Phase 4.4 (~L685-720)

- [ ] **Step 1: Reproduce the double-append bug, then prove the guard fixes it (dummy harness)**

Run (safe; writes only to a temp file):
```bash
T=$(mktemp); printf 'existing line\n' > "$T"
APPEND() { grep -qF '# Amarel HPC — re-load SSH key from Keychain' "$T" 2>/dev/null || cat >> "$T" <<'EOF'

# Amarel HPC — re-load SSH key from Keychain on each shell (macOS Sequoia fix)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_amarel 2>/dev/null
EOF
}
APPEND; APPEND; APPEND
echo "ssh-add lines after 3 runs: $(grep -c 'ssh-add --apple-use-keychain' "$T") (expect 1)"
rm -f "$T"
```
Expected: `ssh-add lines after 3 runs: 1 (expect 1)`.

- [ ] **Step 2: Replace the Phase 4.4 probe + append in `SKILL.md`**

Old string (exact):

````
**Probe — check if fix already present (run yourself, macOS only):**

[EXEC]
```bash
grep -q 'id_ed25519_amarel' ~/.zshrc 2>/dev/null && echo "PRESENT — skip" || echo "ABSENT — add it"
```

**If ABSENT — run yourself.** This is a pure file append with no prompt — the
same pattern as the Phase 4.3 `~/.ssh/config` append — so the LLM runs it via
Bash. It is **not** a TTY hand-off (the appended `ssh-add` reads the passphrase
silently from the Keychain; nothing prompts now):

[EXEC]
```bash
cat >> ~/.zshrc <<'EOF'

# Amarel HPC — re-load SSH key from Keychain on each shell (macOS Sequoia fix)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_amarel 2>/dev/null
EOF
```
````

New string:

````
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
````

(The `[EXEC]` verify grep that follows — `grep -q 'id_ed25519_amarel' ~/.zshrc && echo "✓ ~/.zshrc updated" …` — stays unchanged.)

- [ ] **Step 3: Mirror into `AGENTS.md`**

Anchor: the probe line `grep -q 'id_ed25519_amarel' ~/.zshrc 2>/dev/null && echo "PRESENT — skip"` (~L695) and the `cat >> ~/.zshrc <<'EOF'` append (~L705). Apply the identical replacement.

- [ ] **Step 4: Verify both files**

```bash
for f in SKILL.md AGENTS.md; do
  echo "== $f =="
  grep -c "grep -qF '# Amarel HPC — re-load SSH key from Keychain' ~/.zshrc" "$f"  # expect 1
  grep -c 'PRESENT — skip' "$f"                                                    # expect 0
done
```
Expected: first count 1, second count 0 in both files.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md AGENTS.md
git commit -m "fix: make Phase 4.4 ~/.zshrc append self-guarding (no double-append)

Collapse probe-then-append into one atomic grep-guarded command keyed on the
comment marker, so re-runs can never duplicate the ssh-add line.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Remove the redundant Phase 3.2

Phase 3.2's pre-load `BatchMode` probe always fails on a fresh run and is pure noise; 3.1.1 (human login) and Phase 5 (end-to-end) cover it.

**Files:**
- Modify: `SKILL.md` (delete Phase 3.2, ~L443-468)
- Modify: `AGENTS.md` (delete Phase 3.2, ~L449-)

- [ ] **Step 1: Delete the entire Phase 3.2 section in `SKILL.md`**

Old string (exact) — delete it completely (keep the `---` that separates Phase 3 from Phase 4):

````
### 3.2 — Verify key auth (run yourself)

[EXEC]
Run this probe yourself, then **always advance to Phase 4**. On a fresh run it
returns `Permission denied (publickey,…)` — that is **expected**, not a failure
(the key isn't in the agent until Phase 4.1; see the note below). Do **not**
re-run Phase 3.1 and do **not** ask for the Amarel password again. The canonical
pass/fail check is Phase 5, after the agent holds the key.

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
`~/.ssh/authorized_keys` on Amarel has a line ending in `amarel-vscode`, with
permissions `600 ~/.ssh/authorized_keys` and `700 ~/.ssh`.

**Wait for confirmation, then advance.**

````

Replace with empty (remove the block). Leave the `---` that begins the Phase 4 section intact.

- [ ] **Step 2: Mirror into `AGENTS.md`**

Anchor: `### 3.2 — Verify key auth (run yourself)` (~L449). Read the section to capture its exact text, then delete the equivalent block.

- [ ] **Step 3: Verify both files**

```bash
for f in SKILL.md AGENTS.md; do
  echo "== $f =="
  grep -c '### 3.2 ' "$f"                  # expect 0
  grep -c 'Verify key auth (run yourself)' "$f"  # expect 0
  grep -c '## Phase 4 ' "$f"               # expect 1 (Phase 4 still present)
done
```
Expected: first two counts 0, last count 1.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md AGENTS.md
git commit -m "fix: remove redundant Phase 3.2 always-failing BatchMode probe

3.2's pre-load probe always returns Permission denied on a fresh run (no agent
key yet) and only emitted 'expected failure' noise. Phase 3.1.1 (human login)
and Phase 5 (end-to-end) are the real gates.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Relocate the `authorized_keys` dedupe to Phase 4.2.1

Move the dedupe from 3.1.5 (before the key is loaded — always failed) to a new 4.2.1 (after 4.2 confirms the key is loaded — runs for real).

**Files:**
- Modify: `SKILL.md` (delete 3.1.5 ~L426-441; insert 4.2.1 after Phase 4.2 ~L561)
- Modify: `AGENTS.md` (delete 3.1.5 ~L432-441; insert 4.2.1 after Phase 4.2)

- [ ] **Step 1: Delete Phase 3.1.5 in `SKILL.md`**

Old string (exact) — delete completely:

````
### 3.1.5 — Dedupe `authorized_keys` (run yourself)

`ssh-copy-id` matches by full line, so a re-run with any whitespace or comment
drift can append a duplicate key — the live-run cleanup found three identical
copies accumulated across sessions. After 3.1, collapse duplicates idempotently:

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

Best-effort only: on a first run with a passphrase-protected key this `BatchMode`
ssh can't authenticate yet (the agent isn't loaded until Phase 4.1), so it may
print `Permission denied (publickey,…)`. That's harmless here — it re-runs and
cleans up duplicates after Phase 4 (same interaction the 3.2 note explains).
Don't treat it as a failure.

````

Replace with empty.

- [ ] **Step 2: Insert Phase 4.2.1 after Phase 4.2 in `SKILL.md`**

Find the end of Phase 4.2 — the Windows verify block that ends:

````
```powershell
ssh-add -l 2>$null | Select-String 'amarel-vscode'
```
````

Insert immediately after it (before `### 4.3`):

````

### 4.2.1 — Dedupe `authorized_keys` on Amarel (run yourself)

Now that the key is loaded in the agent, a `BatchMode` SSH authenticates — so
this dedupe actually runs (it was previously misplaced before the key load and
always failed). `ssh-copy-id` matches by full line, so whitespace/comment drift
across re-runs can append duplicate keys (the live run found three identical
copies). `sort -u` is idempotent:

[EXEC]
```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

If this returns `Permission denied`, the key isn't really loaded — re-run Phase
4.2 verify (and 4.1 if needed) before continuing. Otherwise advance to Phase 4.3.

````

- [ ] **Step 3: Mirror into `AGENTS.md`**

Anchors: delete the `### 3.1.5 — Dedupe \`authorized_keys\`` section (~L432); insert the same 4.2.1 block after the AGENTS.md Phase 4.2 Windows verify (`ssh-add -l 2>$null | Select-String 'amarel-vscode'`).

- [ ] **Step 4: Verify both files**

```bash
for f in SKILL.md AGENTS.md; do
  echo "== $f =="
  grep -c '### 3.1.5' "$f"                         # expect 0
  grep -c '### 4.2.1' "$f"                          # expect 1
  grep -c 'sort -u ~/.ssh/authorized_keys' "$f"     # expect 1 (only in 4.2.1)
done
```
Expected: 0, 1, 1 in both files.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md AGENTS.md
git commit -m "fix: relocate authorized_keys dedupe from 3.1.5 to 4.2.1 (after key load)

The BatchMode dedupe needs the agent key loaded (Phase 4.1) to authenticate.
Placed at 3.1.5 it always failed silently; moved to 4.2.1 it runs for real.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Silence the Phase 1.0 skip-probe stderr

The Gate-1 probe prints `Host key verification failed` / `Permission denied` before the routing token, which looks alarming. Only the exit code matters.

**Files:**
- Modify: `SKILL.md` Phase 1.0 Gate-1 (~L172-176)
- Modify: `AGENTS.md` Phase 1.0 Gate-1 (~L178-181)

- [ ] **Step 1: Redirect stderr in the `SKILL.md` Gate-1 probe**

Old string (exact):

```
# Gate 1: key auth
ssh -o BatchMode=yes -o ConnectTimeout=5 \
    -i ~/.ssh/id_ed25519_amarel \
    <NetID>@amarel.rutgers.edu true 2>&1
KEY_OK=$?
```

New string:

```
# Gate 1: key auth (stderr silenced — only the exit code routes SKIP/PROCEED;
# a pre-setup "Permission denied"/"Host key verification failed" here is normal)
ssh -o BatchMode=yes -o ConnectTimeout=5 \
    -i ~/.ssh/id_ed25519_amarel \
    <NetID>@amarel.rutgers.edu true 2>/dev/null
KEY_OK=$?
```

- [ ] **Step 2: Mirror into `AGENTS.md`**

Anchor: `<NetID>@amarel.rutgers.edu true 2>&1` (~L181). Apply the same change (`2>&1` → `2>/dev/null`, plus the comment). The Windows variant at ~L204 already merges to `Out-Null` (`true 2>&1 | Out-Null`) and is already silent — leave it unchanged.

- [ ] **Step 3: Verify both files**

```bash
for f in SKILL.md AGENTS.md; do
  echo "== $f =="
  grep -c 'amarel.rutgers.edu true 2>/dev/null' "$f"  # expect 1 (Gate 1 now silenced)
  grep -c 'amarel.rutgers.edu true 2>&1$' "$f"          # expect 0 (no bare 2>&1 to terminal)
done
```
Expected: 1 and 0 in both files.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md AGENTS.md
git commit -m "fix: silence Phase 1.0 Gate-1 stderr (drop alarming pre-setup errors)

Only the exit code routes SKIP/PROCEED; redirect the probe's stderr to
/dev/null so a normal pre-setup 'Permission denied' no longer prints.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Reword the execution-contract pre-load-denial paragraph

With Phase 3.2 gone and the dedupe at 4.2.1, the only remaining pre-load `BatchMode` denials come from the skip probes (1.0, 3.0). Update the contract wording. **Do this task after Tasks 3 and 4.**

**Files:**
- Modify: `SKILL.md` execution contract item 2 (~L15)
- Modify: `AGENTS.md` execution contract item 2 (~L35)

- [ ] **Step 1: Replace the relevant sentences in `SKILL.md` (execution contract, item 2)**

Old string (exact):

```
> 2. All `[EXEC]` steps are noninteractive: SSH/SCP calls use `-o BatchMode=yes`; no interactive prompts are expected. **Key-auth denial scope (Phases 1–5):** before the key is loaded into the agent (Phase 4.1), a `BatchMode` probe to Amarel returns `Permission denied (publickey,…)` *by construction* — this is an **expected routing signal to proceed with setup, never a failure**. Treat an auth failure as a hard failure to escalate only (a) on any `[EXEC]` step in Phases 6–10, or (b) in Phases 1–5 if the denial persists **after** Phase 4.2 confirms the key is loaded. Never re-run a `[TTY]` password/passphrase step (e.g. Phase 3.1 `ssh-copy-id`) in response to an expected pre-load denial. Any *non-auth* error (network, missing tool, unexpected output) is always surfaced.
```

New string:

```
> 2. All `[EXEC]` steps are noninteractive: SSH/SCP calls use `-o BatchMode=yes`; no interactive prompts are expected. **Key-auth denial scope (Phases 1–5):** before the key is loaded into the agent (Phase 4.1), the **skip probes** (Phase 1.0 Gate-1 and Phase 3.0) return `Permission denied (publickey,…)` *by construction* — this is an **expected routing signal**, not a failure (Phase 1.0 silences this probe's stderr; only its exit code routes SKIP/PROCEED). Treat an auth failure as a hard failure to escalate only (a) on any `[EXEC]` step in Phases 6–10, or (b) in Phases 1–5 if a denial persists **after** Phase 4.2 confirms the key is loaded (e.g. the Phase 4.2.1 dedupe should succeed once the key is loaded). Never re-run a `[TTY]` password/passphrase step (e.g. Phase 3.1) in response to an expected pre-load denial. Any *non-auth* error (network, missing tool, unexpected output) is always surfaced.
```

- [ ] **Step 2: Mirror into `AGENTS.md`**

Anchor: the execution-contract item beginning `> 2. All \`[EXEC]\` steps are noninteractive` (~L35). Apply the identical new text.

- [ ] **Step 3: Verify both files**

```bash
for f in SKILL.md AGENTS.md; do
  echo "== $f =="
  grep -c 'skip probes\*\* (Phase 1.0 Gate-1 and Phase 3.0)' "$f"  # expect 1
  grep -c 'Phase 4.2.1 dedupe' "$f"                                 # expect 1
done
```
Expected: 1 and 1 in both files.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md AGENTS.md
git commit -m "docs: reword execution-contract pre-load denial note (3.2 gone, dedupe at 4.2.1)

Point the 'expected pre-load denial' guidance at the skip probes (1.0/3.0)
now that Phase 3.2 is removed and the dedupe runs post-load at 4.2.1.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Add the "Fresh start" reset section (Local + Amarel)

A copy-paste block that clears prior partial state. Leaves the user's pre-existing `Host rutgers.edu` block untouched.

**Files:**
- Modify: `SKILL.md` (insert a new `## Fresh start` section just before `## Power-user path`, ~L1575)
- Modify: `AGENTS.md` (insert before its `## Power-user path`, ~L1581)

- [ ] **Step 1: Validate the config-block remover on a dirtied copy (dummy harness)**

Run (operates only on a temp file that mimics the user's real config):
```bash
T=$(mktemp)
cat > "$T" <<'EOF'
Host rutgers.edu
  HostName rutgers.edu
  User sj1136


Host amarel.rutgers.edu
    User sj1136
    IdentityFile ~/.ssh/id_ed25519_amarel
    IdentitiesOnly yes
    AddKeysToAgent yes
EOF
awk '
  /^Host[ \t]+amarel\.rutgers\.edu[ \t]*$/ { skip=1; next }
  skip==1 {
    if ($0 ~ /^Host[ \t]/) { skip=0 }
    else if ($0 ~ /^[ \t]/ || $0 ~ /^[ \t]*$/) { next }
    else { skip=0 }
  }
  { print }
' "$T" > "$T.new" && mv "$T.new" "$T"
echo "--- result (amarel block gone, rutgers.edu kept) ---"; cat "$T"
echo "amarel blocks remaining: $(grep -c '^Host amarel\.rutgers\.edu' "$T") (expect 0)"
echo "rutgers.edu blocks remaining: $(grep -c '^Host rutgers\.edu' "$T") (expect 1)"
rm -f "$T"
```
Expected: amarel block removed, `Host rutgers.edu` preserved; counts 0 and 1.

- [ ] **Step 2: Insert the `## Fresh start` section in `SKILL.md`**

Find `## Power-user path (one-shot script)` (~L1575). Insert immediately **before** it:

````
## Fresh start (reset before a clean run)

If a prior partial run left duplicate or stale state, hand the user this block
to wipe **only** what this skill creates, then re-run from Phase 0. It does
**not** touch any other SSH host (e.g. a personal `Host rutgers.edu`) and never
reads or deletes private keys. Substitute the real NetID for `<NetID>`.

Because the reset logic is long, stage it to `~/.cache/amarel-vscode/reset.sh`
via `[EXEC]` first (same width-budget rule as Phase 3.1), with `<NetID>`
substituted:

[EXEC]
```bash
mkdir -p ~/.cache/amarel-vscode
cat > ~/.cache/amarel-vscode/reset.sh <<'EOF'
#!/usr/bin/env bash
set -u
# 1) Remove the Amarel ssh-add block from ~/.zshrc (marker + the line after it)
[ -f ~/.zshrc ] && sed -i.bak '/# Amarel HPC — re-load SSH key from Keychain/,+1d' ~/.zshrc && echo "✓ ~/.zshrc cleaned"
# 2) Remove ONLY the skill-authored Host amarel.rutgers.edu block from ~/.ssh/config
if [ -f ~/.ssh/config ]; then
  cp ~/.ssh/config ~/.ssh/config.bak
  awk '
    /^Host[ \t]+amarel\.rutgers\.edu[ \t]*$/ { skip=1; next }
    skip==1 {
      if ($0 ~ /^Host[ \t]/) { skip=0 }
      else if ($0 ~ /^[ \t]/ || $0 ~ /^[ \t]*$/) { next }
      else { skip=0 }
    }
    { print }
  ' ~/.ssh/config.bak > ~/.ssh/config && chmod 600 ~/.ssh/config && echo "✓ ~/.ssh/config: amarel block removed (others kept)"
fi
# 3) Remove all amarel.rutgers.edu lines (any algorithm) from known_hosts
[ -f ~/.ssh/known_hosts ] && sed -i.bak '/^amarel\.rutgers\.edu /d' ~/.ssh/known_hosts && echo "✓ known_hosts: amarel entries removed"
# 4) Dedupe authorized_keys on Amarel (best-effort; skipped if key auth not set up)
if ssh -o BatchMode=yes -o ConnectTimeout=5 <NetID>@amarel.rutgers.edu 'sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys' 2>/dev/null; then
  echo "✓ Amarel authorized_keys deduped"
else
  echo "• Skipped Amarel dedupe (key auth not set up yet — that's fine)"
fi
echo "Reset complete. Re-run the skill from Phase 0."
EOF
```

Then hand the user the short launcher:

> **🔒 YOUR TURN — macOS / Linux:**
>
> [TTY]
> ```bash
> bash ~/.cache/amarel-vscode/reset.sh
> ```

**Windows PowerShell:** stage an equivalent `reset.ps1` to
`$env:LOCALAPPDATA\amarel-vscode\reset.ps1` (skip the macOS-only `~/.zshrc`
step; remove the `Host amarel.rutgers.edu` block from `$HOME\.ssh\config`
leaving other hosts; drop `amarel.rutgers.edu` lines from
`$HOME\.ssh\known_hosts`; best-effort dedupe `authorized_keys` on Amarel), then
hand the user:

> **🔒 YOUR TURN — Windows:**
>
> [TTY]
> ```powershell
> pwsh -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\amarel-vscode\reset.ps1"
> ```

After the reset, start again at Phase 0.

````

- [ ] **Step 3: Mirror into `AGENTS.md`**

Insert the same `## Fresh start (reset before a clean run)` section before `## Power-user path` in `AGENTS.md`, matching the surrounding AGENTS.md voice (imperative rather than first-person if that is the local style).

- [ ] **Step 4: Verify both files**

```bash
for f in SKILL.md AGENTS.md; do
  echo "== $f =="
  grep -c '## Fresh start' "$f"                       # expect 1
  grep -c 'cache/amarel-vscode/reset.sh' "$f"          # expect >=1
  grep -c 'amarel block removed (others kept)' "$f"    # expect 1
done
```
Expected: 1, ≥1, 1 in both files.

- [ ] **Step 5: Commit**

```bash
git add SKILL.md AGENTS.md
git commit -m "feat: add 'Fresh start' reset section (local + Amarel, leaves other hosts)

Generatable reset block: strips the skill-authored ~/.zshrc line, the
Host amarel.rutgers.edu config block, amarel known_hosts entries, and dedupes
authorized_keys on Amarel. Never touches other SSH hosts or private keys.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Add the TTY heads-up note

List the four upcoming terminal moments up front; keep the verified one-at-a-time flow unchanged.

**Files:**
- Modify: `SKILL.md` (insert after the `### TTY budget` block, before `## Phase 0`, ~L109)
- Modify: `AGENTS.md` (insert after its `### TTY budget` block)

- [ ] **Step 1: Insert the heads-up note in `SKILL.md`**

Find the end of the `### TTY budget` section — the `**Linux keychain note:**` paragraph (~L105-108). Insert immediately **after** that paragraph (before the `---` that precedes `## Phase 0`):

````

### Heads-up: your 4 terminal moments

Tell the user up front (I run everything else myself via Bash). You will switch
to your terminal exactly **four** times, in this order:

1. **Phase 1.2** — `ssh-keygen`: set a key passphrase (typed twice).
2. **Phase 3.1** — install your key: your **last Amarel password ever**.
3. **Phase 3.1.1** — test login: your key passphrase.
4. **Phase 4.1** — `ssh-add`: your key passphrase, saved to the keychain.

I hand you each command when it's time and verify the result before advancing —
so we keep them one at a time rather than all at once. Nothing else needs your
terminal.

````

- [ ] **Step 2: Mirror into `AGENTS.md`**

Anchor: the `### TTY budget` section and its trailing `**Linux keychain note:**` paragraph. Insert the same heads-up block after it.

- [ ] **Step 3: Verify both files**

```bash
for f in SKILL.md AGENTS.md; do
  echo "== $f =="
  grep -c 'Heads-up: your 4 terminal moments' "$f"   # expect 1
done
```
Expected: 1 in both files.

- [ ] **Step 4: Commit**

```bash
git add SKILL.md AGENTS.md
git commit -m "docs: add up-front heads-up of the 4 TTY moments

List Phases 1.2/3.1/3.1.1/4.1 so the user knows the terminal touch-points in
advance, while keeping the verified one-at-a-time flow.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Parity sweep, README scan, and final verification

**Files:**
- Read: `SKILL.md`, `AGENTS.md`, `README.md`
- Modify: `README.md` only if it references the removed/moved phases

- [ ] **Step 1: SKILL↔AGENTS parity assertions**

```bash
cd "$(git rev-parse --show-toplevel)"
fail=0
check() { # pattern expected_count
  local pat="$1" want="$2"
  for f in SKILL.md AGENTS.md; do
    got=$(grep -c "$pat" "$f")
    [ "$got" = "$want" ] || { echo "MISMATCH $f: '$pat' = $got (want $want)"; fail=1; }
  done
}
check '### 3.2 ' 0
check '### 3.1.5' 0
check '### 4.2.1' 1
check 'paste-safe TTY hand-offs (width budget)' 1
check '## Fresh start' 1
check 'Heads-up: your 4 terminal moments' 1
[ "$fail" = 0 ] && echo "PARITY OK" || echo "PARITY FAILURES ABOVE"
```
Expected: `PARITY OK`.

- [ ] **Step 2: Scan `README.md` for stale phase references**

```bash
grep -nE '3\.1\.5|Phase 3\.2|3\.2 ' README.md || echo "no stale refs in README"
```
If matches appear (e.g. a troubleshooting row pointing at Phase 3.2), edit them to reference the surviving gate (Phase 3.1.1 / Phase 5) or Phase 4.2.1 as appropriate. If none, no change.

- [ ] **Step 3: Re-run the paste-safety arg-integrity harness end-to-end**

```bash
# Arg-integrity of the staged 3.1 wrapper (fake ssh-copy-id; no network)
T=$(mktemp -d); printf '#!/usr/bin/env bash\necho ARGC=$#\n' > "$T/ssh-copy-id"; chmod +x "$T/ssh-copy-id"
PATH="$T:$PATH"
printf '#!/usr/bin/env bash\nssh-copy-id -i ~/.ssh/k.pub -o PreferredAuthentications=password -o PubkeyAuthentication=no user@amarel.rutgers.edu\n' > "$T/step-3.1.sh"
n=$(bash "$T/step-3.1.sh" | sed -n 's/^ARGC=//p')
echo "staged wrapper arg count = $n (expect 7)"
rm -rf "$T"
```
Expected: `staged wrapper arg count = 7 (expect 7)`.

- [ ] **Step 4: Commit any README change (skip if none)**

```bash
git add README.md
git commit -m "docs: update README phase references after 3.2 removal / 4.2.1 move

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 5: Final review gate (manual)**

Confirm: no `### 3.2`/`### 3.1.5` anywhere; `### 4.2.1` present once per file; Phase 3.1 hands off `bash ~/.cache/...`; `~/.zshrc` append is a single guarded command; Phase 1.0 Gate-1 uses `2>/dev/null`; `## Fresh start` and the heads-up note present in both files. The canonical acceptance test remains a **full live re-run on Amarel** (VPN + real account) per `CLAUDE.md` — the Windows `pwsh` wrapper path is exercised there.

---

## Self-review against the spec

- **Spec change 1 (self-guarding appends):** Task 2 (`~/.zshrc`); the `authorized_keys` side is `sort -u` (inherently idempotent) in Task 4. ✓
- **Spec change 2 (remove 3.2):** Task 3. ✓
- **Spec change 3 (relocate dedupe → 4.2.1):** Task 4. ✓
- **Spec change 4 (silence Phase 1.0):** Task 5. ✓
- **Spec change 5 (fresh-start reset, local+Amarel, keep rutgers.edu):** Task 7 (awk validated to preserve `Host rutgers.edu`). ✓
- **Spec change 6 (TTY heads-up):** Task 8. ✓
- **Spec change 7 (paste-safe wrappers, priority):** Task 1 (operator note, 3.1 macOS+Windows, cleanup, security bullet, budget row). ✓
- **Cross-file sync:** every task has a mirror step; Task 9 asserts parity. Execution-contract reword = Task 6. README scan = Task 9. ✓
- **Placeholder scan:** all code/edit steps contain complete old/new strings or full snippets. ✓
- **Naming consistency:** `~/.cache/amarel-vscode/step-3.1.sh`, `reset.sh`, and the `# Amarel HPC — re-load SSH key from Keychain` marker are used identically across tasks. ✓
