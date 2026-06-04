# Fixing VS Code Source Control on Amarel (and other old-glibc HPC clusters)

**Deep-dive reference for the skill's Phase 11 / Phase 12 (and `setup.sh` Phase 9.5).**
For the guided, one-command-at-a-time version, run the skill and follow Phase 11
(Source Control) and the optional Phase 12 (GitHub). This page explains *why* the
fix works and how to apply it by hand on Amarel or any similar cluster.

---

## The bug

After Remote-SSH connects, VS Code's **Source Control** panel shows *"The folder
currently open doesn't have a Git repository / Initialize Repository"* — even
though the folder is a real, already-cloned git repo. Clicking **Initialize
Repository** does nothing useful; the repo never syncs.

The **Git** output channel (View → Output → "Git") shows the smoking gun:

```
[main] Using git "1.8.3.1" from "git"
[Model][doInitialScan] Initial repository scan started
> git rev-parse --show-toplevel
> git rev-parse --git-dir --git-common-dir
[Model][doInitialScan] Initial repository scan completed - repositories (0) …
```

## Root cause

The VS Code **Server** resolves bare `git` from its **non-interactive PATH**.
On Amarel (CentOS 7) that is the OS-stock **`/usr/bin/git` = git 1.8.3.1**. VS
Code's repository-detection probe runs:

```
git rev-parse --git-dir --git-common-dir
```

`--git-common-dir` was introduced in **git 2.5** (2015). On 1.8.3.1 the probe
fails, repository construction throws, the error is swallowed, and VS Code
registers **0 repositories** → the empty "Initialize Repository" welcome view.

Amarel's modern git is an **Lmod module**, but it lives in the **community module
tree** (`/projects/community/modulefiles`), which is *not* on the default
`MODULEPATH`. You must `module use /projects/community/modulefiles` before
`module load git` finds anything — a bare `module load git` (or `module spider
git`) silently returns nothing. Lmod also initialises only in login/interactive
shells, so it is **absent** in the server's non-interactive context — and the
skill never set `git.path`, so the stale system git always won.

> This is **independent** of the "you are connected to an unsupported OS" banner.
> With the glibc 2.28 sysroot in place the extension host is fully functional;
> the only problem is the git binary version.

## The fix

> **RHEL 9.6 (amarel-new) needs none of this.** The new host ships a modern
> system **git ~2.43**, which passes VS Code's `--git-common-dir` probe out of
> the box — no `git.path` override, no Lmod, no wrapper. The skill's Phase 11
> skip-probe reports `SYSTEM_GIT_OK` and writes nothing. Everything below applies
> to the **legacy CentOS 7 host** (stock git 1.8.3.1).

Set the machine-scoped **`git.path`** to a modern git on the remote. It lives in
the **remote** Machine settings — the same file Phase 9 already edits:

```
~/.vscode-server/data/Machine/settings.json
```

`git.path` is `"scope": "machine"`, so it must be set in the Remote/Machine
settings (not your local user settings), and it always wins over PATH.

### Wrapper vs. absolute path (prefer the absolute path)

The server runs git **non-interactively** (no Lmod), so `git.path` must resolve to
a modern git without an interactive shell. Two ways do that, and the **absolute
path is preferred**:

- **Absolute path (best — and what Amarel needs).** If the modern git runs
  *standalone* — it works in a clean, server-like environment with no
  module-provided libraries (verify with `ldd "$(command -v git)"`: every line
  resolves to `/lib64`, `/usr/lib64`, or vDSO) — point `git.path` straight at the
  binary, e.g. `/projects/community/git/2.35.1/ez82/bin/git`. No per-call Lmod
  cost, and it **cannot silently regress**: if the binary ever disappears, VS Code
  reports `git not found` (loud) instead of quietly using the stock git.
- **Wrapper (only when the binary needs module libraries).** If `ldd` shows
  dependencies under `/opt`, `/projects`, `/home`, … (or `not found`), the binary
  can't run without its module environment, so wrap it:

  ```bash
  #!/usr/bin/env bash
  # ~/.vscode-server/git-modern.sh
  {
    if ! command -v module >/dev/null 2>&1; then
      for i in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
        [ -f "$i" ] && . "$i" 2>/dev/null && break
      done
    fi
    if command -v module >/dev/null 2>&1; then
      # Amarel's git modules are in the community tree, not the default MODULEPATH.
      [ -d /projects/community/modulefiles ] && module use /projects/community/modulefiles 2>/dev/null
      module load git 2>/dev/null
    fi
  } >/dev/null 2>&1
  exec /abs/path/to/modern/git "$@"   # absolute path, NOT bare `git`
  ```

  The last line execs the **absolute path**, not a bare `git`. A wrapper that ends
  in `exec git` will — if `module load` ever fails at runtime — silently resolve
  `git` from `PATH` to CentOS 7's stock `/usr/bin/git` (1.8.3.1), and Source
  Control breaks again with **no error**. Exec'ing the absolute path fails loudly
  instead.

The skill (Phase 11 / `setup.sh` Phase 9.5) automates exactly this: it loads a
modern git module, tests whether the binary runs in a **clean** environment, and
sets `git.path` to the bare binary when it does (the Amarel case) — otherwise it
writes the wrapper (exec'ing the absolute path) and verifies it yields git ≥ 2.5
in a clean environment. If neither works it stops with `NO_MODERN_GIT`.

Resulting `settings.json` on Amarel (absolute path chosen; other keys preserved):

```json
{
    "extensions.verifySignature": false,
    "git.path": "/projects/community/git/2.35.1/ez82/bin/git"
}
```

After writing it, run **Developer: Reload Window**. The Git output should then
show `Using git "2.x"` and `repositories (1)`.

**Automated check.** Phase 11.2 of the skill (and `setup.sh` / `setup.ps1`) now
self-tests the fix: it runs VS Code's exact repo-detection probe
(`git rev-parse --git-dir --git-common-dir`) through the configured `git.path`,
in a throwaway repo under a clean server-like environment, and reports a clear
PASS/FAIL — so you know it works without inspecting the GUI.

---

## Doing it by hand (other clusters, or when the auto-detect can't)

1. **Check the server's git:** `ssh <user>@<host> 'git --version'` — below 2.5
   means the fix is needed.
2. **Find a modern git.** Try, in order:
   - **Lmod / Environment Modules:** `module avail git` → `module load git/<ver>`
     → `command -v git; git --version`. On Amarel the git modules are in a
     community tree, so run `module use /projects/community/modulefiles` first
     (otherwise `module avail git` / `module spider git` show nothing).
   - **Conda:** `conda activate base; which git`.
   - **Spack:** `spack load git`.
3. **Decide wrapper vs absolute:** `ldd "$(command -v git)"`. Any non-system
   path (`/opt`, `/projects`, `/home`, …) or `not found` → use a wrapper.
4. **Verify against your repo** with the candidate git:
   ```bash
   "$GITPATH" -C /path/to/repo rev-parse --git-dir --git-common-dir
   ```
   Two clean paths printed = good.
5. **Write `git.path`** into `~/.vscode-server/data/Machine/settings.json`
   (idempotent merge — preserve existing keys), then **Reload Window**.

   You can also set it in the GUI: **Settings** → switch to the **Remote
   [SSH: <host>]** tab → search `git.path`.

---

## GitHub authentication & identity (Phase 12)

Independent of the `git.path` fix, but needed to push from Amarel. Run these in a
terminal **on Amarel** (VS Code → Terminal → New Terminal).

```bash
# Device flow — no browser on the cluster. Opens a code + URL you approve on your laptop.
BROWSER= gh auth login --hostname github.com --git-protocol https

# Wire gh as git's credential helper (must run AFTER login)
gh auth setup-git

# Identity — see the email note below; the no-reply address is the safe default
git config --global user.name "Your Name"
git config --global user.email "12345678+yourname@users.noreply.github.com"
```

**Which email?** It depends on your GitHub account — not everyone has email
privacy on:

- **Email privacy ON** (GitHub → Settings → Emails → *"Keep my email address
  private"*): you **must** use your GitHub **no-reply** address
  (`12345678+yourname@users.noreply.github.com`, shown on that page) or every push
  is rejected with **GH007**.
- **Email privacy OFF:** you *may* use your real email, but the no-reply address
  still works and keeps your email out of public commit history — so it's the safe
  default either way.

### GH007: push rejected — private email protection

```
remote: error: GH007: Your push would publish a private email address.
```

A commit carries a private address. Set the no-reply email (above), then
re-stamp and push:

```bash
git commit --amend --reset-author --no-edit
git push
```

For multiple bad commits, use `git rebase -i` (re-stamp each) or `git filter-repo`.

---

## Pitfalls

| Pitfall | What happens | Fix |
|---|---|---|
| Editing `~/.bashrc` / `~/.bash_profile` to "fix" git | VS Code Server may not pick it up in its non-interactive context | Use the machine-scoped `git.path` setting |
| Using a module git's absolute path without checking `ldd` | Runtime failure / silent breakage when module libs aren't loaded | Run `ldd`; use the wrapper only if any non-system libs |
| Wrapper ending in `exec git` (not the absolute path) | If `module load` fails at runtime, `git` resolves from `PATH` to stock 1.8.3.1 → Source Control silently breaks again | Exec the modern git's **absolute path** in the wrapper (the skill does this automatically) |
| Setting `git.path` in **local** user settings | Ignored for the remote — it's machine-scoped | Set it in the **Remote [SSH]** / Machine settings |
| `gh auth setup-git` before `gh auth login` | "not logged into any GitHub hosts" | Log in first, then `setup-git` |
| Private email in `user.email` **while GitHub email privacy is ON** | `GH007` on push | Use the GitHub no-reply address (works whether or not privacy is on) |
| VS Code Server upgrade clears settings | Source Control breaks again | Re-run the skill from Phase 11 (idempotent) |
| Fresh start (`reset.sh full` / the skill's "fresh start" offer) | Removes the `git-modern.sh` wrapper **and** strips the `git.path` + `extensions.verifySignature` keys, returning `settings.json` to its pre-skill state (user-added keys kept) | Intentional — re-running the skill (Phase 11) rebuilds it; this is what makes a clean re-test possible |
