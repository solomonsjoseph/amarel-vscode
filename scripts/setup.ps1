<#
.SYNOPSIS
  amarel-vscode setup — Windows 10/11

.DESCRIPTION
  One-shot bootstrap of SSH key auth + VS Code Server sysroot on Amarel.
  Mirrors scripts/setup.sh; PowerShell idioms throughout.

.NOTES
  Security contract:
    - NEVER reads ~/.ssh/id_* private key contents
    - NEVER captures passwords from stdin pipes
    - Every command that could prompt for a password uses BatchMode=yes after key setup
    - User types each secret directly into a TTY prompt the OS owns

.PARAMETER AmarelUser
  Your Rutgers Amarel username. Prompts interactively if omitted.

.EXAMPLE
  .\setup.ps1
  .\setup.ps1 -AmarelUser sj1136
#>

[CmdletBinding()]
param(
  [string]$AmarelUser
)

$ErrorActionPreference = 'Stop'

# ─── Constants ──────────────────────────────────────────────────────────────
$AmarelHost     = 'amarel.rutgers.edu'
$SkillDir       = Split-Path -Parent $PSScriptRoot
$SshDir         = Join-Path $env:USERPROFILE '.ssh'
$SshKeyPath     = Join-Path $SshDir 'id_ed25519_amarel'
$SshConfigPath  = Join-Path $SshDir 'config'
$KnownHostsPath = Join-Path $SshDir 'known_hosts'

$DefaultTarballUrl = 'https://github.com/solomonsjoseph/amarel-vscode/releases/latest/download/vscode-sysroot-x86_64-linux-gnu.tgz'
$TarballUrl        = if ($env:TARBALL_URL) { $env:TARBALL_URL } else { $DefaultTarballUrl }
$TarballLocal      = Join-Path $SkillDir 'build\vscode-sysroot-x86_64-linux-gnu.tgz'

$ChecksumsFile = Join-Path $SkillDir 'assets\checksums.txt'
$SysrootScript = Join-Path $SkillDir 'assets\sysroot.sh'

# ─── Helpers ────────────────────────────────────────────────────────────────
function Write-Info    { param($Msg) Write-Host "  ✓ $Msg"             -ForegroundColor Green }
function Write-Warn    { param($Msg) Write-Host "  ! $Msg"             -ForegroundColor Yellow }
function Write-Err     { param($Msg) Write-Host "  ✗ $Msg"             -ForegroundColor Red }
function Write-Human   { param($Msg) Write-Host "`n🔒 YOUR TURN: $Msg" -ForegroundColor Cyan }
function Write-Heading { param($Msg) Write-Host "`n› $Msg"             -ForegroundColor White -BackgroundColor DarkBlue }

function Confirm-User {
  param([string]$Prompt)
  while ($true) {
    $reply = Read-Host "  ? $Prompt [y/N]"
    switch -Regex ($reply) {
      '^[Yy]([Ee][Ss])?$' { return $true }
      '^([Nn]([Oo])?)?$'  { return $false }
      default { Write-Host "    please answer yes or no" }
    }
  }
}

function Die {
  param([string]$Msg)
  Write-Err $Msg
  exit 1
}

# ─── Phase 0 — Preflight ────────────────────────────────────────────────────
function Invoke-PhasePreflight {
  Write-Heading "Phase 0 — Checking prerequisites"

  # OpenSSH client
  $missing = @()
  foreach ($cmd in 'ssh','scp','ssh-keygen','ssh-add','ssh-keyscan') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { $missing += $cmd }
  }
  if ($missing.Count -gt 0) {
    Write-Err "Missing OpenSSH tools: $($missing -join ', ')"
    Write-Err "Install with: Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0  (admin PowerShell)"
    Die "OpenSSH client not fully installed."
  }
  Write-Info "OpenSSH tools present"

  # ssh-agent service
  $svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
  if (-not $svc) { Die "ssh-agent service not found. Install OpenSSH Client capability." }
  if ($svc.StartType -ne 'Automatic') {
    Write-Warn "ssh-agent service not set to Automatic — fixing (requires admin PowerShell)"
    try { Set-Service ssh-agent -StartupType Automatic -ErrorAction Stop } catch {
      Write-Warn "Could not change start type (run as admin to persist). Continuing anyway."
    }
  }
  if ($svc.Status -ne 'Running') {
    Start-Service ssh-agent
  }
  Write-Info "ssh-agent service is running"

  # VS Code (warn-only)
  if (Get-Command code -ErrorAction SilentlyContinue) {
    $ver = (code --version 2>$null | Select-Object -First 1)
    Write-Info "VS Code CLI present: $ver"
    if ((code --list-extensions 2>$null) -match '^ms-vscode-remote\.remote-ssh$') {
      Write-Info "Remote-SSH extension installed"
    } else {
      Write-Warn "Remote-SSH extension not installed. Install: code --install-extension ms-vscode-remote.remote-ssh"
    }
  } else {
    Write-Warn "VS Code 'code' command not on PATH. Install VS Code, add to PATH from setup."
  }

  # Amarel username
  if (-not $AmarelUser) { $script:AmarelUser = Read-Host "  ? Your Amarel username" }
  if (-not $AmarelUser) { Die "Amarel username required." }
  Write-Info "Amarel target: $AmarelUser@$AmarelHost"

  # VPN reachability
  try {
    $tcp = Test-NetConnection -ComputerName $AmarelHost -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue
    if (-not $tcp) {
      Write-Err "Cannot reach ${AmarelHost}:22"
      Write-Err "Connect to the Rutgers VPN first, then re-run."
      Die "VPN check failed."
    }
    Write-Info "Amarel reachable on port 22 (VPN appears active)"
  } catch {
    Write-Warn "Could not run Test-NetConnection — skipping VPN reachability check"
  }
}

# ─── Phase 1 — SSH key creation ─────────────────────────────────────────────
function Invoke-PhaseKeygen {
  Write-Heading "Phase 1 — SSH key"

  if (Test-Path $SshKeyPath) {
    Write-Info "Existing key found at $SshKeyPath — reusing"
    return
  }

  if (-not (Test-Path $SshDir)) { New-Item -ItemType Directory -Path $SshDir -Force | Out-Null }

  Write-Human "I'll launch ssh-keygen interactively. Pick a passphrase you'll remember. The passphrase NEVER leaves your terminal — I cannot see what you type."
  Write-Host ""
  Write-Host "  Command: ssh-keygen -t ed25519 -f `"$SshKeyPath`" -C `"amarel-vscode-$env:USERNAME@$env:COMPUTERNAME`""
  Write-Host ""

  if (-not (Confirm-User "Run ssh-keygen now?")) { Die "Aborted by user." }

  & ssh-keygen -t ed25519 -f $SshKeyPath -C "amarel-vscode-$env:USERNAME@$env:COMPUTERNAME"
  if (-not (Test-Path $SshKeyPath) -or -not (Test-Path "$SshKeyPath.pub")) {
    Die "Key generation failed."
  }
  Write-Info "Key created: $SshKeyPath"
}

# ─── Phase 2 — Host key fingerprint verification ───────────────────────────
function Invoke-PhaseKnownHost {
  Write-Heading "Phase 2 — Verify Amarel's host fingerprint"

  if ((Test-Path $KnownHostsPath) -and (Select-String -Path $KnownHostsPath -Pattern "^$([regex]::Escape($AmarelHost)) " -Quiet)) {
    Write-Info "$AmarelHost already in known_hosts — skipping fingerprint check"
    return
  }

  Write-Host "Fetching $AmarelHost host key…"
  $tmp = New-TemporaryFile
  & ssh-keyscan -t ed25519 $AmarelHost 2>$null | Out-File -Encoding ascii $tmp.FullName
  if ((Get-Content $tmp.FullName).Count -eq 0) {
    Remove-Item $tmp -Force
    Die "Could not retrieve host key from $AmarelHost. (Are you on the VPN?)"
  }

  Write-Host ""
  Write-Host "  Host key fingerprint (verify this against Rutgers OARC's published value):"
  & ssh-keygen -lf $tmp.FullName | ForEach-Object { "    $_" }
  Write-Host ""
  Write-Host "  Reference fingerprint (recorded 2026-05-26 during initial setup):"
  Write-Host "    SHA256:cN6l3kR3jbdOv6Ofz1b+KNCt3LaOCj9bq6yeHoR3eLs"
  Write-Host ""

  Write-Human "Compare the fingerprint above against what Rutgers OARC publishes. Only continue if they match. A mismatch means a possible man-in-the-middle attack."

  if (-not (Confirm-User "Does the fingerprint match?")) {
    Remove-Item $tmp -Force
    Die "Fingerprint mismatch or unverified — aborting."
  }

  if (-not (Test-Path $KnownHostsPath)) { New-Item -ItemType File -Path $KnownHostsPath -Force | Out-Null }
  Get-Content $tmp.FullName | Add-Content $KnownHostsPath
  Remove-Item $tmp -Force
  Write-Info "Host key recorded in $KnownHostsPath"
}

# ─── Phase 3 — Install public key on Amarel ────────────────────────────────
function Invoke-PhaseCopyId {
  Write-Heading "Phase 3 — Install public key on Amarel"

  $args = @('-o','BatchMode=yes','-o','ConnectTimeout=5','-i',$SshKeyPath,"$AmarelUser@$AmarelHost",'true')
  & ssh @args 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Info "Key-based login already works — skipping ssh-copy-id"
    return
  }

  Write-Human "I'll now install your public key on Amarel. When prompted, type your Amarel password into the terminal. This is the ONLY time you'll need to type it. I cannot see what you type."
  Write-Host ""
  if (-not (Confirm-User "Proceed?")) { Die "Aborted by user." }

  # Windows has no ssh-copy-id; equivalent one-liner:
  $pubkey = Get-Content "$SshKeyPath.pub" -Raw
  # Send the pubkey via stdin to ssh, which appends to authorized_keys on Amarel.
  # Note: -tt forces TTY allocation so the Amarel password prompt is visible.
  $remoteCmd = 'umask 077; mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && ' +
               'grep -qxF "$(cat)" ~/.ssh/authorized_keys || cat >> ~/.ssh/authorized_keys'

  $pubkey | & ssh -tt -o PreferredAuthentications=password -o PubkeyAuthentication=no "$AmarelUser@$AmarelHost" $remoteCmd

  # Verify
  & ssh -o BatchMode=yes -o ConnectTimeout=5 -i $SshKeyPath "$AmarelUser@$AmarelHost" 'true' 2>$null
  if ($LASTEXITCODE -ne 0) {
    Die "Public key install appeared to succeed but key auth still fails. Inspect ~/.ssh/authorized_keys on Amarel."
  }
  Write-Info "Public key installed and verified"
}

# ─── Phase 4 — ssh-agent + Windows Credential Manager (DPAPI) ──────────────
function Invoke-PhaseAgent {
  Write-Heading "Phase 4 — Save passphrase to Windows credential store"

  $fp = (& ssh-keygen -lf $SshKeyPath).Split(' ')[1]
  $loaded = (& ssh-add -l 2>$null) | Select-String -Pattern $fp -Quiet
  if ($loaded) {
    Write-Info "Key already loaded in ssh-agent"
  } else {
    Write-Human "ssh-add will prompt for your key passphrase. After this, Windows Credential Manager stores it and you'll never type it again."
    if (-not (Confirm-User "Run ssh-add now?")) { Die "Aborted by user." }
    & ssh-add $SshKeyPath
    if ($LASTEXITCODE -ne 0) { Die "ssh-add failed." }
    Write-Info "Key added to ssh-agent (passphrase saved to DPAPI)"
  }

  Set-SshConfigEntry
}

function Set-SshConfigEntry {
  if (-not (Test-Path $SshDir)) { New-Item -ItemType Directory -Path $SshDir -Force | Out-Null }
  if (-not (Test-Path $SshConfigPath)) { New-Item -ItemType File -Path $SshConfigPath -Force | Out-Null }

  if (Select-String -Path $SshConfigPath -Pattern "^Host $([regex]::Escape($AmarelHost))$" -Quiet) {
    Write-Info "~/.ssh/config already has entry for $AmarelHost"
    return
  }

  $date = Get-Date -Format 'yyyy-MM-dd'
  $entry = @"

# Added by amarel-vscode skill on $date
Host $AmarelHost
  User $AmarelUser
  IdentityFile $SshKeyPath
  IdentitiesOnly yes
  AddKeysToAgent yes
"@
  Add-Content -Path $SshConfigPath -Value $entry
  Write-Info "~/.ssh/config entry added"
}

# ─── Phase 5 — Verify passwordless SSH ─────────────────────────────────────
function Invoke-PhaseVerifyPasswordless {
  Write-Heading "Phase 5 — Verify passwordless SSH"

  & ssh -o BatchMode=yes -o ConnectTimeout=10 "$AmarelUser@$AmarelHost" 'echo ok; hostname; whoami' 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Info "Passwordless SSH works"
  } else {
    Die "Passwordless SSH still failing. Inspect: ssh -v $AmarelUser@$AmarelHost"
  }
}

# ─── Phase 6 — Download + verify tarball ───────────────────────────────────
function Invoke-PhaseDownloadTarball {
  Write-Heading "Phase 6 — Download sysroot tarball"

  $dir = Split-Path -Parent $TarballLocal
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

  if (Test-Path $TarballLocal) {
    Write-Info "Tarball already present locally: $TarballLocal"
  } else {
    Write-Host "Downloading from: $TarballUrl"
    try {
      Invoke-WebRequest -Uri $TarballUrl -OutFile $TarballLocal -UseBasicParsing
    } catch {
      Write-Err "Tarball download failed: $_"
      Die "Cannot continue without tarball."
    }
    Write-Info "Tarball downloaded"
  }

  Test-Sha256 -File $TarballLocal -LookupName 'vscode-sysroot-x86_64-linux-gnu.tgz'
}

function Test-Sha256 {
  param([string]$File, [string]$LookupName)
  if (-not (Test-Path $ChecksumsFile)) { Write-Warn "No checksums file — skipping verification"; return }
  $line = (Get-Content $ChecksumsFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -match $LookupName } | Select-Object -First 1)
  if (-not $line) { Write-Warn "No checksum recorded for $LookupName — skipping"; return }
  $expected = ($line -split '\s+')[0]
  if ($expected -match '^0+$') { Write-Warn "Checksum placeholder — skipping verification"; return }
  $actual = (Get-FileHash -Path $File -Algorithm SHA256).Hash.ToLower()
  if ($expected.ToLower() -eq $actual) {
    Write-Info "SHA-256 verified for $LookupName"
  } else {
    Write-Err "SHA-256 mismatch for $LookupName"
    Write-Err "  expected: $expected"
    Write-Err "  actual:   $actual"
    Die "Refusing to install a tarball that doesn't match its recorded hash."
  }
}

# ─── Phase 7 — Deploy sysroot on Amarel ────────────────────────────────────
function Invoke-PhaseDeploy {
  Write-Heading "Phase 7 — Deploy sysroot on Amarel"

  Write-Host "scp tarball → $AmarelUser@$AmarelHost:~/"
  & scp -q $TarballLocal "$AmarelUser@${AmarelHost}:~/vscode-sysroot-x86_64-linux-gnu.tgz"
  if ($LASTEXITCODE -ne 0) { Die "scp tarball failed" }

  Write-Host "scp sysroot.sh → $AmarelUser@$AmarelHost:~/"
  & scp -q $SysrootScript "$AmarelUser@${AmarelHost}:~/sysroot.sh"
  if ($LASTEXITCODE -ne 0) { Die "scp sysroot.sh failed" }

  Write-Info "Files uploaded"

  $remoteScript = @'
set -euo pipefail
if [ -d "$HOME/.vscode-server/sysroot" ]; then
  chmod -R u+w "$HOME/.vscode-server" 2>/dev/null || true
fi
rm -rf "$HOME/.vscode-server/cli" "$HOME/.vscode-server/extensions" 2>/dev/null || true
mkdir -p "$HOME/.vscode-server"
if [ ! -d "$HOME/.vscode-server/sysroot" ]; then
  tar zxf "$HOME/vscode-sysroot-x86_64-linux-gnu.tgz" -C "$HOME/.vscode-server"
fi
mv -f "$HOME/sysroot.sh" "$HOME/.vscode-server/sysroot.sh"
rm -f "$HOME/vscode-sysroot-x86_64-linux-gnu.tgz"
test -f "$HOME/.vscode-server/sysroot/lib/ld-linux-x86-64.so.2" || { echo "ERR: linker missing"; exit 1; }
test -x "$HOME/.vscode-server/sysroot/usr/bin/patchelf"        || { echo "ERR: patchelf missing or not exec"; exit 1; }
test -f "$HOME/.vscode-server/sysroot.sh"                      || { echo "ERR: sysroot.sh missing"; exit 1; }
if ! grep -q '\.vscode-server/sysroot\.sh' "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# VS Code Server custom glibc workaround (added by amarel-vscode skill)\n[ -f "$HOME/.vscode-server/sysroot.sh" ] && source "$HOME/.vscode-server/sysroot.sh"\n' >> "$HOME/.bashrc"
fi
echo "remote setup OK"
'@

  $remoteScript | & ssh "$AmarelUser@$AmarelHost" 'bash -se'
  if ($LASTEXITCODE -ne 0) { Die "Remote setup failed." }
  Write-Info "Remote extraction + configuration complete"
}

# ─── Phase 8 — Verify env vars in non-interactive shell ────────────────────
function Invoke-PhaseVerifyEnv {
  Write-Heading "Phase 8 — Verify env vars in non-interactive SSH"

  $result = (& ssh -o BatchMode=yes "$AmarelUser@$AmarelHost" 'echo "$VSCODE_SERVER_PATCHELF_PATH"').Trim()
  $expected = "/home/$AmarelUser/.vscode-server/sysroot/usr/bin/patchelf"
  if ($result -eq $expected) {
    Write-Info "Env vars load correctly in non-interactive shells"
  } else {
    Write-Err "Got:      '$result'"
    Write-Err "Expected: '$expected'"
    Die "Env vars not loading — VS Code Remote-SSH will still fail. Check ~/.bashrc on Amarel."
  }
}

# ─── Phase 9 — Final instructions ──────────────────────────────────────────
function Invoke-PhaseFinish {
  Write-Heading "Phase 9 — Open VS Code"
  Write-Host ""
  Write-Host "  ✓ Server-side setup complete." -ForegroundColor Green
  Write-Host ""
  Write-Host "  YOUR TURN — finish in VS Code:" -ForegroundColor White
  Write-Host ""
  Write-Host "    1. Open VS Code"
  Write-Host "    2. Ctrl+Shift+P"
  Write-Host "    3. Type: Remote-SSH: Connect to Host"
  Write-Host "    4. Pick: $AmarelHost  (or type $AmarelUser@$AmarelHost)"
  Write-Host "    5. First time only: click Allow on the 'OS unsupported' warning"
  Write-Host ""
  Write-Host "  Status bar will show: SSH: $AmarelHost" -ForegroundColor Green
  Write-Host ""
}

# ─── main ──────────────────────────────────────────────────────────────────
Write-Host @"
==========================================
 amarel-vscode - Remote-SSH setup for Amarel
==========================================

  This will:
    - Generate an SSH keypair for Amarel (if missing)
    - Install your public key on Amarel (one password prompt)
    - Save your key's passphrase in Windows Credential Manager
    - Deploy a custom-glibc sysroot to your Amarel `$HOME
    - Wire it into ~/.bashrc so VS Code Server installs cleanly

  You'll type two things during setup:
    - Amarel password - once, into ssh's prompt
    - Key passphrase - once, into ssh-add's prompt
    After that: zero password typing forever.

"@

Invoke-PhasePreflight
Invoke-PhaseKeygen
Invoke-PhaseKnownHost
Invoke-PhaseCopyId
Invoke-PhaseAgent
Invoke-PhaseVerifyPasswordless
Invoke-PhaseDownloadTarball
Invoke-PhaseDeploy
Invoke-PhaseVerifyEnv
Invoke-PhaseFinish
