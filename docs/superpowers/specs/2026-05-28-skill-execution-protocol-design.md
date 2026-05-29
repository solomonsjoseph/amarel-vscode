# Skill Execution Protocol — Design Spec
**Date:** 2026-05-28  
**Status:** Approved for implementation (v2 — defects fixed)  
**Scope:** SKILL.md, AGENTS.md (kept in sync)

---

## Problem

The `amarel-vscode-setup` skill has failed inconsistently across multiple runs despite correct content. The root cause is structural, not factual:

1. **Documentation language, not execution language.** The skill uses passive advice ("run yourself via Bash") which LLMs sometimes execute and sometimes narrate as chat text.

2. **Global contracts drift.** Any execution rule at the top of a 1400-line document loses influence by Phase 6. LLMs re-evaluate their role locally, not globally.

3. **No prior Bash-execution baseline.** The original manual run was purely interactive — the user ran every command, the LLM only gave instructions. This redesign introduces LLM-Bash execution mode from scratch.

4. **No pass/fail gates.** VERIFY steps tell the LLM what to run but not what output = success, what = warning, or when to escalate. Without this, the LLM cannot decide whether to advance or halt.

5. **No state continuity contract.** Phases share required state (LOCAL_OS, NetID, REPO_ROOT, USE_TARBALL). Without an explicit rule to persist these from first discovery, each phase can re-derive inconsistent values.

---

## Background: Manual Run vs. Skill Phases

The original manual run (the only successful run) covered **Phases 6–10 only**:
find tarball → scp to Amarel → extract sysroot → edit `.bashrc` → connect in VS Code.

In that run, the user entered their Amarel password multiple times (once per `scp`, once per `ssh` command). There was no SSH key setup and no `extensions.verifySignature` configuration.

**Phases 0–5 and Phase 9 are deliberate upgrade additions:**

- **Phases 1–5** convert from password-per-command auth to single-password auth. If these fail, every subsequent SSH/SCP command prompts for a password. These phases have **no manual fallback** — the LLM must diagnose and fix, not hand off.
- **Phase 9** (`extensions.verifySignature: false`) was absent from the manual run but is required for VS Code Server 1.99+ to function on CentOS 7 with the custom glibc node binary. It is mandatory on every run.

---

## Mission (non-negotiable, user-confirmed)

1. **One password entry.** The Amarel account password is entered exactly once — Phase 3.1 (`ssh-copy-id`) only. Phases 1–5 make this possible by establishing key auth for all subsequent SSH/SCP calls.

2. **LLM runs all non-TTY commands.** Every command that does not require a human-visible TTY is executed by the LLM via its Bash tool immediately, before responding. The user touches nothing except the hand-offs listed in Change 3.

3. **Phase 9 is mandatory.** The `extensions.verifySignature: false` setting is applied on every run — not optional, not probe-skippable.

---

## Design: Four Concrete Changes

### Change 1 — Three-rule execution contract at the top of the skill body

Placed immediately after the YAML frontmatter, before any phase content:

> **Execution contract:**
> 1. This skill executes `[EXEC]` steps autonomously via its Bash tool; it never asks the user to run them.
> 2. All `[EXEC]` steps are noninteractive: SSH/SCP calls use `-o BatchMode=yes`; no interactive prompts are expected. If a credential prompt appears during an `[EXEC]` step, treat it as a failure and escalate to the user — do not wait.
> 3. Key state discovered during execution (`LOCAL_OS`, `NetID`, `REPO_ROOT`, `USE_TARBALL`) is recorded at the phase that first establishes it and reused in all subsequent phases without re-deriving.

### Change 2 — Inline action tags + structured VERIFY gates

Every code block gets an action tag on the line immediately above it. Tags are adjacent to the command — not in a global header.

**Action tags:**

| Tag | Meaning | Who acts |
|---|---|---|
| `[EXEC]` | Run via Bash tool right now, report result, advance | LLM |
| `[TTY]` | Show to user, wait for confirmation | User |
| `[VERIFY]` | Run via Bash; evaluate against structured gate | LLM |
| `[MANDATORY][EXEC]` | Run via Bash; skip probe disabled for this block | LLM |

**Structured VERIFY gate format** — used for any VERIFY step with a branching outcome:

```
[VERIFY]
Command:  <command to run>
Pass:     <exact string or regex the output must contain>
Warn:     <output that is acceptable but worth noting>  (omit if none)
Fail:     <output that means something is wrong>
On fail:  <specific fix to apply, or "escalate to user">
Advance:  Phase N.N
```

Trivial checks (file exists, exit code 0) may use a one-line inline note instead of the full format.

### Change 3 — TTY hand-offs: 5 on Linux/Windows, 6 on macOS

The complete human touch-point list. Everything not on this list is `[EXEC]`:

| # | Phase | Command / Action | Why human | OS |
|---|---|---|---|---|
| 1 | 1.2 | `ssh-keygen -t ed25519 …` | Passphrase prompt on TTY — LLM cannot see | All |
| 2 | 3.1 | `ssh-copy-id -i … netid@amarel.rutgers.edu` | **⚠ LAST AMAREL PASSWORD EVER** — password on TTY | All |
| 3 | 3.1.1 | `ssh -i ~/.ssh/id_ed25519_amarel netid@amarel` | Key passphrase on TTY; confirms key installed | All |
| 4 | 4.1 | `ssh-add --apple-use-keychain …` / `ssh-add …` | Passphrase to agent on TTY | All |
| 5 | 4.4 | `tee -a ~/.zshrc <<'EOF' …` | macOS Sequoia fix — single-line paste | **macOS only** |
| 6 | 10 | VS Code GUI — click Allow, watch status bar | No Bash equivalent | All |

**TTY budget:** macOS = 6 · Linux = 5 · Windows = 5

All other steps (preflight probes, known_hosts, BatchMode ssh, scp, tarball download + checksum, remote extract, `.bashrc` append, Phase 9 merge, all verification gates) are `[EXEC]`.

### Change 4 — Phase 9 marked `[MANDATORY]`

Phase 9's apply block gets `[MANDATORY][EXEC]` and a one-line note:

> Skip probe disabled — run on every execution. The verifySignature fix is required for VS Code Server 1.99+ on CentOS 7 regardless of prior state.

Phase 9's `STATE=SET` path no longer exits early — it still checks state, then always applies the idempotent merge and verifies.

---

## What Does NOT Change

- Phase numbering 0–10 (load-bearing across README, SKILL.md, AGENTS.md, troubleshooting table)
- All commands (correct and battle-tested)
- Phase 1.0 skip probe (still skips Phases 1–5 entirely when key auth already works)
- All fallback branches: 7.3 (scp→curl), 8.3 (heredoc→nano), 7.8 (patchelf upgrade)
- Security constraints deny-list
- Idempotency guarantees

---

## Files Changed

| File | Change |
|---|---|
| `SKILL.md` | Add 3-rule execution contract; inline `[EXEC]`/`[TTY]`/`[VERIFY]` tags on every block; structured VERIFY gate format; OS-conditional TTY budget; Phase 9 `[MANDATORY]`; Phase 3.1 labeled "⚠ LAST PASSWORD ENTRY"; state-persistence rule |
| `AGENTS.md` | Mirror all SKILL.md changes (same content, different frontmatter) |

No other files change.

---

## Success Criteria

1. LLM runs all phases via Bash tool — only the 5–6 TTY hand-offs go to the user
2. Amarel password never requested after Phase 3.1
3. Phase 9 runs and reports `VERIFIED` on every execution
4. No VERIFY step advances without its pass gate confirmed
5. VS Code Remote-SSH status bar turns green on first attempt after setup

---

## Defects Fixed in v2

| Defect | Fix |
|---|---|
| TTY count stated as flat "6" — wrong on Linux/Windows | OS-conditional table and budget line |
| VERIFY steps had no pass/fail gate | Structured VERIFY gate format added |
| Execution contract missing noninteractive + credential-prompt rules | Rules 2 and 3 added to contract |
| State persistence across phases not specified | Rule 3 added to execution contract |
| Phases 1–5 not distinguished from manual-run phases | "Background" section added |
