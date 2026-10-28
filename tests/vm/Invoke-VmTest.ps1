<#
.SYNOPSIS
Runs the destructive integration tests inside a throwaway VMware VM.

.DESCRIPTION
Reverts the VM to a snapshot, copies this repository in, runs
tests\vm\guest.ps1 elevated with the network adapter disconnected,
copies the results back, and powers the VM off. The VM is reverted again
on the next run, so nothing the tests do survives.

The VM needs: Windows 11, VMware Tools, an administrator account that is not
subject to UAC token filtering (the built-in Administrator is the simple
choice), and a snapshot taken in that state. Install whatever apps you want
covered (the tests expect Edge and 7-Zip) before taking the snapshot.

Needs vmrun.exe from VMware Workstation. Never point this at a VM you care
about.

.EXAMPLE
.\tests\vm\Invoke-VmTest.ps1 -Vmx D:\vms\schizo-test\schizo-test.vmx -Snapshot clean -Credential (Get-Credential Administrator)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Vmx,
    [string]$Snapshot = 'clean',
    [Parameter(Mandatory)][pscredential]$Credential,
    [string]$Vmrun = "${env:ProgramFiles(x86)}\VMware\VMware Workstation\vmrun.exe",
    [switch]$Online,
    # where results land; give each VM its own when running several at once
    [string]$Out,
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$out = if ($Out) { $Out } else { Join-Path $repo 'tests\vm\out' }
$user = $Credential.UserName
$pass = $Credential.GetNetworkCredential().Password

function Invoke-Vmrun {
    param([string[]]$Arguments, [switch]$Guest, [switch]$AllowFailure)
    $a = @('-T', 'ws')
    if ($Guest) { $a += '-gu', $user, '-gp', $pass }
    $text = & $Vmrun @a @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) { throw "vmrun $($Arguments[0]) failed: $text" }
    $text.Trim()
}

function Wait-Tools {
    # checkToolsState keeps saying "installed" after a revert until something
    # talks to the guest, so ask the guest directly.
    $deadline = (Get-Date).AddMinutes(10)
    while ($true) {
        $r = Invoke-Vmrun 'directoryExistsInGuest', $Vmx, 'C:\Windows' -Guest -AllowFailure
        if ($r -match 'exists') { break }
        if ((Get-Date) -gt $deadline) { throw "can't reach the guest as ${user}: $r" }
        Start-Sleep -Seconds 5
    }
}
Write-Host "reverting to '$Snapshot'"
$null = Invoke-Vmrun 'revertToSnapshot', $Vmx, $Snapshot
$null = Invoke-Vmrun 'start', $Vmx, 'nogui'
Wait-Tools

$stage = Join-Path ([IO.Path]::GetTempPath()) "schizo-vm-$([guid]::NewGuid().ToString('n'))"
$null = New-Item -ItemType Directory -Path $stage
try {
    $files = Get-ChildItem -LiteralPath $repo -Recurse -File | Where-Object { $_.FullName -notmatch '\\(\.git|tests\\vm\\out)\\' }
    $copy = Join-Path $stage 'repo'
    foreach ($f in $files) {
        $dest = Join-Path $copy $f.FullName.Substring($repo.Length + 1)
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest)
        Copy-Item -LiteralPath $f.FullName -Destination $dest
    }
    $pester = Get-Module -ListAvailable Pester | Where-Object { $_.Version -ge [version]'5.5' } | Sort-Object Version | Select-Object -Last 1
    if (-not $pester) { throw 'Pester 5.5 or later is needed on the host; it is copied into the guest.' }
    Copy-Item -Recurse -LiteralPath $pester.ModuleBase -Destination (Join-Path $stage 'Pester')
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath (Join-Path $stage 'payload.zip')

    $null = Invoke-Vmrun 'createDirectoryInGuest', $Vmx, 'C:\schizo-test' -Guest -AllowFailure
    $null = Invoke-Vmrun 'copyFileFromHostToGuest', $Vmx, (Join-Path $stage 'payload.zip'), 'C:\schizo-test\payload.zip' -Guest
    $null = Invoke-Vmrun 'copyFileFromHostToGuest', $Vmx, (Join-Path $PSScriptRoot 'run-guest.ps1'), 'C:\schizo-test\run-guest.ps1' -Guest

    if (-not $Online) {
        # schizo should not need the network; the tests run with it unplugged.
        $null = Invoke-Vmrun 'disconnectNamedDevice', $Vmx, 'ethernet0'
    }

    Write-Host 'running tests in the guest'
    $run = Invoke-Vmrun 'runProgramInGuest', $Vmx, 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'C:\schizo-test\run-guest.ps1' -Guest -AllowFailure

    Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue
    $null = New-Item -ItemType Directory -Path $out
    foreach ($name in 'summary.txt', 'results.xml', 'pester.log', 'schizo-run1.txt', 'schizo-restore1.txt') {
        $null = Invoke-Vmrun 'copyFileFromGuestToHost', $Vmx, "C:\schizo-test\out\$name", (Join-Path $out $name) -Guest -AllowFailure
    }
}
finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    if (-not $KeepRunning) { $null = Invoke-Vmrun 'stop', $Vmx, 'hard' -AllowFailure }
}

$summary = Join-Path $out 'summary.txt'
if (-not (Test-Path $summary)) { throw "no results came back from the guest. vmrun said: $run" }
Get-Content $summary
if ((Get-Content $summary -Raw) -notmatch '(?m)^failed 0\r?$') { exit 1 }
