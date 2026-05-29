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

$RepoDir    = Split-Path -Parent $PSCommandPath
$SkillName  = 'amarel-vscode-setup'
$PluginName = 'amarel-vscode'

function Install-Link {
  param(
    [Parameter(Mandatory=$true)][string]$AgentName,
    [Parameter(Mandatory=$true)][string]$SourceDir,
    [Parameter(Mandatory=$true)][string]$ParentDir,
    [Parameter(Mandatory=$true)][string]$Name
  )

  $Target = Join-Path $ParentDir $Name

  if (-not (Test-Path $ParentDir)) {
    New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
  }

  if (Test-Path $Target) {
    Write-Host "-> removing previous $AgentName install at $Target"
    Remove-Item $Target -Force -Recurse
  }

  # Junction works without Developer Mode and across most Windows configs.
  New-Item -ItemType Junction -Path $Target -Target $SourceDir | Out-Null
  Write-Host "Installed for ${AgentName}: $Target -> $SourceDir" -ForegroundColor Green
}

$SkillSourceDir = Join-Path $RepoDir "skills\$SkillName"

Install-Link -AgentName 'Claude Code' -SourceDir $SkillSourceDir -ParentDir (Join-Path $env:USERPROFILE '.claude\skills') -Name $SkillName
Install-Link -AgentName 'Codex' -SourceDir $SkillSourceDir -ParentDir (Join-Path $env:USERPROFILE '.codex\skills') -Name $SkillName
Install-Link -AgentName 'Gemini CLI' -SourceDir $RepoDir -ParentDir (Join-Path $env:USERPROFILE '.gemini\config\plugins') -Name $PluginName

Write-Host ""
Write-Host "Restart your agent so it reloads the local skills/plugins."
Write-Host "Claude Code command:  /$SkillName"
Write-Host "Gemini / Codex: ask it to set up VS Code Remote-SSH for Amarel; it will load this skill by name/description."
