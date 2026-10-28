# runs INSIDE a disposable Windows VM, elevated. it applies every rule,
# including the aggressive ones, then restores, and compares against the
# state captured before the first run. never run this on a machine you care
# about. tests\vm\Invoke-VmTest.ps1 is the way in. it is deliberately not
# named *.Tests.ps1, so Invoke-Pester .\tests never picks it up.

BeforeDiscovery {
    if (-not $env:SCHIZO_DISPOSABLE_VM) { throw 'refusing to run: set SCHIZO_DISPOSABLE_VM=1, and only inside a throwaway VM.' }
}

BeforeAll {
    $repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
    Import-Module (Join-Path $repo 'lib\schizo.psm1') -Force
    $stateRoot = Join-Path $env:ProgramData 'schizo'

    function Invoke-Script {
        param([string]$Name, [string[]]$Arguments = @())
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo $Name) @Arguments 2>&1
        @{ Code = $LASTEXITCODE; Text = ($out | Out-String) }
    }

    $rulebase = Import-Rules (Join-Path $repo 'rules')
    $machine = Get-Machine $rulebase.Apps
    $targets = @(foreach ($rule in $rulebase.Rules) {
            if ($rule.Advice -or -not (Test-RuleApplies $rule $machine)) { continue }
            foreach ($t in Resolve-RuleTargets $rule $machine) { $t.Rule = $rule.Id; $t }
        })

    function Get-Snapshot {
        $snap = @{}
        foreach ($t in $targets) { $snap[(Get-TargetId $t)] = Get-TargetState $t }
        $snap
    }

    # reg.exe as an independent reader, so the tests don't only check
    # schizo's registry code with schizo's registry code.
    function Get-RegExe {
        param([hashtable]$Target)
        $out = & reg.exe query $Target.Key /v $Target.Value /reg:64 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        $line = $out | Where-Object { $_ -match "^\s+$([regex]::Escape($Target.Value))\s+REG_" } | Select-Object -First 1
        ($line -split '\s{2,}|\t', 4 | Where-Object { $_ })[-1].Trim()
    }

    function Assert-Original {
        param([hashtable]$Snapshot)
        foreach ($t in $targets) {
            $id = Get-TargetId $t
            $now = Get-TargetState $t
            $was = $Snapshot[$id]
            if ([bool]$was.Exists -ne [bool]$now.Exists -or -not (Test-StateMatch $t.Type $now $was)) {
                throw "$id is $(Format-State $now), was $(Format-State $was)"
            }
            if ($t.Type -eq 'registry' -and $was.Missing) {
                if (Test-Path -LiteralPath ('Registry::' + $was.Missing.Replace('HKLM', 'HKEY_LOCAL_MACHINE').Replace('HKCU', 'HKEY_CURRENT_USER'))) {
                    throw "$($was.Missing) was created by schizo and is still there"
                }
            }
        }
    }

    Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
    $original = Get-Snapshot
}

Describe 'the vm' {
    It 'is elevated' { Test-Admin | Should -BeTrue }
    It 'has rules to test' { $targets.Count | Should -BeGreaterThan 20 }
    It 'has the test apps' {
        $machine.Found.Keys | Should -Contain '7zip'
        $machine.Found.Keys | Should -Contain 'edge'
    }
}

Describe 'apply, apply again, restore' {
    It 'applies everything' {
        $r = Invoke-Script 'schizo.ps1' '-Aggressive'
        $r.Text | Out-File (Join-Path $env:TEMP 'schizo-run1.txt')
        $r.Code | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match '\n0 failed'
        $r.Text | Should -Match 'backup:'
    }

    It 'leaves every target the way its rule wants it' {
        foreach ($t in $targets) {
            Test-StateMatch $t.Type (Get-TargetState $t) $t.Want | Should -BeTrue -Because (Get-TargetId $t)
        }
    }

    It 'agrees with reg.exe' {
        foreach ($t in @($targets | Where-Object Type -eq 'registry')) {
            $want = if ($t.Want.Kind -eq 'DWord') { '0x{0:x}' -f [long]$t.Want.Data } else { [string]$t.Want.Data }
            Get-RegExe $t | Should -Be $want -Because (Get-TargetId $t)
        }
    }

    It 'agrees with sc.exe and the firewall' {
        foreach ($t in @($targets | Where-Object Type -eq 'service')) {
            (& sc.exe qc $t.Service | Out-String) | Should -Match 'START_TYPE\s+:\s+4\s+DISABLED'
        }
        $fw = @(Get-NetFirewallRule -Group 'schizo' -ErrorAction SilentlyContinue)
        $fw.Count | Should -Be @($targets | Where-Object Type -eq 'firewall').Count
        foreach ($r in $fw) {
            $r.Direction | Should -Be 'Outbound'
            $r.Action | Should -Be 'Block'
            ($r | Get-NetFirewallApplicationFilter).Program | Should -Match '\\7z(FM|G)?\.exe$'
        }
    }

    It 'keeps the backup folder admin-only' {
        Test-PrivateDir $stateRoot | Should -BeNullOrEmpty
        $acl = Get-Acl $stateRoot
        $acl.AreAccessRulesProtected | Should -BeTrue
        @($acl.Access | Where-Object { $_.IdentityReference -match 'Users|Everyone|Authenticated' }).Count | Should -Be 0
    }

    It 'changes nothing the second time' {
        $runsBefore = @(Get-ActiveRuns $stateRoot).Count
        $r = Invoke-Script 'schizo.ps1' '-Aggressive'
        $r.Code | Should -Be 0
        $r.Text | Should -Match '\n0 changed'
        @(Get-ActiveRuns $stateRoot).Count | Should -Be $runsBefore
    }

    It 'restores the original state' {
        $r = Invoke-Script 'restore.ps1'
        $r.Text | Out-File (Join-Path $env:TEMP 'schizo-restore1.txt')
        $r.Code | Should -Be 0 -Because $r.Text
        $r.Text | Should -Match '\n0 failed'
        Assert-Original $original
        @(Get-NetFirewallRule -Group 'schizo' -ErrorAction SilentlyContinue).Count | Should -Be 0
        @(Get-ActiveRuns $stateRoot).Count | Should -Be 0
    }

    It 'restores the original after apply, update-style revert, apply, restore' {
        (Invoke-Script 'schizo.ps1' '-Aggressive').Code | Should -Be 0
        # what an update does: put one thing back
        $svc = @($targets | Where-Object Type -eq 'service')[0]
        Set-TargetState $svc $original[(Get-TargetId $svc)]
        $r = Invoke-Script 'schizo.ps1' '-Aggressive'
        $r.Text | Should -Match '\n1 changed'
        (Invoke-Script 'restore.ps1').Code | Should -Be 0
        Assert-Original $original
    }
}

Describe 'drift' {
    It 'leaves changes made after schizo alone, and -Force restores them' {
        (Invoke-Script 'schizo.ps1' '-Aggressive').Code | Should -Be 0
        $edge = @($targets | Where-Object { $_.Type -eq 'registry' -and $_.Value -eq 'DiagnosticData' })[0]
        Set-TargetState $edge @{ Exists = $true; Kind = 'DWord'; Data = 2 }

        $r = Invoke-Script 'restore.ps1'
        $r.Text | Should -Match '1 changed since schizo set them'
        (Get-TargetState $edge).Data | Should -Be 2
        @(Get-ActiveRuns $stateRoot).Count | Should -Be 1

        $r = Invoke-Script 'restore.ps1' '-Force'
        $r.Code | Should -Be 0
        Assert-Original $original
    }
}

Describe 'things that belong to someone else' {
    BeforeAll {
        $policy = @{ Type = 'registry'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Value = 'AllowTelemetry' }
        $policyBefore = Get-TargetState $policy
    }

    It 'does not overwrite an existing policy, and restore does not touch it' {
        Set-TargetState $policy @{ Exists = $true; Kind = 'DWord'; Data = 3 }
        $r = Invoke-Script 'schizo.ps1'
        $r.Text | Should -Match 'diagnostic data\s+left alone'
        $r.Text | Should -Match 'AllowTelemetry is already 3'
        (Get-TargetState $policy).Data | Should -Be 3
        (Invoke-Script 'restore.ps1').Code | Should -Be 0
        (Get-TargetState $policy).Data | Should -Be 3
    }

    It 'leaves a firewall rule it did not create alone' {
        $exe = @($targets | Where-Object Type -eq 'firewall')[0].Program
        $null = New-NetFirewallRule -Name 'someone-elses-rule' -DisplayName 'mine' -Direction Outbound -Action Block -Program $exe
        (Invoke-Script 'schizo.ps1').Code | Should -Be 0
        (Invoke-Script 'restore.ps1').Code | Should -Be 0
        Get-NetFirewallRule -Name 'someone-elses-rule' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Remove-NetFirewallRule -Name 'someone-elses-rule'
    }

    AfterAll {
        Set-TargetState $policy $policyBefore
    }
}

Describe 'a write windows refuses' {
    # build 26300 blocks writes to this one value, and deleting its key, for
    # everyone but group policy. that makes it a real partial failure: the
    # key gets created, the value doesn't, and the key can't be removed again.
    It 'reports the failure and the leftover key instead of claiming success' {
        $dsh = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Dsh'
        if (Test-Path $dsh) { Set-ItResult -Skipped -Because 'the Dsh key already exists here'; return }
        # no shipped rule writes here any more, so let this session's module accept it.
        & (Get-Module schizo) { $script:AllowedKeys += 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' }
        $rule = @{ Id = 'test.widgets'; App = 'windows'; Name = 'widgets'; State = 'off'; Level = 'verified'
            Set = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Dsh'; Value = 'AllowNewsAndInterests'; Dword = 0 } }
        $run = Open-Run $stateRoot
        try { $r = @(Invoke-Schizo -Rulebase @{ Rules = @($rule) } -Machine $machine -Run $run) }
        finally { Close-Run $run }
        if ($r[0].Status -eq 'changed') {
            $null = Invoke-Restore -Root $stateRoot
            Set-ItResult -Inconclusive -Because 'this build lets an administrator write the value'
            return
        }
        $r[0].Status | Should -Be 'failed'
        if (Test-Path $dsh) {
            $r[0].Notes -join ' ' | Should -Match 'access denied \(putting it back failed too: access denied\)'
            $out = Invoke-Restore -Root $stateRoot
            @($out.Items | Where-Object Status -eq 'failed').Count | Should -Be 1
            $out.ContainsKey('Archived') | Should -BeFalse -Because 'an unfinished restore keeps its backup'
        }
        else {
            $out = Invoke-Restore -Root $stateRoot
            $out.Archived | Should -BeTrue
        }
        Remove-Item -LiteralPath $stateRoot -Recurse -Force
    }
}
Describe 'refusals' {
    It 'refuses a backup folder it does not trust' {
        Remove-Item -LiteralPath $stateRoot -Recurse -Force -ErrorAction SilentlyContinue
        $null = New-Item -ItemType Directory -Path $stateRoot
        # what a standard user could have done: give everyone write access
        $null = icacls.exe $stateRoot /grant '*S-1-5-32-545:(OI)(CI)M'
        $r = Invoke-Script 'schizo.ps1'
        $r.Code | Should -Be 2
        $r.Text | Should -Match "won't use"
        $r = Invoke-Script 'restore.ps1'
        $r.Code | Should -Be 2
        Remove-Item -LiteralPath $stateRoot -Recurse -Force
    }

    It 'notices generic write rights on inheritable entries too' {
        $null = New-Item -ItemType Directory -Path $stateRoot
        $null = icacls.exe $stateRoot /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)(IO)(GA)'
        $r = Invoke-Script 'schizo.ps1'
        $r.Code | Should -Be 2
        $r.Text | Should -Match "won't use"
        Remove-Item -LiteralPath $stateRoot -Recurse -Force
    }

    It 'refuses to run twice at once' {
        $null = Get-StateRoot $stateRoot -Create
        $lock = Lock-StateRoot $stateRoot
        try {
            $r = Invoke-Script 'schizo.ps1'
            $r.Code | Should -Be 2
            $r.Text | Should -Match 'another schizo or restore is running'
        }
        finally { $lock.Dispose() }
    }

    It 'leaves the machine as it found it' {
        Assert-Original $original
    }
}
