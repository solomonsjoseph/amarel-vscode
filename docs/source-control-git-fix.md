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

Amarel's modern git is an **Lmod module** (`module load git`). Lmod initialises
only in login/interactive shells, so it is **absent** in the server's
non-interactive context — and the skill never set `git.path`, so the stale
system git always won.

> This is **independent** of the "you are connected to an unsupported OS" banner.
> With the glibc 2.28 sysroot in place the extension host is fully functional;
> the only problem is the git binary version.

## The fix

Set the machine-scoped **`git.path`** to a modern git on the remote. It lives in
the **remote** Machine settings — the same file Phase 9 already edits:

```
~/.vscode-server/data/Machine/settings.json
```

`git.path` is `"scope": "machine"`, so it must be set in the Remote/Machine
settings (not your local user settings), and it always wins over PATH.

### Wrapper vs. absolute path

Because the server runs git **non-interactively** (no Lmod), the robust form is a
tiny wrapper that re-creates the module environment, then runs git:

```bash
#!/usr/bin/env bash
# ~/.vscode-server/git-modern.sh
if ! command -v module >/dev/null 2>&1; then
  for i in /etc/profile.d/lmod.sh /etc/profile.d/modules.sh /usr/share/lmod/lmod/init/bash; do
    [ -f "$i" ] && . "$i" 2>/dev/null && break
  done
fi
command -v module >/dev/null 2>&1 && module load git 2>/dev/null
exec git "$@"
```

Point `git.path` at that wrapper. Use a **bare absolute path** instead only when
the modern git has **no** module-provided library dependencies (check with
`ldd`). If the binary links against libraries under `/opt`, `/projects`, etc.,
the wrapper is required — an absolute path without the module env would fail at
runtime.

The skill (Phase 11 / `setup.sh` Phase 9.5) automates this: it writes the
wrapper, verifies it yields git ≥ 2.5 in a **clean** environment, and falls back
to the absolute path only when that is safe.

Resulting `settings.json` (other keys preserved):

```json
{
    "extensions.verifySignature": false,
    "git.path": "/home/<netid>/.vscode-server/git-modern.sh"
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
     → `command -v git; git --version`.
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

# Identity — use your GitHub no-reply address (github.com/settings/emails)
git config --global user.name "Your Name"
git config --global user.email "12345678+yourname@users.noreply.github.com"
```

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
| Using a module git's absolute path without checking `ldd` | Runtime failure / silent breakage when module libs aren't loaded | Run `ldd`; use the wrapper if any non-system libs |
| Setting `git.path` in **local** user settings | Ignored for the remote — it's machine-scoped | Set it in the **Remote [SSH]** / Machine settings |
| `gh auth setup-git` before `gh auth login` | "not logged into any GitHub hosts" | Log in first, then `setup-git` |
| Private email in `user.email` | `GH007` on push | Use the GitHub no-reply address |
| VS Code Server upgrade clears settings | Source Control breaks again | Re-run the skill from Phase 11 (idempotent) |
| Fresh start (`reset.sh full` / the skill's "fresh start" offer) | Removes the `git-modern.sh` wrapper **and** strips the `git.path` + `extensions.verifySignature` keys, returning `settings.json` to its pre-skill state (user-added keys kept) | Intentional — re-running the skill (Phase 11) rebuilds it; this is what makes a clean re-test possible |
