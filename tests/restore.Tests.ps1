# apply/restore behaviour with real registry targets under a scratch HKCU key
# and a journal in TestDrive. services, tasks and firewall rules need admin and
# are covered by tests\vm.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\schizo.psm1') -Force
    $script:Base = "HKCU\Software\schizo-test-$([guid]::NewGuid().ToString('n'))"
    $script:BasePs = 'Registry::HKEY_CURRENT_USER\' + $Base.Substring(5)
    $script:Me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $script:Machine = @{ Build = 26200; Edition = 'pro'; Found = @{}; OtherUser = $false; UserSid = $Me }

    # restore only acts on journal records under the roots rules may write to.
    # the scratch key isn't one of them, so let the module accept it for this
    # test run only.
    & (Get-Module schizo) { param($Key) $script:AllowedKeys += "$Key\" } $Base

    function New-Rule {
        param([string]$Id, [object[]]$Set, [string]$Level = 'verified')
        @{ Id = $Id; App = 'windows'; Name = $Id; State = 'off'; Level = $Level; Set = $Set }
    }

    function Set-Value { param($Sub, $Name, $Data) $null = New-Item -Path "$BasePs\$Sub" -Force; Set-ItemProperty -Path "$BasePs\$Sub" -Name $Name -Value $Data }
    function Get-Value { param($Sub, $Name) (Get-ItemProperty -Path "$BasePs\$Sub" -ErrorAction SilentlyContinue).$Name }

    # Open-Run insists on an admin-owned folder; this is the same run object
    # without that check, so the journal logic can be tested unelevated.
    function New-TestRun {
        param([string]$Root, [string]$Name)
        $dir = Join-Path $Root "runs\$Name"
        $null = New-Item -ItemType Directory -Force -Path $dir
        $stream = New-Object IO.FileStream (Join-Path $dir 'journal.jsonl'), 'CreateNew', 'Write', 'Read', 4096, 'WriteThrough'
        @{ Root = $Root; Dir = $dir; Stream = $stream; Changes = 0 }
    }

    function Invoke-TestRun {
        param([string]$Root, [string]$Name, [object[]]$Rules)
        $run = New-TestRun $Root $Name
        try { @(Invoke-Schizo -Rulebase @{ Rules = $Rules } -Machine $Machine -Run $run -Aggressive) }
        finally { Close-Run $run }
    }
}

AfterAll {
    Remove-Item -LiteralPath $BasePs -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'applying' {
    BeforeEach {
        Remove-Item -LiteralPath $BasePs -Recurse -Force -ErrorAction SilentlyContinue
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $rule = New-Rule 'test.a' @(@{ Key = "$Base\k"; Value = 'A'; Dword = 0 })
    }

    It 'changes a value and journals the old state first' {
        $r = @(Invoke-TestRun $root 'r1' @($rule))
        $r[0].Status | Should -Be 'changed'
        Get-Value 'k' 'A' | Should -Be 0
        $records = @(Read-Journal (Join-Path $root 'runs\r1\journal.jsonl'))
        $records[0].kind | Should -Be 'change'
        $records[0].before.Exists | Should -BeFalse
        $records[1].kind | Should -Be 'done'
        $records[1].ok | Should -BeTrue
    }

    It 'does nothing the second time' {
        $null = Invoke-TestRun $root 'r1' @($rule)
        $r = @(Invoke-TestRun $root 'r2' @($rule))
        $r[0].Status | Should -Be 'already'
        Test-Path (Join-Path $root 'runs\r2') | Should -BeFalse -Because 'a run with no changes leaves no backup folder'
    }

    It 'changes nothing in audit mode' {
        $r = @(Invoke-Schizo -Rulebase @{ Rules = @($rule) } -Machine $Machine -Run $null)
        $r[0].Status | Should -Be 'would'
        Test-Path "$BasePs\k" | Should -BeFalse
    }

    It 'leaves an existing policy alone' {
        Set-Value 'Policies\p' 'A' 3
        $policy = New-Rule 'test.policy' @(@{ Key = "$Base\Policies\p"; Value = 'A'; Dword = 0 })
        $r = @(Invoke-TestRun $root 'r1' @($policy))
        $r[0].Status | Should -Be 'conflict'
        $r[0].Notes | Should -Match 'already 3'
        Get-Value 'Policies\p' 'A' | Should -Be 3
    }

    It 'updates a policy value that schizo itself set earlier' {
        $old = New-Rule 'test.policy' @(@{ Key = "$Base\Policies\p"; Value = 'A'; Dword = 1 })
        $null = @(Invoke-TestRun $root 'r1' @($old))
        $changes = Read-Changes @(Get-ActiveRuns $root)
        $owned = @{}
        foreach ($id in $changes.Groups.Keys) { $owned[$id] = $changes.Groups[$id].Set }

        $new = New-Rule 'test.policy' @(@{ Key = "$Base\Policies\p"; Value = 'A'; Dword = 0 })
        $run = New-TestRun $root 'r2'
        try { $r = @(Invoke-Schizo -Rulebase @{ Rules = @($new) } -Machine $Machine -Run $run -Owned $owned) }
        finally { Close-Run $run }
        $r[0].Status | Should -Be 'changed'
        Get-Value 'Policies\p' 'A' | Should -Be 0

        $null = Invoke-Restore -Root $root
        Test-Path "$BasePs\Policies\p" | Should -BeFalse -Because 'the value did not exist before the first run'
    }

    It 'overwrites an ordinary setting, keeping the old value for restore' {
        Set-Value 'k' 'A' 7
        @(Invoke-TestRun $root 'r1' @($rule))[0].Status | Should -Be 'changed'
        $records = @(Read-Journal (Join-Path $root 'runs\r1\journal.jsonl'))
        $records[0].before.Data | Should -Be 7
    }

    It 'skips aggressive rules unless asked' {
        $aggr = New-Rule 'test.aggr' @(@{ Key = "$Base\k"; Value = 'B'; Dword = 1 }) 'aggressive'
        $r = @(Invoke-Schizo -Rulebase @{ Rules = @($aggr) } -Machine $Machine -Run $null)
        $r[0].Status | Should -Be 'aggressive'
    }

    It 'skips per-user rules when someone else is signed in' {
        $other = $Machine.Clone(); $other.OtherUser = $true
        $r = @(Invoke-Schizo -Rulebase @{ Rules = @($rule) } -Machine $other -Run $null)
        $r[0].Status | Should -Be 'otheruser'
    }

    It 'stays out when an Unless file exists' {
        $file = Join-Path $TestDrive 'policies.json'
        Set-Content -LiteralPath $file -Value '{}'
        $guarded = New-Rule 'test.guarded' @(@{ Key = "$Base\k"; Value = 'A'; Dword = 0 })
        $guarded.Unless = $file
        $r = @(Invoke-TestRun $root 'r1' @($guarded))
        $r[0].Status | Should -Be 'conflict'
        Test-Path "$BasePs\k" | Should -BeFalse
    }

    It 'keeps going after a target fails, and journals what it did' {
        # HKLM is not writable without admin, which makes a reliable failure.
        if (Test-Admin) { Set-ItResult -Skipped -Because 'needs a non-admin shell to provoke access denied'; return }
        $mixed = New-Rule 'test.mixed' @(
            @{ Key = "$Base\k"; Value = 'A'; Dword = 0 }
            @{ Key = 'HKLM\SOFTWARE\Policies\schizo-test-denied'; Value = 'A'; Dword = 0 }
        )
        $next = New-Rule 'test.next' @(@{ Key = "$Base\k"; Value = 'C'; Dword = 0 })
        $r = @(Invoke-TestRun $root 'r1' @($mixed, $next))
        $r[0].Status | Should -Be 'failed'
        $r[0].Notes -join ' ' | Should -Match 'HKLM\\SOFTWARE\\Policies\\schizo-test-denied'
        $r[1].Status | Should -Be 'changed'
        Get-Value 'k' 'A' | Should -Be 0
        $done = @(Read-Journal (Join-Path $root 'runs\r1\journal.jsonl') | Where-Object { $_.kind -eq 'done' })
        @($done | Where-Object { -not $_.ok }).Count | Should -Be 1
    }
}

Describe 'restoring' {
    BeforeEach {
        Remove-Item -LiteralPath $BasePs -Recurse -Force -ErrorAction SilentlyContinue
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $null = New-Item -Path $BasePs -Force
        Set-Value 'existing' 'B' 'original text'
        $rules = @(
            New-Rule 'test.new' @(@{ Key = "$Base\created\deep"; Value = 'A'; Dword = 1 })
            New-Rule 'test.old' @(@{ Key = "$Base\existing"; Value = 'B'; String = 'schizo' })
        )
    }

    It 'puts back the original state, removing what schizo created' {
        $null = Invoke-TestRun $root 'r1' $rules
        $out = Invoke-Restore -Root $root
        @($out.Items | Where-Object Status -eq 'restored').Count | Should -Be 2
        Test-Path "$BasePs\created" | Should -BeFalse
        Get-Value 'existing' 'B' | Should -Be 'original text'
        (Get-Item "$BasePs\existing").GetValueKind('B') | Should -Be 'String'
        $out.Archived | Should -BeTrue
        Test-Path (Join-Path $root 'restored\r1') | Should -BeTrue
        Test-Path (Join-Path $root 'runs\r1') | Should -BeFalse
    }

    It 'restores the pre-schizo state after several runs' {
        $null = Invoke-TestRun $root 'r1' $rules
        # an update puts one value back, the next run fixes it again
        Set-Value 'existing' 'B' 'original text'
        $null = Invoke-TestRun $root 'r2' $rules
        $null = Invoke-TestRun $root 'r3' $rules
        Test-Path (Join-Path $root 'runs\r3') | Should -BeFalse
        $out = Invoke-Restore -Root $root
        @($out.Items | Where-Object Status -eq 'failed').Count | Should -Be 0
        Get-Value 'existing' 'B' | Should -Be 'original text'
        Test-Path "$BasePs\created" | Should -BeFalse
    }

    It 'restores the first original, not a later one' {
        $null = Invoke-TestRun $root 'r1' $rules
        Set-Value 'existing' 'B' 'changed by an update'
        $null = Invoke-TestRun $root 'r2' $rules
        $null = Invoke-Restore -Root $root
        Get-Value 'existing' 'B' | Should -Be 'original text'
    }

    It 'leaves something alone if it changed after schizo set it' {
        $null = Invoke-TestRun $root 'r1' $rules
        Set-Value 'existing' 'B' 'the user changed it'
        $out = Invoke-Restore -Root $root
        $drift = @($out.Items | Where-Object Status -eq 'drifted')
        $drift.Count | Should -Be 1
        $drift[0].Note | Should -Match 'the user changed it'
        Get-Value 'existing' 'B' | Should -Be 'the user changed it'
        $out.ContainsKey('Archived') | Should -BeFalse
        Test-Path (Join-Path $root 'runs\r1') | Should -BeTrue -Because 'unfinished restores keep the backup'
    }

    It 'restores drifted things with -Force' {
        $null = Invoke-TestRun $root 'r1' $rules
        Set-Value 'existing' 'B' 'the user changed it'
        $null = Invoke-Restore -Root $root
        $out = Invoke-Restore -Root $root -Force
        @($out.Items | Where-Object Status -eq 'restored').Count | Should -Be 1
        Get-Value 'existing' 'B' | Should -Be 'original text'
    }

    It 'changes nothing in audit mode' {
        $null = Invoke-TestRun $root 'r1' $rules
        $out = Invoke-Restore -Root $root -Audit
        @($out.Items | Where-Object Status -eq 'would').Count | Should -Be 2
        Get-Value 'existing' 'B' | Should -Be 'schizo'
        Test-Path (Join-Path $root 'runs\r1') | Should -BeTrue
    }

    It 'is a no-op the second time' {
        $null = Invoke-TestRun $root 'r1' $rules
        $null = Invoke-Restore -Root $root
        $out = Invoke-Restore -Root $root
        $out.Runs.Count | Should -Be 0
    }

    It 'handles a run that died after changing something but before saying so' {
        $run = New-TestRun $root 'r1'
        $t = @{ Type = 'registry'; Key = "$Base\existing"; Value = 'B'; User = $Me }
        $before = Get-RegistryState $t
        Add-JournalRecord $run @{ kind = 'change'; rule = 'test.old'; target = $t; before = $before; after = @{ Exists = $true; Kind = 'String'; Data = 'schizo' } }
        Set-RegistryState $t @{ Exists = $true; Kind = 'String'; Data = 'schizo' }
        # no 'done' record, and a torn half-line at the end
        $bytes = [Text.Encoding]::UTF8.GetBytes('{"kind":"done","rule":"te')
        $run.Stream.Write($bytes, 0, $bytes.Length)
        $run.Stream.Dispose()

        $out = Invoke-Restore -Root $root
        Get-Value 'existing' 'B' | Should -Be 'original text'
        $out.Problems | Should -Match 'unreadable journal line 2'
    }

    It 'handles a run that died before changing anything' {
        $run = New-TestRun $root 'r1'
        $t = @{ Type = 'registry'; Key = "$Base\existing"; Value = 'B'; User = $Me }
        Add-JournalRecord $run @{ kind = 'change'; rule = 'test.old'; target = $t; before = (Get-RegistryState $t); after = @{ Exists = $true; Kind = 'String'; Data = 'schizo' } }
        $run.Stream.Dispose()
        $out = Invoke-Restore -Root $root
        $out.Items[0].Status | Should -Be 'already'
        Get-Value 'existing' 'B' | Should -Be 'original text'
    }

    It 'ignores journal records that point somewhere schizo never goes' {
        $run = New-TestRun $root 'r1'
        Add-JournalRecord $run @{ kind = 'change'; rule = 'evil'; target = @{ Type = 'registry'; Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender'; Value = 'DisableAntiSpyware' }; before = @{ Exists = $true; Kind = 'DWord'; Data = 1 }; after = @{ Exists = $false } }
        Add-JournalRecord $run @{ kind = 'change'; rule = 'evil'; target = @{ Type = 'firewall'; Name = 'Core Networking - DNS (UDP-Out)' }; before = @{ Exists = $false }; after = @{ Exists = $true } }
        Add-JournalRecord $run @{ kind = 'change'; rule = 'evil'; target = @{ Type = 'service'; Service = 'WinDefend' }; before = @{ Exists = $true; Start = 'Disabled' }; after = @{ Exists = $true; Start = 'Automatic' } }
        $run.Stream.Dispose()
        $out = Invoke-Restore -Root $root
        $out.Items.Count | Should -Be 0
        $out.Problems.Count | Should -Be 3
    }
}

Describe 'restoring, the awkward cases' {
    BeforeEach {
        Remove-Item -LiteralPath $BasePs -Recurse -Force -ErrorAction SilentlyContinue
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $null = New-Item -Path $BasePs -Force
        Set-Value 'existing' 'B' 'original text'
        $t = @{ Type = 'registry'; Key = "$Base\existing"; Value = 'B'; User = $Me }
    }

    It 'leaves another user''s settings alone and keeps the backup' {
        $run = New-TestRun $root 'r1'
        $other = $t.Clone(); $other.User = 'S-1-5-21-1-2-3-1001'
        Add-JournalRecord $run @{ kind = 'change'; rule = 'x'; target = $other; before = @{ Exists = $false }; after = @{ Exists = $true; Kind = 'String'; Data = 'original text' } }
        $run.Stream.Dispose()
        $out = Invoke-Restore -Root $root
        $out.Items[0].Status | Should -Be 'otheruser'
        Get-Value 'existing' 'B' | Should -Be 'original text' -Because 'this hive is not the one that was changed'
        $out.ContainsKey('Archived') | Should -BeFalse
    }

    It 'keeps the backup when a journal line could not be read' {
        $run = New-TestRun $root 'r1'
        Add-JournalRecord $run @{ kind = 'change'; rule = 'x'; target = $t; before = (Get-RegistryState $t); after = @{ Exists = $true; Kind = 'String'; Data = 'schizo' } }
        $bytes = [Text.Encoding]::UTF8.GetBytes("garbage
")
        $run.Stream.Write($bytes, 0, $bytes.Length)
        $run.Stream.Dispose()
        Set-RegistryState $t @{ Exists = $true; Kind = 'String'; Data = 'schizo' }
        $out = Invoke-Restore -Root $root
        Get-Value 'existing' 'B' | Should -Be 'original text'
        $out.ContainsKey('Archived') | Should -BeFalse
        Test-Path (Join-Path $root 'runs\r1') | Should -BeTrue
    }

    It 'counts a value from a write that reported failure as schizo''s' {
        $run = New-TestRun $root 'r1'
        Add-JournalRecord $run @{ kind = 'change'; rule = 'x'; target = $t; before = (Get-RegistryState $t); after = @{ Exists = $true; Kind = 'String'; Data = 'first' } }
        Add-JournalRecord $run @{ kind = 'done'; rule = 'x'; target = (Get-TargetId $t); ok = $true }
        Set-RegistryState $t @{ Exists = $true; Kind = 'String'; Data = 'first' }
        Add-JournalRecord $run @{ kind = 'change'; rule = 'x'; target = $t; before = (Get-RegistryState $t); after = @{ Exists = $true; Kind = 'String'; Data = 'second' } }
        Add-JournalRecord $run @{ kind = 'done'; rule = 'x'; target = (Get-TargetId $t); ok = $false; error = 'it broke' }
        $run.Stream.Dispose()
        $out = Invoke-Restore -Root $root
        $out.Items[0].Status | Should -Be 'restored'
        Get-Value 'existing' 'B' | Should -Be 'original text'
    }

    It 'archives newest first, so a failed move leaves the oldest originals' {
        $null = Invoke-TestRun $root 'r1' @(New-Rule 'test.old' @(@{ Key = "$Base\existing"; Value = 'B'; String = 'schizo' }))
        Set-Value 'existing' 'B' 'drift'
        $null = Invoke-TestRun $root 'r2' @(New-Rule 'test.old' @(@{ Key = "$Base\existing"; Value = 'B'; String = 'schizo' }))
        # hold the oldest run's journal open (readable, not deletable) so its
        # folder can't be moved
        $hold = [IO.File]::Open((Join-Path $root 'runs\r1\journal.jsonl'), 'Open', 'Read', 'Read')
        try { $out = Invoke-Restore -Root $root }
        finally { $hold.Dispose() }
        $out.Problems -join ' ' | Should -Match "couldn't move r1"
        Test-Path (Join-Path $root 'runs\r1') | Should -BeTrue
        Test-Path (Join-Path $root 'runs\r2') | Should -BeFalse
        Get-Value 'existing' 'B' | Should -Be 'original text'
    }
}

Describe 'reading back what schizo printed' {
    It 'strips control characters from registry data in messages' {
        Format-State @{ Exists = $true; Kind = 'String'; Data = "a$([char]27)[31mb" } | Should -Be 'a[31mb (String)'
    }
}
Describe 'the backup folder' {
    It 'refuses a folder an ordinary user could have planted' {
        $dir = Join-Path $TestDrive 'planted'
        $null = New-Item -ItemType Directory -Path $dir
        Test-PrivateDir $dir | Should -Not -BeNullOrEmpty
    }

    It 'refuses a junction' {
        $target = Join-Path $TestDrive 'elsewhere'
        $null = New-Item -ItemType Directory -Path $target
        $link = Join-Path $TestDrive 'link'
        $null = New-Item -ItemType Junction -Path $link -Target $target
        Test-PrivateDir $link | Should -Match 'is a link'
    }

    It 'creates the folder readable only by SYSTEM and Administrators' {
        $dir = Join-Path $TestDrive 'private'
        New-PrivateDir $dir
        $acl = Get-Acl -LiteralPath $dir
        $acl.AreAccessRulesProtected | Should -BeTrue
        $sids = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
        $sids | Should -Be @('S-1-5-18', 'S-1-5-32-544')
        # unelevated, the test can no longer open its own folder. as owner it
        # can still rewrite the acl, which lets Pester clean up.
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $null = icacls.exe $dir /grant "*${me}:(OI)(CI)F"
    }
}

Describe 'output hygiene' {
    It 'strips terminal control sequences from untrusted names' {
        Format-Untrusted "Evil$([char]27)[2J App$([char]7)" | Should -Be 'Evil[2J App'
    }

    It 'shortens very long names' {
        (Format-Untrusted ('x' * 200)).Length | Should -Be 60
    }
}
