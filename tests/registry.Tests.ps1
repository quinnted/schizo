# runs against the real registry, but only under HKCU\Software\schizo-test-*,
# which the tests create and delete. nothing here needs admin.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\schizo.psm1') -Force
    $script:Base = "HKCU\Software\schizo-test-$([guid]::NewGuid().ToString('n'))"
    $script:BasePs = 'Registry::HKEY_CURRENT_USER\' + $Base.Substring(5)

    function New-Target {
        param([string]$Sub, [string]$Value = 'v')
        $key = $Base
        if ($Sub) { $key += "\$Sub" }
        @{ Type = 'registry'; Key = $key; Value = $Value }
    }
}

AfterAll {
    Remove-Item -LiteralPath $BasePs -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'reading registry state' {
    It 'reports the highest missing key' {
        $null = New-Item -Path $BasePs -Force
        $s = Get-RegistryState (New-Target 'a\b\c')
        $s.Exists | Should -BeFalse
        $s.Missing | Should -Be "$Base\a"
    }

    It 'says nothing about keys when only the value is missing' {
        $null = New-Item -Path "$BasePs\present" -Force
        $s = Get-RegistryState (New-Target 'present')
        $s.Exists | Should -BeFalse
        $s.ContainsKey('Missing') | Should -BeFalse
    }

    It 'round-trips <kind>' -ForEach @(
        @{ kind = 'DWord'; data = [long]1 }
        @{ kind = 'DWord'; data = [long]4294967295 }
        @{ kind = 'QWord'; data = [long]-5 }
        @{ kind = 'String'; data = 'plain' }
        @{ kind = 'ExpandString'; data = '%SystemRoot%\x' }
        @{ kind = 'MultiString'; data = [string[]]@('one', 'two') }
        @{ kind = 'MultiString'; data = [string[]]@('single') }
        @{ kind = 'Binary'; data = 'AAEC/w==' }
    ) {
        $t = New-Target 'kinds' "$kind-$($data.GetHashCode())"
        $want = @{ Exists = $true; Kind = $kind; Data = $data }
        Set-RegistryState $t $want
        $got = Get-RegistryState $t
        Test-StateMatch 'registry' $got $want | Should -BeTrue
        $got.Kind | Should -Be $kind
    }

    It 'does not expand environment variables in ExpandString values' {
        $t = New-Target 'kinds' 'expand'
        Set-RegistryState $t @{ Exists = $true; Kind = 'ExpandString'; Data = '%TEMP%' }
        (Get-RegistryState $t).Data | Should -Be '%TEMP%'
    }

    It 'survives a json round trip, the way the journal stores it' {
        $t = New-Target 'kinds' 'json'
        Set-RegistryState $t @{ Exists = $true; Kind = 'MultiString'; Data = [string[]]@('x') }
        $state = Get-RegistryState $t
        $back = ConvertTo-Hashtable ($state | ConvertTo-Json -Compress -Depth 5 | ConvertFrom-Json)
        Test-StateMatch 'registry' $back $state | Should -BeTrue
    }

    It 'marks value types it cannot back up' {
        $null = New-Item -Path "$BasePs\odd" -Force
        $k = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(($Base.Substring(5) + '\odd'), $true)
        $k.SetValue('none', [byte[]]@(), [Microsoft.Win32.RegistryValueKind]::None)
        $k.Dispose()
        (Get-RegistryState (New-Target 'odd' 'none')).Kind | Should -Be 'Unsupported'
    }
}

Describe 'comparing states' {
    It 'compares strings exactly: <case>' -ForEach @(
        @{ case = 'soft hyphen'; a = "a$([char]0xAD)b"; b = 'ab' }
        @{ case = 'case'; a = 'Off'; b = 'off' }
        @{ case = 'nul'; a = "a$([char]0)"; b = 'a' }
    ) {
        Test-StateMatch 'registry' @{ Exists = $true; Kind = 'String'; Data = $a } @{ Exists = $true; Kind = 'String'; Data = $b } | Should -BeFalse
    }

    It 'compares multi-strings element by element' {
        $ab = @{ Exists = $true; Kind = 'MultiString'; Data = [string[]]@('a', 'b') }
        Test-StateMatch 'registry' $ab @{ Exists = $true; Kind = 'MultiString'; Data = [string[]]@('ab') } | Should -BeFalse
        Test-StateMatch 'registry' $ab @{ Exists = $true; Kind = 'MultiString'; Data = [string[]]@('a', 'b') } | Should -BeTrue
        Test-StateMatch 'registry' @{ Exists = $true; Kind = 'MultiString'; Data = [string[]]@('') } @{ Exists = $true; Kind = 'MultiString'; Data = [string[]]@() } | Should -BeFalse
    }

    It 'does not confuse a DWORD 1 with a string 1' {
        Test-StateMatch 'registry' @{ Exists = $true; Kind = 'String'; Data = '1' } @{ Exists = $true; Kind = 'DWord'; Data = 1 } | Should -BeFalse
    }
}
Describe 'removing values' {
    It 'removes the keys it created, and only those' {
        $null = New-Item -Path "$BasePs\keep" -Force
        $t = New-Target 'keep\made\deeper'
        $before = Get-RegistryState $t
        Set-RegistryState $t @{ Exists = $true; Kind = 'DWord'; Data = 1 }
        Set-RegistryState $t $before
        Test-Path "$BasePs\keep\made" | Should -BeFalse
        Test-Path "$BasePs\keep" | Should -BeTrue
    }

    It 'leaves a created key alone if something else moved in' {
        $t = New-Target 'shared'
        $before = Get-RegistryState $t
        Set-RegistryState $t @{ Exists = $true; Kind = 'DWord'; Data = 1 }
        Set-ItemProperty -Path "$BasePs\shared" -Name 'someone-else' -Value 1
        Set-RegistryState $t $before
        Test-Path "$BasePs\shared" | Should -BeTrue
        (Get-ItemProperty "$BasePs\shared").'someone-else' | Should -Be 1
    }

    It 'is fine removing a value that is already gone' {
        { Set-RegistryState (New-Target 'nothing-here') @{ Exists = $false } } | Should -Not -Throw
    }
}
