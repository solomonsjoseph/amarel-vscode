# Legacy CentOS 7 runbook: Phases 6 to 9 (the custom-glibc sysroot)

> **You only need this file if Phase 5.5 routed you to LEGACY.**
>
> Phase 5.5 probes the remote glibc. On **RHEL 9.6** (`amarel-new.hpc.rutgers.edu`,
> glibc 2.34, the default host) VS Code Server runs natively, Phases 6 to 9 are
> **skipped entirely**, and you should not be reading this. On the **legacy
> CentOS 7 host** (glibc 2.17) VS Code Server 1.99+ refuses to start, and these
> four phases install a glibc 2.28 sysroot into the user's `$HOME` to fix it.
>
> Routing is on **glibc, never hostname**, so a transition DNS alias is handled
> correctly. Do not decide from the hostname which path to take.

These phases live in their own file because they are dead weight on the path that
actually runs. They are 778 of the runbook's ~3,780 lines, about a fifth of it,
and the default host never executes any of them. Splitting them out is issue #35:
the runbook has to fit in a smaller model's context to be usable by one.

**Nothing here is abbreviated.** The phases are moved whole, byte for byte, not
summarised. Every command, success marker, verification gate and recovery branch
is exactly as it was.

**Status.** The legacy path is maintained but has not been re-validated since the
RHEL 9.6 migration. If you are running it and something is wrong, that is worth an
issue.

Back to the main runbook: [`AGENTS.md`](../AGENTS.md)
([raw](https://raw.githubusercontent.com/solomonsjoseph/amarel-vscode/main/AGENTS.md)) or, for Claude Code,
[`SKILL.md`](../skills/amarel-vscode-setup/SKILL.md)
([raw](https://raw.githubusercontent.com/solomonsjoseph/amarel-vscode/main/skills/amarel-vscode-setup/SKILL.md)).

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

---

## Done. Go back to the main runbook.

Phases 6 to 9 are complete. Return to **Phase 10 (Connect from VS Code)** in
[`AGENTS.md`](../AGENTS.md) ([raw](https://raw.githubusercontent.com/solomonsjoseph/amarel-vscode/main/AGENTS.md)), and carry on from there:
Phase 11 fixes Source Control, Phase 12 is optional GitHub auth, and Phase 13 is
the optional compute-node session offered after Phase 12.
