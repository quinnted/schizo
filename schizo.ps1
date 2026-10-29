<#
.SYNOPSIS
Applies the privacy rules in this repository that match this machine, then exits.

.DESCRIPTION
Inventories installed software, picks the rules in .\rules that apply, backs up
everything it is about to change to C:\ProgramData\schizo, and changes it.
Run .\restore.ps1 to put things back.

Nothing is downloaded and nothing is sent anywhere. Unknown software is
listed, not touched.

.PARAMETER Audit
Show what would change. Changes nothing, writes no backup, and works without
admin rights (a few things can't be read without them).

.PARAMETER Aggressive
Also apply rules marked aggressive. Those cost a feature; each one says which.

.PARAMETER ShowUnknown
List installed applications that no rule knows about. Runtimes, drivers,
Store support packages, parts of Windows and Steam games are counted but
not listed.

.PARAMETER ShowUnknownAll
List everything the inventory found that no rule knows about, each with what
schizo took it for.

.EXAMPLE
.\schizo.ps1

.EXAMPLE
.\schizo.ps1 -Audit -ShowUnknown
#>
[CmdletBinding()]
param(
    [switch]$Audit,
    [switch]$Aggressive,
    [switch]$ShowUnknown,
    [switch]$ShowUnknownAll
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 1.0
Import-Module (Join-Path $PSScriptRoot 'lib\schizo.psm1') -Force

# known-folder api, not $env:ProgramData: the environment is the user's to change.
$StateRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)) 'schizo'

function Write-Row {
    param([string]$Name, [string]$Value, [string]$Color)
    $line = '  {0,-35} {1}' -f $Name, $Value
    if ($Color) { Write-Host $line -ForegroundColor $Color } else { Write-Host $line }
}

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    Write-Host 'use 64-bit powershell. 32-bit powershell sees a redirected registry and Program Files.'
    exit 2
}
if (-not $Audit -and -not (Test-Admin)) {
    Write-Host 'run this from an Administrator PowerShell.'
    exit 2
}

try { $rulebase = Import-Rules (Join-Path $PSScriptRoot 'rules') }
catch { Write-Host $_.Exception.Message; exit 2 }

$machine = Get-Machine $rulebase.Apps

if (-not $Audit) {
    $refusal = $null
    if ($machine.Server) { $refusal = 'windows server is not supported.' }
    elseif ($machine.Build -lt 26100) { $refusal = "schizo supports windows 11 24H2 (build 26100) and later. this is build $($machine.Build)." }
    else {
        $managed = Get-ManagedReason
        if ($managed) { $refusal = "this machine is managed by an organization ($managed). schizo is for machines you control." }
    }
    if ($refusal) {
        Write-Host $refusal
        Write-Host '-Audit still works.'
        exit 2
    }
}

$run = $null
if (-not $Audit) {
    try { $run = Open-Run $StateRoot }
    catch { Write-Host $_.Exception.Message; exit 2 }
}

try {
    $owned = @{}
    if ($run) {
        $earlier = @(Get-ActiveRuns $run.Root | Where-Object { $_.FullName -ne $run.Dir })
        $changes = Read-Changes $earlier
        foreach ($id in $changes.Groups.Keys) { $owned[$id] = $changes.Groups[$id].Set }
    }
    $results = @(Invoke-Schizo -Rulebase $rulebase -Machine $machine -Run $run -Aggressive:$Aggressive -Owned $owned)
}
finally {
    Close-Run $run
}

# a changed machine environment variable only reaches new processes after
# explorer hears about it.
$envChanged = @($results | Where-Object {
        $_.Status -eq 'changed' -and @(@($_.Rule.Set) | Where-Object { $_.Key -like '*\Session Manager\Environment' }).Count
    }).Count
if ($envChanged) { Send-EnvironmentChange }

Write-Host $machine.Label
if ($machine.Edition -eq 'home') {
    Write-Host 'home edition: microsoft documents most of these windows policies for pro and up. schizo sets them; home may ignore some.' -ForegroundColor DarkGray
}
Write-Host "$(@($machine.Installed).Count) apps found"
foreach ($gap in $machine.Gaps) { Write-Host "  $gap" }
Write-Host ''

$human = New-Object System.Collections.Generic.List[string]
$counts = @{}
$shown = $results | Where-Object { $_.Status -in 'changed', 'already', 'failed', 'conflict', 'would' }
$group = $null
foreach ($r in $shown) {
    $counts[$r.Status] = 1 + [int]$counts[$r.Status]
    if ($r.Rule.App -ne $group) {
        $group = $r.Rule.App
        Write-Host $rulebase.Apps[$group].Name.ToLowerInvariant()
    }
    switch ($r.Status) {
        'changed' { Write-Row $r.Rule.Name $r.Rule.State }
        'already' { Write-Row $r.Rule.Name $r.Rule.State DarkGray }
        'would' { Write-Row $r.Rule.Name "would be $($r.Rule.State)" }
        'failed' {
            Write-Row $r.Rule.Name 'failed' Red
            foreach ($n in $r.Notes) { Write-Host "    $n" -ForegroundColor Red }
        }
        'conflict' {
            Write-Row $r.Rule.Name 'left alone' Yellow
            foreach ($n in $r.Notes) { $human.Add("$($r.Rule.Id)`n    $n") }
        }
    }
}
foreach ($r in $results) {
    if ($r.Status -in 'aggressive', 'otheruser') { $counts[$r.Status] = 1 + [int]$counts[$r.Status] }
    if ($r.Status -eq 'advice') {
        $advice = (Format-Wrapped $r.Rule.Advice 4) -join "`n"
        $human.Add("$($rulebase.Apps[$r.Rule.App].Name.ToLowerInvariant()): $($r.Rule.Name)`n$advice")
    }
}

if ($counts['otheruser']) {
    $human.Add("per-user settings`n    skipped $($counts['otheruser']) rules: schizo runs as $($machine.User), but someone else is signed in.`n    run it from that account's own elevated shell.")
}

# extensions are per user, and only the current user's profiles are read.
$extensions = @()
if (-not $machine.OtherUser) { $extensions = @(Get-BrowserExtensions) }
# what a school or company put there by policy is listed apart from what the
# user installed. both lists only show extensions with broad access.
$managed = @($extensions | Where-Object { $_.Source -eq 'policy' })
$broad = @($extensions | Where-Object { $_.Facts.Count })
Set-ExtensionLabel $broad

if ($human.Count) {
    Write-Host ''
    Write-Host 'needs a human'
    foreach ($h in $human) { Write-Host "  $h" }
}

function Write-Extensions {
    param([string]$Title, [object[]]$List)
    if (-not $List.Count) { return }
    Write-Host ''
    Write-Host $Title
    foreach ($e in ($List | Sort-Object { $_.Browser }, { $_.Label })) {
        Write-Host ('  {0,-8} {1}' -f $e.Browser, $e.Label)
        $facts = @()
        if ($e.Disabled) { $facts += 'disabled' }
        if ($e.Source -eq 'other program') { $facts += 'added by another program' }
        if ($e.Source -eq 'unpacked') { $facts += 'loaded unpacked' }
        $facts += $e.Facts
        foreach ($l in (Format-Wrapped ($facts -join ', ') 11)) { Write-Host $l -ForegroundColor DarkGray }
    }
}
Write-Extensions 'browser extensions with broad access (no rules; not touched)' @($broad | Where-Object { $_.Source -ne 'policy' })
Write-Extensions 'managed browser extensions with broad access (installed by policy; not touched)' @($broad | Where-Object { $_.Source -eq 'policy' })

# the unknown list is for deciding what to research next, so it leaves out
# what is plainly not an application. -ShowUnknownAll shows all of it.
$unknownApps = @($machine.Unknown | Where-Object { -not $_.Kind })
$listed = @{}
$unknownLines = @(foreach ($u in ($unknownApps | Sort-Object { if ($_.Title) { $_.Title } else { $_.Name } })) {
        $key = Get-AppKey $u
        if ($listed.ContainsKey($key)) { continue }
        $listed[$key] = $true
        Format-UnknownApp $u
    })
if ($ShowUnknownAll -and @($machine.Unknown).Count) {
    Write-Host ''
    Write-Host 'no rules'
    foreach ($u in ($machine.Unknown | Sort-Object { if ($_.Title) { $_.Title } else { $_.Name } })) {
        $line = Format-UnknownApp $u
        if ($u.Kind) { $line += "  [$($u.Kind)]" }
        Write-Host "  $line"
    }
}
elseif ($ShowUnknown -and $unknownLines.Count) {
    Write-Host ''
    Write-Host 'no rules'
    foreach ($l in $unknownLines) { Write-Host "  $l" }
}
Write-Host ''
if ($Audit) {
    Write-Host "$([int]$counts['would']) would change"
}
else {
    Write-Host "$([int]$counts['changed']) changed"
}
Write-Host "$([int]$counts['already']) already set"
Write-Host "$([int]$counts['failed']) failed"
Write-Host "$($human.Count) need a human"
$userBroad = @($broad | Where-Object { $_.Source -ne 'policy' }).Count
if ($userBroad) { Write-Host "$userBroad extensions with broad access" }
if ($managed.Count) { Write-Host "$($managed.Count) extensions installed by policy, $($broad.Count - $userBroad) with broad access" }
if ($counts['aggressive']) { Write-Host "$($counts['aggressive']) aggressive rules not applied (-Aggressive)" }
$hidden = @($machine.Unknown).Count - $unknownApps.Count
if (-not ($ShowUnknown -or $ShowUnknownAll)) { Write-Host "$($unknownLines.Count) apps have no rules (-ShowUnknown)" }
if ($hidden -and -not $ShowUnknownAll) { Write-Host "$hidden runtimes, drivers, support packages and games not counted (-ShowUnknownAll)" }

if ($run -and $run.Changes) {
    Write-Host ''
    Write-Host 'backup:'
    Write-Host "  $($run.Dir)"
}
Write-Host ''
Write-Host 'done.'

if ($counts['failed']) { exit 1 }
exit 0
