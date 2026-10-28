BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\schizo.psm1') -Force

    # a minimal valid rule; tests override one field at a time.
    function New-TestRule {
        param([hashtable]$Override = @{})
        $rule = @{
            Id       = 'test.thing'
            App      = 'windows'
            Name     = 'thing'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'Thing'; Dword = 0 }
            Why      = 'because'
            Breaks   = 'nothing'
            Level    = 'verified'
            Source   = 'https://example.com/doc'
            Tested   = 'test'
            Reviewed = '2026-10-27'
        }
        foreach ($k in $Override.Keys) {
            if ($null -eq $Override[$k]) { $rule.Remove($k) } else { $rule[$k] = $Override[$k] }
        }
        $rule
    }

    function Get-Problems {
        param([hashtable]$Rule)
        @(Test-RuleDefinition $Rule @{ windows = @{ Name = 'Windows' } })
    }

    function Write-RuleFile {
        param([string]$Dir, [string]$Name, [string]$Content)
        $null = New-Item -ItemType Directory -Force -Path $Dir
        Set-Content -LiteralPath (Join-Path $Dir $Name) -Value $Content -Encoding ASCII
    }
}

Describe 'the shipped rulebase' {
    It 'loads without problems' {
        { Import-Rules (Join-Path $PSScriptRoot '..\rules') } | Should -Not -Throw
    }
}

Describe 'rule validation' {
    It 'accepts the baseline test rule' {
        Get-Problems (New-TestRule) | Should -BeNullOrEmpty
    }

    It 'rejects a missing <field>' -ForEach @(
        @{ field = 'Why' }, @{ field = 'Source' }, @{ field = 'Breaks' }, @{ field = 'Reviewed' }, @{ field = 'Tested' }, @{ field = 'Level' }
    ) {
        Get-Problems (New-TestRule @{ $field = $null }) | Should -Match "missing $field"
    }

    It 'rejects unknown fields, which are usually typos' {
        Get-Problems (New-TestRule @{ Breks = 'x' }) | Should -Match "unknown field 'Breks'"
    }

    It 'rejects <case>' -ForEach @(
        @{ case = 'a bad id'; o = @{ Id = 'NoDots' }; m = 'should look like' }
        @{ case = 'a long name'; o = @{ Name = 'x' * 35 }; m = 'longer than 34' }
        @{ case = 'an unknown app'; o = @{ App = 'nope' }; m = "unknown app 'nope'" }
        @{ case = 'an unknown level'; o = @{ Level = 'probably' }; m = 'level must be' }
        @{ case = 'a non-https source'; o = @{ Source = 'http://example.com' }; m = 'not an https url' }
        @{ case = 'a bad review date'; o = @{ Reviewed = 'last week' }; m = 'yyyy-MM-dd' }
        @{ case = 'an unknown edition'; o = @{ Edition = 'ultimate' }; m = "unknown edition 'ultimate'" }
        @{ case = 'a Set with two kinds'; o = @{ Set = @{ Key = 'HKCU\x'; Value = 'v'; Dword = 1; Service = 's' } }; m = 'exactly one of' }
        @{ case = 'an HKU path'; o = @{ Set = @{ Key = 'HKU\S-1-5-18\x'; Value = 'v'; Dword = 1 } }; m = 'must start with HKLM' }
        @{ case = 'a wildcard key'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\*'; Value = 'v'; Dword = 1 } }; m = 'looks wrong' }
        @{ case = 'a parent-path key'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\..\SYSTEM'; Value = 'v'; Dword = 1 } }; m = 'looks wrong' }
        @{ case = 'both Dword and String'; o = @{ Set = @{ Key = 'HKCU\x'; Value = 'v'; Dword = 1; String = 'a' } }; m = 'exactly one of Dword or String' }
        @{ case = 'an out of range Dword'; o = @{ Set = @{ Key = 'HKCU\x'; Value = 'v'; Dword = 5000000000 } }; m = 'out of range' }
        @{ case = 'Defender policy'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet'; Value = 'SpynetReporting'; Dword = 0 } }; m = 'does not touch' }
        @{ case = 'Windows Update policy'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'; Value = 'NoAutoUpdate'; Dword = 1 } }; m = 'does not touch' }
        @{ case = 'the UAC policy key'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'; Value = 'EnableLUA'; Dword = 0 } }; m = 'does not touch' }
        @{ case = 'service config through the registry'; o = @{ Set = @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack'; Value = 'Start'; Dword = 4 } }; m = 'not an allowed key' }
        @{ case = 'the same through ControlSet001'; o = @{ Set = @{ Key = 'HKLM\SYSTEM\ControlSet001\Services\WinDefend'; Value = 'Start'; Dword = 4 } }; m = 'not an allowed key' }
        @{ case = 'a Run key'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Value = 'x'; String = 'C:\x.exe' } }; m = 'not an allowed key' }
        @{ case = 'an IFEO debugger'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\sethc.exe'; Value = 'Debugger'; String = 'cmd.exe' } }; m = 'not an allowed key' }
        @{ case = 'a Run key under the policy keys'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run'; Value = 'x'; String = 'C:\x.exe' } }; m = 'not an allowed key' }
        @{ case = 'a forced extension install'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome\ExtensionInstallForcelist'; Value = '1'; String = 'abc' } }; m = 'not an allowed key' }
        @{ case = 'PATH'; o = @{ Set = @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; Value = 'Path'; String = 'C:\evil' } }; m = 'only telemetry environment variables' }
        @{ case = 'PSModulePath'; o = @{ Set = @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; Value = 'PSModulePath'; String = 'C:\evil' } }; m = 'only telemetry environment variables' }
        @{ case = 'SmartScreen in Edge'; o = @{ Set = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'SmartScreenEnabled'; Dword = 0 } }; m = 'does not touch' }
        @{ case = 'an unknown %variable%'; o = @{ Set = @{ BlockOutbound = '%TEMP%\x.exe' } }; m = 'known folder' }
        @{ case = 'a .. in a program path'; o = @{ Set = @{ BlockOutbound = 'C:\Program Files\..\Windows\x.exe' } }; m = 'wildcards or \.\.' }
        @{ case = 'the Defender service'; o = @{ Set = @{ Service = 'WinDefend'; Start = 'Disabled' } }; m = 'does not touch the WinDefend' }
        @{ case = 'Windows Update'; o = @{ Set = @{ Service = 'wuauserv'; Start = 'Disabled' } }; m = 'does not touch' }
        @{ case = 'a service name with a quote'; o = @{ Set = @{ Service = 'a" b'; Start = 'Disabled' } }; m = 'bad service name' }
        @{ case = 'enabling a service'; o = @{ Set = @{ Service = 'x'; Start = 'Automatic' } }; m = 'Disabled or Manual' }
        @{ case = 'a scheduled task, which isn''t supported'; o = @{ Set = @{ Task = '\x\y'; Enabled = $false } }; m = 'exactly one of Key, Service, BlockOutbound' }
        @{ case = 'a relative firewall program'; o = @{ Set = @{ BlockOutbound = 'bin\x.exe' } }; m = 'must start with a drive' }
        @{ case = 'a wildcard firewall program'; o = @{ Set = @{ BlockOutbound = 'C:\Program Files\*\x.exe' } }; m = 'wildcards' }
        @{ case = 'a relative Unless'; o = @{ Unless = 'policies.json' }; m = 'Unless must start with' }
    ) {
        (Get-Problems (New-TestRule $o)) -join "`n" | Should -Match $m
    }

    It 'requires advice rules to change nothing' {
        $r = @{ Id = 'test.advice'; App = 'windows'; Name = 'x'; Advice = 'click here'; Why = 'y'; Source = 'https://example.com'; Reviewed = '2026-10-27'; Set = @{ Key = 'HKCU\x'; Value = 'v'; Dword = 1 } }
        Get-Problems $r | Should -Match "has Advice, so it can't have Set"
        $r.Remove('Set')
        Get-Problems $r | Should -BeNullOrEmpty
    }
}

Describe 'conflicts' {
    It 'rejects two rules that set the same value' {
        $a = New-TestRule @{ Id = 'test.a' }
        $b = New-TestRule @{ Id = 'test.b'; Set = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'Thing'; Dword = 1 } }
        @(Find-RuleConflicts @($a, $b)) | Should -Match "'test.a' and 'test.b' both change"
    }

    It 'is not fooled by case' {
        $a = New-TestRule @{ Id = 'test.a' }
        $b = New-TestRule @{ Id = 'test.b'; Set = @{ Key = 'hklm\software\policies\microsoft\EDGE'; Value = 'thing'; Dword = 0 } }
        @(Find-RuleConflicts @($a, $b)).Count | Should -Be 1
    }

    It 'allows the same value on editions that can never both match' {
        $a = New-TestRule @{ Id = 'test.a'; Edition = 'home', 'pro' }
        $b = New-TestRule @{ Id = 'test.b'; Edition = 'enterprise'; Set = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'Thing'; Dword = 1 } }
        @(Find-RuleConflicts @($a, $b)) | Should -BeNullOrEmpty
    }

    It 'rejects overlapping editions' {
        $a = New-TestRule @{ Id = 'test.a'; Edition = 'home', 'pro' }
        $b = New-TestRule @{ Id = 'test.b'; Edition = 'pro'; Set = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'Thing'; Dword = 1 } }
        @(Find-RuleConflicts @($a, $b)).Count | Should -Be 1
    }

    It 'rejects a rule that sets one value twice' {
        $a = New-TestRule @{ Set = @(@{ Key = 'HKCU\x'; Value = 'v'; Dword = 0 }, @{ Key = 'HKCU\x'; Value = 'v'; Dword = 1 }) }
        @(Find-RuleConflicts @($a)) | Should -Match 'twice'
    }

    It 'rejects the same service in two rules' {
        $a = New-TestRule @{ Id = 'test.a'; Set = @{ Service = 'Foo'; Start = 'Disabled' } }
        $b = New-TestRule @{ Id = 'test.b'; Set = @{ Service = 'foo'; Start = 'Manual' } }
        @(Find-RuleConflicts @($a, $b)).Count | Should -Be 1
    }
}

Describe 'loading rule files' {
    BeforeEach {
        $dir = Join-Path $TestDrive ([guid]::NewGuid())
    }

    It 'refuses a rule file that tries to run code' {
        Write-RuleFile $dir 'evil.psd1' "@{ Rules = @( @{ Id = (Get-Date).ToString() } ) }"
        { Import-Rules $dir } | Should -Throw '*evil.psd1*'
    }

    It 'refuses duplicate ids across files' {
        $one = "@{ Rules = @( @{ Id='x.same'; App='windows'; Name='n'; State='s'; Set=@{ Key='HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value='v'; Dword=1 }; Why='w'; Breaks='b'; Level='verified'; Source='https://e.com'; Tested='t'; Reviewed='2026-01-01' } ) }"
        $two = $one.Replace("Key='HKLM\SOFTWARE\Policies\Microsoft\Edge'", "Key='HKLM\SOFTWARE\Policies\Google\Chrome'")
        Write-RuleFile $dir 'a.psd1' $one
        Write-RuleFile $dir 'b.psd1' $two
        { Import-Rules $dir } | Should -Throw "*duplicate rule id 'x.same'*"
    }

    It 'refuses an app defined twice' {
        Write-RuleFile $dir 'a.psd1' "@{ Apps = @{ foo = @{ Name = 'Foo'; File = 'C:\foo.exe' } } }"
        Write-RuleFile $dir 'b.psd1' "@{ Apps = @{ foo = @{ Name = 'Foo'; File = 'C:\foo.exe' } } }"
        { Import-Rules $dir } | Should -Throw "*app 'foo' is defined twice*"
    }

    It 'reports every problem at once, not just the first' {
        Write-RuleFile $dir 'a.psd1' "@{ Rules = @( @{ Id = 'BAD' }, @{ Id = 'x.y'; App = 'nope' } ) }"
        $err = $null
        try { Import-Rules $dir } catch { $err = $_.Exception.Message }
        $err | Should -Match "rule id 'BAD'"
        $err | Should -Match "unknown app 'nope'"
    }

    It 'refuses an empty folder' {
        $null = New-Item -ItemType Directory -Path $dir
        { Import-Rules $dir } | Should -Throw '*no rule files*'
    }

    It 'puts windows rules first' {
        Write-RuleFile $dir 'aaa.psd1' "@{ Apps = @{ foo = @{ Name = 'Foo'; File = 'C:\foo.exe' } }; Rules = @( @{ Id='foo.a'; App='foo'; Name='n'; State='s'; Set=@{ Key='HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value='v'; Dword=1 }; Why='w'; Breaks='b'; Level='verified'; Source='https://e.com'; Tested='t'; Reviewed='2026-01-01' } ) }"
        Write-RuleFile $dir 'windows.psd1' "@{ Rules = @( @{ Id='windows.a'; App='windows'; Name='n'; State='s'; Set=@{ Key='HKLM\SOFTWARE\Policies\Google\Chrome'; Value='v'; Dword=1 }; Why='w'; Breaks='b'; Level='verified'; Source='https://e.com'; Tested='t'; Reviewed='2026-01-01' } ) }"
        (Import-Rules $dir).Rules[0].Id | Should -Be 'windows.a'
    }
}

Describe 'which rules apply' {
    BeforeAll {
        $machine = @{ Build = 26200; Edition = 'pro'; Found = @{ foo = @{ Dir = 'C:\foo' } } }
    }

    It 'skips rules for software that is not installed' {
        Test-RuleApplies (New-TestRule @{ App = 'bar' }) $machine | Should -BeFalse
        Test-RuleApplies (New-TestRule @{ App = 'foo' }) $machine | Should -BeTrue
    }

    It 'respects editions' {
        Test-RuleApplies (New-TestRule @{ Edition = 'enterprise' }) $machine | Should -BeFalse
        Test-RuleApplies (New-TestRule @{ Edition = 'home', 'pro' }) $machine | Should -BeTrue
    }

    It 'respects MinBuild' {
        Test-RuleApplies (New-TestRule @{ MinBuild = 26300 }) $machine | Should -BeFalse
        Test-RuleApplies (New-TestRule @{ MinBuild = 26100 }) $machine | Should -BeTrue
    }

    It 'expands {dir} for firewall targets and skips exes that are not there' {
        $exe = Join-Path $TestDrive 'app\real.exe'
        $null = New-Item -ItemType File -Force -Path $exe
        $m = @{ Found = @{ foo = @{ Dir = (Join-Path $TestDrive 'app') } } }
        $rule = New-TestRule @{ App = 'foo'; Set = @(@{ BlockOutbound = '{dir}\real.exe' }, @{ BlockOutbound = '{dir}\missing.exe' }) }
        $targets = @(Resolve-RuleTargets $rule $m)
        $targets.Count | Should -Be 1
        $targets[0].Program | Should -Be $exe
        $targets[0].Name | Should -Be 'schizo-test.thing-real.exe'
    }
}
