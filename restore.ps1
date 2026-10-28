<#
.SYNOPSIS
Puts back what schizo changed, using the backups in C:\ProgramData\schizo.

.DESCRIPTION
For every registry value, service, scheduled task and firewall rule schizo
changed, restore returns it to the state it had before schizo first touched
it. A value that did not exist is removed again; a service that was Manual
goes back to Manual; a firewall rule schizo created is deleted.

If something was changed by someone else after schizo set it, restore leaves
it alone and says so. -Force restores it anyway.

Restore works without the rules folder and without a network connection.

.PARAMETER Audit
Show what would be restored without changing anything.

.PARAMETER Force
Also restore things that changed after schizo set them.

.EXAMPLE
.\restore.ps1
#>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0
Import-Module (Join-Path $PSScriptRoot 'lib\schizo.psm1') -Force

# known-folder api, not $env:ProgramData: the environment is the user's to change.
$StateRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'schizo'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Host 'use 64-bit powershell.'
    exit 2
}
if (-not (Test-Admin)) {
    Write-Host 'run this from an Administrator PowerShell.'
    exit 2
}

try { $root = Get-StateRoot $StateRoot }
catch { Write-Host $_.Exception.Message; exit 2 }
if (-not $root) {
    Write-Host 'nothing to restore.'
    exit 0
}

$lock = $null
try {
    $lock = Lock-StateRoot $root
    $result = Invoke-Restore -Root $root -Force:$Force -Audit:$Audit
}
catch {
    Write-Host $_.Exception.Message
    exit 2
}
finally {
    if ($lock) { $lock.Dispose() }
}

if (-not $result.Runs.Count) {
    Write-Host 'nothing to restore.'
    exit 0
}

Write-Host "backups: $($result.Runs -join ', ')"
Write-Host ''

$counts = @{}
foreach ($i in $result.Items) {
    $counts[$i.Status] = 1 + [int]$counts[$i.Status]
    $what = Format-Target $i.Target
    switch ($i.Status) {
        'restored' { Write-Host "  $what" }
        'would' { Write-Host "  $what" }
        'already' { Write-Host "  $what" -ForegroundColor DarkGray }
        'gone' { Write-Host "  $what  (no longer exists)" -ForegroundColor DarkGray }
        { $_ -in 'drifted', 'otheruser' } {
            Write-Host "  $what  left alone" -ForegroundColor Yellow
            Write-Host "    $($i.Note)" -ForegroundColor Yellow
        }
        'failed' {
            Write-Host "  $what  failed" -ForegroundColor Red
            Write-Host "    $($i.Note)" -ForegroundColor Red
        }
    }
}
foreach ($p in $result.Problems) { Write-Host "  $p" -ForegroundColor Yellow }

Write-Host ''
if ($Audit) { Write-Host "$([int]$counts['would']) would be restored" }
else { Write-Host "$([int]$counts['restored']) restored" }
Write-Host "$([int]$counts['already'] + [int]$counts['gone']) already back"
if ($counts['drifted']) { Write-Host "$($counts['drifted']) changed since schizo set them, left alone (-Force restores them)" }
if ($counts['otheruser']) { Write-Host "$($counts['otheruser']) belong to another user, left alone" }
Write-Host "$([int]$counts['failed']) failed"
if ($result.ContainsKey('Archived')) {
    Write-Host ''
    Write-Host "backups moved to $(Join-Path $root 'restored')"
}
Write-Host ''
Write-Host 'done.'

if ($counts['failed']) { exit 1 }
exit 0
