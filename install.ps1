<#
.SYNOPSIS
  Install the amarel-vscode-setup skill into local agent skill directories.

.DESCRIPTION
  Creates a junction (Windows symlink-equivalent) so the skill stays in sync
  with `git pull` on this repo. Run once after cloning. Idempotent.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoDir   = Split-Path -Parent $PSCommandPath
$SkillName = 'amarel-vscode-setup'

function Install-SkillLink {
  param(
    [Parameter(Mandatory=$true)][string]$AgentName,
    [Parameter(Mandatory=$true)][string]$SkillsDir
  )

  $Target = Join-Path $SkillsDir $SkillName

  if (-not (Test-Path $SkillsDir)) {
    New-Item -ItemType Directory -Path $SkillsDir -Force | Out-Null
  }

  if (Test-Path $Target) {
    Write-Host "-> removing previous $AgentName install at $Target"
    Remove-Item $Target -Force -Recurse
  }

  # Junction works without Developer Mode and across most Windows configs.
  New-Item -ItemType Junction -Path $Target -Target $RepoDir | Out-Null
  Write-Host "Installed for ${AgentName}: $Target -> $RepoDir" -ForegroundColor Green
}

Install-SkillLink -AgentName 'Claude Code' -SkillsDir (Join-Path $env:USERPROFILE '.claude\skills')
Install-SkillLink -AgentName 'Codex' -SkillsDir (Join-Path $env:USERPROFILE '.codex\skills')

Write-Host ""
Write-Host "Restart Claude Code or Codex so it reloads local skills."
Write-Host "Claude Code command:  /$SkillName"
Write-Host "Codex: ask it to set up VS Code Remote-SSH for Amarel; it will load this skill by name/description."
