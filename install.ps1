<#
.SYNOPSIS
  Install the amarel-vscode-setup skill into %USERPROFILE%\.claude\skills\

.DESCRIPTION
  Creates a junction (Windows symlink-equivalent) so the skill stays in sync
  with `git pull` on this repo. Run once after cloning. Idempotent.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoDir   = Split-Path -Parent $PSCommandPath
$SkillName = 'amarel-vscode-setup'
$SkillsDir = Join-Path $env:USERPROFILE '.claude\skills'
$Target    = Join-Path $SkillsDir $SkillName

if (-not (Test-Path $SkillsDir)) { New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null }

if (Test-Path $Target) {
  Write-Host "-> removing previous install at $Target"
  Remove-Item $Target -Force -Recurse
}

# Junction works without Developer Mode and across most Windows configs
New-Item -ItemType Junction -Path $Target -Target $RepoDir | Out-Null

Write-Host "Installed: $Target -> $RepoDir" -ForegroundColor Green
Write-Host ""
Write-Host "Restart Claude Code, then run:  /$SkillName"
