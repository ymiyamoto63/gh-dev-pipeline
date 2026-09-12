# Generates both the Claude Code and GitHub Copilot variants of each agent /
# orchestrator definition from the single-source files in src/.
#
# Each src/<name>.md has three sections, introduced by marker lines:
#   <<<claude>>>     Claude-variant frontmatter, verbatim (including the --- lines)
#   <<<copilot>>>    Copilot-variant frontmatter, verbatim
#   <<<body>>>       shared body; format-specific phrases are written inline as
#                    {{claude:...}} / {{copilot:...}}  (marker text must not contain "}")
#
# Rendering rules:
#   - {{claude:X}} expands to X in the Claude output and to nothing in the Copilot
#     output (and vice versa).
#   - A non-empty source line that renders to an empty string (it held only
#     markers for the other format) is dropped entirely.
#   - An AUTO-GENERATED notice is inserted between the frontmatter and the body.
#
# tools/generate.sh is the same generator for bash; keep the two behaviorally identical.
#
# This file is saved as UTF-8 with BOM: it contains Japanese text, and Windows
# PowerShell 5.1 decodes a BOM-less script with the ANSI code page, which would
# mangle that text and make the generated files differ from the bash output.
#
# Usage:
#   ./tools/generate.ps1           # (re)write the generated files
#   ./tools/generate.ps1 -Check    # verify generated files are up to date (exit 1 if stale)

[CmdletBinding()]
param([switch]$Check)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$pairs = @(
    @{ Name = 'dev-pipeline';          Claude = 'commands/dev-pipeline.md';          Copilot = 'copilot/agents/dev-pipeline.agent.md' },
    @{ Name = 'requirements-analyst';  Claude = 'agents/requirements-analyst.md';    Copilot = 'copilot/agents/requirements-analyst.agent.md' },
    @{ Name = 'requirements-reviewer'; Claude = 'agents/requirements-reviewer.md';   Copilot = 'copilot/agents/requirements-reviewer.agent.md' },
    @{ Name = 'software-architect';    Claude = 'agents/software-architect.md';      Copilot = 'copilot/agents/software-architect.agent.md' },
    @{ Name = 'design-reviewer';       Claude = 'agents/design-reviewer.md';         Copilot = 'copilot/agents/design-reviewer.agent.md' },
    @{ Name = 'implementer';           Claude = 'agents/implementer.md';             Copilot = 'copilot/agents/implementer.agent.md' },
    @{ Name = 'test-engineer';         Claude = 'agents/test-engineer.md';           Copilot = 'copilot/agents/test-engineer.agent.md' },
    @{ Name = 'security-reviewer';     Claude = 'agents/security-reviewer.md';       Copilot = 'copilot/agents/security-reviewer.agent.md' },
    @{ Name = 'test-reviewer';         Claude = 'agents/test-reviewer.md';           Copilot = 'copilot/agents/test-reviewer.agent.md' },
    @{ Name = 'structure-reviewer';    Claude = 'agents/structure-reviewer.md';      Copilot = 'copilot/agents/structure-reviewer.agent.md' },
    @{ Name = 'convention-reviewer';   Claude = 'agents/convention-reviewer.md';     Copilot = 'copilot/agents/convention-reviewer.agent.md' },
    @{ Name = 'pr-publisher';          Claude = 'agents/pr-publisher.md';            Copilot = 'copilot/agents/pr-publisher.agent.md' }
)

function Read-Lines([string]$path) {
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    return ,@(($text -replace "`r`n", "`n").TrimEnd("`n") -split "`n")
}

function Parse-Source([string]$path) {
    if (-not (Test-Path $path)) { throw "missing source file: $path" }
    $claude  = New-Object System.Collections.Generic.List[string]
    $copilot = New-Object System.Collections.Generic.List[string]
    $body    = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $current = $null
    foreach ($line in (Read-Lines $path)) {
        if ($line -eq '<<<claude>>>')      { $current = $claude;  $seen['claude']  = $true }
        elseif ($line -eq '<<<copilot>>>') { $current = $copilot; $seen['copilot'] = $true }
        elseif ($line -eq '<<<body>>>')    { $current = $body;    $seen['body']    = $true }
        elseif ($null -eq $current) { if ($line -ne '') { throw "$($path): content before the first section marker" } }
        else { $current.Add($line) }
    }
    foreach ($k in 'claude', 'copilot', 'body') {
        if (-not $seen[$k]) { throw "$($path): missing <<<$k>>> section" }
    }
    return @{ claude = $claude; copilot = $copilot; body = $body }
}

function Render-Body($bodyLines, [string]$keep, [string]$drop, [string]$name) {
    $keepPat = '\{\{' + $keep + ':([^}]*)\}\}'
    $dropPat = '\{\{' + $drop + ':[^}]*\}\}'
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $bodyLines) {
        $r = [regex]::Replace($line, $keepPat, '$1')
        $r = [regex]::Replace($r, $dropPat, '')
        if ($r.Contains('{{') -or $r.Contains('}}')) {
            throw "src/$name.md: unrendered marker remains in line: $r"
        }
        if ($line -ne '' -and $r -eq '' -and $line.Contains('{{')) { continue }
        $out.Add($r)
    }
    return ,@($out)
}

function Build-Output($sections, [string]$fmt, [string]$name) {
    if ($fmt -eq 'claude') { $other = 'copilot' } else { $other = 'claude' }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($l in $sections[$fmt]) { $lines.Add($l) }
    $lines.Add("<!-- 自動生成ファイル: src/$name.md から生成。編集は src/$name.md で行い tools/generate.ps1（または tools/generate.sh）を実行すること。このファイルを直接編集しないこと。 -->")
    foreach ($l in (Render-Body $sections['body'] $fmt $other $name)) { $lines.Add($l) }
    return (($lines -join "`n") + "`n")
}

$stale = @()
foreach ($p in $pairs) {
    $sections = Parse-Source (Join-Path $root "src/$($p.Name).md")
    $targets = @(
        @{ Fmt = 'claude';  Rel = $p.Claude },
        @{ Fmt = 'copilot'; Rel = $p.Copilot }
    )
    foreach ($t in $targets) {
        $outPath = Join-Path $root $t.Rel
        $content = Build-Output $sections $t.Fmt $p.Name
        if ($Check) {
            $existing = ''
            if (Test-Path $outPath) {
                $existing = ([System.IO.File]::ReadAllText($outPath, [System.Text.Encoding]::UTF8) -replace "`r`n", "`n")
            }
            if ($existing -ne $content) { $stale += $t.Rel } else { Write-Host "ok: $($t.Rel)" }
        }
        else {
            [System.IO.File]::WriteAllText($outPath, $content, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "generated: $($t.Rel)"
        }
    }
}

if ($Check) {
    if ($stale.Count -gt 0) {
        Write-Host ""
        Write-Host "STALE: the following generated files do not match src/. Regenerate with ./tools/generate.ps1 (or ./tools/generate.sh) and commit the result - never edit generated files directly:"
        $stale | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    Write-Host "all generated files up to date"
}
