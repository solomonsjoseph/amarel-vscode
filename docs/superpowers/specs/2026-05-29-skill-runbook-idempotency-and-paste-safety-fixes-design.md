# Design Spec — Runbook Idempotency & Paste-Safety Fixes

- **Date:** 2026-05-29
- **Status:** Draft (awaiting user review)
- **Scope:** `SKILL.md` and `AGENTS.md` (kept in sync), with knock-on checks to
  `README.md` and `GEMINI.md` / `docs/using-other-llms.md` if they reference the
  affected phase numbers.
- **Origin:** Friction observed during a real macOS (zsh) live run. The user's
  direct observations are treated as authoritative over the agent's
  self-reported notes, because the user can see terminal/paste behavior the
  agent cannot.

## Problem statement

A live setup run surfaced seven defects/friction points. The highest-impact one
(issue 7) is a **command paste-corruption bug** the agent originally
misdiagnosed: long single-line TTY commands wrap in the rendered terminal and
corrupt on copy, breaking the user's paste. The remaining six are idempotency
bugs (duplicate appends), always-failing phases placed before the SSH agent is
loaded, alarming-but-harmless error output, a missing "start clean" path, and
unnecessary context-switching.

## Ground-truth findings (verified on the user's machine, read-only)

These correct two assumptions and anchor the fixes:

1. **`~/.ssh/config` contains two host blocks:** a pre-existing `Host
   rutgers.edu` block (user-authored — the skill only ever writes `Host
   amarel.rutgers.edu`) **and** the skill's `Host amarel.rutgers.edu` block. The
   stray `rutgers.edu` is **not skill-created** and is functionally harmless
   (`amarel.rutgers.edu` never matches `rutgers.edu`). The reset path will
   **leave it untouched** (we do not delete config the skill did not author).
2. **`~/.ssh/known_hosts` has two `amarel.rutgers.edu` lines, but they are
   different key algorithms** (`ed25519` + `ecdsa`). This is **normal**, not a
   duplicate — one entry per algorithm. No fix needed; do not "dedupe" it. (The
   `ecdsa` line is auto-added by the interactive login in Phase 3.1.1; Phase 2
   only pins `ed25519`.)
3. **`~/.zshrc` double-append is real.** The Phase 4.4 append used a
   *separate-command* probe followed by a *separate-command* append; a phase
   re-run (or an un-threaded probe result) appended the block twice. Same
   root-cause class produced the triple `authorized_keys` entry on Amarel.

## Paste-corruption root cause (issue 7, validated)

The Phase 3.1 `ssh-copy-id` command is a single line in source **already**
(the existing operator note at `SKILL.md` ~L61–65 is satisfied), but it is
~133–158 characters depending on NetID/path length. Claude Code renders fenced
code blocks with a left indent gutter; the terminal soft-wraps the long line;
the copied render carries injected newlines **plus** the 2-space gutter, e.g.:

```
ssh-copy-id -i ~/.ssh/id_ed25519_amarel.pub -o
  PreferredAuthentications=password -o
  PubkeyAuthentication=no <NetID>@amarel.rutgers.edu
```

zsh then parses three broken fragments. **The problem is line length vs terminal
width, not source formatting** — so "make it one line" cannot fix it.

A dummy-data harness reproduced the bug and validated the fix on macOS/bash:

| Test | Result |
|---|---|
| Wrapped paste run as-is | `ssh-copy-id` received **3 of 7** args; remainder `command not found` (bug reproduced) |
| Staged `bash ~/.cache/amarel-vscode/step-3.1.sh` (39 chars) | **7/7 args intact**, `~` expanded |
| Re-stage twice | Stays **1 line** (overwrite, not append) |
| Interactive prompt reachability | Prompt surfaces; no secret stored |

**Rejected alternative:** shortening the command by dropping `-o
PreferredAuthentications=password -o PubkeyAuthentication=no`. Those flags force
the deterministic password path. Without them, ssh offers local keys first —
including the passphrase-protected `id_ed25519_amarel` Amarel does not yet
trust — producing a **passphrase** prompt instead of the expected **password**
prompt, then `Permission denied`. The flags are load-bearing.

## The seven changes

### 1. Self-guarding appends (kills double-append)

**Where:** Phase 4.4 (`~/.zshrc`), and the relocated `authorized_keys` dedupe
(see change 3).

**Change:** Replace "probe-then-append (two commands)" with a single atomic,
self-guarding command keyed on a stable marker so any number of re-runs yields
exactly one copy:

```bash
grep -qF '# Amarel HPC — re-load SSH key from Keychain' ~/.zshrc 2>/dev/null || cat >> ~/.zshrc <<'EOF'

# Amarel HPC — re-load SSH key from Keychain on each shell (macOS Sequoia fix)
ssh-add --apple-use-keychain ~/.ssh/id_ed25519_amarel 2>/dev/null
EOF
```

The standalone 4.4 probe step is folded into this guard (a `[VERIFY]` grep still
runs afterward to confirm the line is present). The marker text must match the
comment line exactly (use `grep -qF`, fixed-string, to avoid em-dash/regex
surprises).

### 2. Remove Phase 3.2 entirely

**Why:** 3.2's non-interactive `BatchMode` key-auth probe **always** fails on a
fresh run (the passphrase key is not in the agent until 4.1), so the runbook
papered over it with an "expected failure" note — pure noise. The human-verified
interactive login in **3.1.1** already proves the key works, and **Phase 5** is
the canonical end-to-end gate.

**Change:** Delete Phase 3.2 (probe + both expected-failure notes). Do **not**
renumber other phases (the 0–10 numbering is load-bearing per `CLAUDE.md`); 3.2
simply disappears.

### 3. Relocate the `authorized_keys` dedupe to after the key is loaded

**Why:** Phase 3.1.5 ran a `BatchMode` `sort -u` over remote `authorized_keys`
*before* Phase 4.1 loaded the key, so it also always failed on a fresh run.

**Change:** Move it to a new step **4.2.1** (immediately after 4.2 confirms the
key is in the agent), where `BatchMode` SSH authenticates and the dedupe
actually runs:

```bash
ssh -o BatchMode=yes <NetID>@amarel.rutgers.edu 'sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
```

`sort -u` is inherently idempotent. Remove the old 3.1.5 block and its
"expected-failure / best-effort" caveat (no longer needed — it now runs for
real). Using `4.2.1` keeps the 0–10 numbering intact.

### 4. Silence the Phase 1.0 skip-probe noise

**Why:** Phase 1.0 Gate-1's `ssh ... 2>&1` prints `Host key verification
failed` / `Permission denied` before the routing token, which looks alarming.
Only the exit code matters for `SKIP` vs `PROCEED`.

**Change:** Redirect that probe's stderr to `/dev/null` (drop the `2>&1`), so
only the clean `SKIP` / `PROCEED` line shows. (Windows variant already pipes to
`Out-Null`; verify it discards stderr too.) Phase 3.0's analogous re-probe
already uses `2>/dev/null` — confirm consistency.

### 5. New "fresh start" reset prompt (Local + Amarel)

**Why:** The user asked for a generatable block that clears prior partial state
so a re-run starts truly clean.

**Scope (user-selected): Local + Amarel.** It:

- removes the Amarel `ssh-add` block from `~/.zshrc` (marker-matched);
- removes the `Host amarel.rutgers.edu` block from `~/.ssh/config` (the
  skill-authored block only);
- removes **both** `amarel.rutgers.edu` lines (all algorithms) from
  `~/.ssh/known_hosts` so Phase 2 re-pins cleanly;
- dedupes `authorized_keys` on Amarel via one `BatchMode` SSH call (best-effort:
  if key auth isn't set up yet, it is skipped with a clear message).

**Explicitly out of scope:** the user's pre-existing `Host rutgers.edu` block is
**left untouched**. The reset never reads or deletes private keys.

**Placement:** a clearly labeled, copy-paste section near the Power-user /
recovery area at the end of each runbook, with macOS/Linux and Windows variants.
The local file edits should themselves be idempotent (safe to run when nothing
is present). Destructive lines (removing blocks) are presented for the user to
run; the agent does not silently wipe user files.

### 6. TTY heads-up (keep the verified one-at-a-time flow)

**Why:** The user context-switches to the terminal four times (Phases 1.2, 3.1,
3.1.1, 4.1). Full batching would lose the per-step `[EXEC]` checks that catch a
failed key-copy early.

**Change (user-selected: heads-up only):** Add a short note before Phase 1
listing the four upcoming TTY moments so the user knows what's coming, while
keeping the existing verified, sequential flow unchanged. No reordering of
phases.

### 7. Paste-safe TTY hand-offs via staged wrapper scripts (priority)

**Rule:** Any TTY command longer than ~70 characters MUST be staged into a short
wrapper script the user runs via a brief launcher; commands ≤70 chars stay
inline as a single-line fenced block. Today only **Phase 3.1** triggers staging;
Phases 1.2 (~65), 3.1.1 (~57), and 4.1 (~53) stay inline.

**Mechanism (macOS/Linux):**

- Agent `[EXEC]` writes the full one-line command to
  `~/.cache/amarel-vscode/step-3.1.sh` with a `#!/usr/bin/env bash` shebang
  (runs under bash regardless of the user's login shell — avoids zsh reserved-var
  / glob quirks; e.g. `ARGC` is read-only in zsh).
- Hand-off (the only thing the user pastes — cannot wrap):
  ```
  bash ~/.cache/amarel-vscode/step-3.1.sh
  ```
- The interactive password/passphrase prompt surfaces on the user's TTY exactly
  as if the command were run directly.
- Cleanup: fold `rm -f` of the staged script into the existing post-step
  `[EXEC]` verify. Re-staging overwrites (idempotent); always write immediately
  before the hand-off (never reuse a path blindly, to avoid stale content from a
  prior skill version).

**Mechanism (Windows):**

- Stage to `$env:LOCALAPPDATA\amarel-vscode\step-3.1.ps1`; launch with
  `pwsh -ExecutionPolicy Bypass -File "<path>"` (quote the path — `$HOME` may
  contain spaces; do not rely on `~` expansion in PowerShell).
- The Windows 3.1 form must **faithfully reproduce** the existing
  pipe-`pubkey`-into-`ssh -tt` structure (the `-tt` PTY allocation is what makes
  the password prompt appear). Do not flatten it.

**Operator-note upgrade:** Replace the existing single-line guidance (~L61–65)
with the width-budget rule above. Launcher selection branches on the recorded
`LOCAL_OS`. Use interpreter-launch (`bash <file>` / `pwsh -File <file>`), never
`./file` (no executable-bit dependency).

**Security:** A staged wrapper contains only non-secret tokens (flags, paths,
NetID, host) and, on Windows, the public key (`.pub`, explicitly allowed). The
typed password/passphrase is **never** written to any file. Add a one-line
reaffirmation under the Security constraints section that staged files are
*command* files and must never capture a typed secret.

## Cross-file sync & knock-on edits

- **`AGENTS.md`** receives the identical logical changes (framework-neutral
  wording). `GEMINI.md` is a thin pointer — update only if it names phases.
- **Execution-contract paragraph** (`SKILL.md` ~L14–15; AGENTS.md mirror):
  reword the "expected pre-load `BatchMode` denial" guidance. With 3.2 removed
  and the dedupe moved to 4.2.1, the only remaining pre-load `BatchMode` calls
  are the **skip probes** (Phase 1.0, Phase 3.0); point the note at those and
  drop the 3.1.5/3.2 references.
- **TTY budget table** (`SKILL.md` ~L91–103): unchanged in count (still 5), but
  the Phase 3.1 row's "Command / Action" should reflect the `bash <path>`
  hand-off.
- **`README.md` troubleshooting table:** scan for references to Phase 3.2 /
  3.1.5 and update.

## Testing / verification plan

- **Idempotency:** re-run Phase 4.4 and 4.2.1 logic repeatedly → exactly one
  `~/.zshrc` line, deduped `authorized_keys` (validated for the append pattern
  via the dummy harness).
- **Paste-safety:** the dummy-data harness already proved arg integrity (7/7)
  and bug reproduction on macOS/bash. **Windows `pwsh` variant to be exercised on
  a Windows box during the live pass.**
- **Phase removal:** confirm a fresh run no longer emits the 3.2 "expected
  failure" noise and that 4.2.1 dedupe authenticates and succeeds.
- **Reset prompt:** run on a dirtied environment → local artifacts gone, stray
  `Host rutgers.edu` preserved, Amarel `authorized_keys` deduped.
- **Full live re-run** on Amarel (VPN + real account) remains the canonical
  acceptance test, per `CLAUDE.md`.

## Out of scope

- Renumbering the 0–10 phase scheme.
- Touching the user's pre-existing `Host rutgers.edu` block.
- "Deduping" the (legitimate) two-algorithm `known_hosts` entries.
- Changing `scripts/setup.sh` / `setup.ps1` (the no-LLM installer); this spec is
  about the LLM-driven runbooks. (A follow-up may port the self-guarding append
  and dedupe relocation into the scripts for parity.)
