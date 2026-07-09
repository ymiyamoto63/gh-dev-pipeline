# Checks that the Claude Code and GitHub Copilot variants of each agent stay in sync.
#
# The two variants are intentionally identical except for frontmatter and a few
# known phrase differences (Agent tool vs agent tool, AskUserQuestion vs chat).
# For each pair this script strips the frontmatter, computes which body lines
# exist only on one side, and compares that delta against a committed snapshot
# in tools/sync-snapshots/. If the delta changed, one side was edited without
# the other.
#
# Usage:
#   ./tools/check-sync.ps1            # verify (exit 1 on drift)
#   ./tools/check-sync.ps1 -Update    # re-record snapshots after an intentional divergence

[CmdletBinding()]
param([switch]$Update)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$snapshotDir = Join-Path $PSScriptRoot 'sync-snapshots'

$pairs = @(
    @{ Name = 'dev-pipeline';          Claude = 'commands/dev-pipeline.md';          Copilot = 'copilot/agents/dev-pipeline.agent.md' },
    @{ Name = 'requirements-analyst';  Claude = 'agents/requirements-analyst.md';    Copilot = 'copilot/agents/requirements-analyst.agent.md' },
    @{ Name = 'software-architect';    Claude = 'agents/software-architect.md';      Copilot = 'copilot/agents/software-architect.agent.md' },
    @{ Name = 'implementer';           Claude = 'agents/implementer.md';             Copilot = 'copilot/agents/implementer.agent.md' },
    @{ Name = 'test-engineer';         Claude = 'agents/test-engineer.md';           Copilot = 'copilot/agents/test-engineer.agent.md' },
    @{ Name = 'code-reviewer';         Claude = 'agents/code-reviewer.md';           Copilot = 'copilot/agents/code-reviewer.agent.md' },
    @{ Name = 'pr-publisher';          Claude = 'agents/pr-publisher.md';            Copilot = 'copilot/agents/pr-publisher.agent.md' }
)

function Get-Body([string]$path) {
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    $lines = $text -replace "`r`n", "`n" -split "`n"
    if ($lines.Count -gt 0 -and $lines[0] -eq '---') {
        $end = 1
        while ($end -lt $lines.Count -and $lines[$end] -ne '---') { $end++ }
        if ($end + 1 -le $lines.Count - 1) { $lines = $lines[($end + 1)..($lines.Count - 1)] } else { $lines = @() }
    }
    return ,@($lines)
}

function Get-LineCounts([string[]]$lines) {
    # PowerShell's @{} hashtable compares string keys case-insensitively by default,
    # which would silently treat "Read access" and "read access" as the same line.
    # Use an explicit ordinal (case-sensitive) comparer so this matches check-sync.sh.
    $c = New-Object 'System.Collections.Generic.Dictionary[string,int]'([System.StringComparer]::Ordinal)
    foreach ($l in $lines) { if ($c.ContainsKey($l)) { $c[$l]++ } else { $c[$l] = 1 } }
    return $c
}

function Get-UniqueLines([string[]]$src, $otherCounts) {
    $remaining = New-Object 'System.Collections.Generic.Dictionary[string,int]'([System.StringComparer]::Ordinal)
    foreach ($k in $otherCounts.Keys) { $remaining[$k] = $otherCounts[$k] }
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($l in $src) {
        if ($remaining.ContainsKey($l) -and $remaining[$l] -gt 0) { $remaining[$l]-- } else { $out.Add($l) }
    }
    return ,@($out)
}

function Get-Delta([string]$claudePath, [string]$copilotPath) {
    $a = Get-Body $claudePath
    $b = Get-Body $copilotPath
    $delta = New-Object System.Collections.Generic.List[string]
    foreach ($l in (Get-UniqueLines $a (Get-LineCounts $b))) { $delta.Add("claude-only| $l") }
    foreach ($l in (Get-UniqueLines $b (Get-LineCounts $a))) { $delta.Add("copilot-only| $l") }
    return ($delta -join "`n")
}

if (-not (Test-Path $snapshotDir)) { New-Item -ItemType Directory -Path $snapshotDir | Out-Null }

$failed = @()
foreach ($p in $pairs) {
    $claudePath = Join-Path $root $p.Claude
    $copilotPath = Join-Path $root $p.Copilot
    $snapPath = Join-Path $snapshotDir "$($p.Name).delta.txt"

    $delta = Get-Delta $claudePath $copilotPath

    if ($Update) {
        [System.IO.File]::WriteAllText($snapPath, $delta + "`n", (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "updated snapshot: $($p.Name)"
        continue
    }

    $expected = ''
    if (Test-Path $snapPath) {
        $expected = ([System.IO.File]::ReadAllText($snapPath, [System.Text.Encoding]::UTF8) -replace "`r`n", "`n").TrimEnd("`n")
    }

    if ($delta -ne $expected) {
        $failed += $p.Name
        Write-Host "DRIFT: $($p.Name) — the Claude and Copilot bodies diverge beyond the recorded snapshot."
        Write-Host "  current delta (lines present on only one side):"
        if ($delta) { $delta -split "`n" | ForEach-Object { Write-Host "    $_" } } else { Write-Host "    (none)" }
    }
    else {
        Write-Host "ok: $($p.Name)"
    }
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Sync check failed for: $($failed -join ', ')"
    Write-Host "Either mirror the edit to the other variant, or — if the divergence is intentional — run ./tools/check-sync.ps1 -Update and commit the snapshot."
    exit 1
}

Write-Host "all pairs in sync"
