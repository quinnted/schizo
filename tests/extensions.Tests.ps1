# fixtures shaped like a real chrome profile: Extensions\<id>\<version>\ plus
# the profile's prefs, which are what chrome itself trusts.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\schizo.psm1') -Force

    function Write-Json {
        param([string]$Path, $Object)
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
        [IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
    }

    function New-Extension {
        param([string]$Dir, [string]$Id, [string]$Version, [string]$Name, [string[]]$Hosts = @('<all_urls>'), [string[]]$Permissions = @())
        Write-Json "$Dir\Extensions\$Id\$Version\manifest.json" @{ name = $Name; manifest_version = 3; host_permissions = $Hosts; permissions = $Permissions }
    }

    function Write-Settings {
        param([string]$Dir, [hashtable]$Settings, [string]$File = 'Secure Preferences')
        Write-Json "$Dir\$File" @{ extensions = @{ settings = $Settings } }
    }

    $a = 'a' * 32; $b = 'b' * 32; $c = 'c' * 32; $d = 'd' * 32; $e = 'e' * 32
}

Describe 'which extensions are installed' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $default = Join-Path $root 'Default'
    }

    It 'reports the version the profile says is installed, once' {
        New-Extension $default $a '1.0_0' 'Old Name'
        New-Extension $default $a '2.0_0' 'Tampermonkey'
        Write-Settings $default @{ $a = @{ location = 1; path = "$a\2.0_0" } }
        $found = @(Get-ChromiumExtensions 'chrome' $root)
        $found.Count | Should -Be 1
        $found[0].Name | Should -Be 'Tampermonkey'
    }

    It 'counts an extension once when both prefs files list it' {
        New-Extension $default $a '1.0_0' 'Tampermonkey'
        Write-Settings $default @{ $a = @{ location = 1; path = "$a\1.0_0" } } 'Preferences'
        Write-Settings $default @{ $a = @{ location = 1; path = "$a\1.0_0" } }
        @(Get-ChromiumExtensions 'chrome' $root).Count | Should -Be 1
    }

    It 'ignores leftovers of removed extensions' {
        New-Extension $default $a '1.0_0' 'Still Here'
        New-Extension $default $b '1.0_0' 'Removed Last Week'
        Write-Settings $default @{ $a = @{ location = 1; path = "$a\1.0_0" } }
        @(Get-ChromiumExtensions 'chrome' $root | ForEach-Object { $_.Name }) | Should -Be @('Still Here')
    }

    It 'skips the pieces of the browser itself' {
        New-Extension $default $a '1.0_0' 'Component'
        New-Extension $default $b '1.0_0' 'External Component'
        Write-Settings $default @{ $a = @{ location = 5; path = "$a\1.0_0" }; $b = @{ location = 10; path = "$b\1.0_0" } }
        @(Get-ChromiumExtensions 'chrome' $root) | Should -BeNullOrEmpty
    }

    It 'does not follow an extension path onto a network share' {
        Write-Settings $default @{ $a = @{ location = 4; path = '\\attacker\share\ext' } }
        @(Get-ChromiumExtensions 'chrome' $root) | Should -BeNullOrEmpty
    }

    It 'falls back to the folders, without claiming a source, when there are no prefs' {
        New-Extension $default $a '1.0_0' 'No Prefs'
        $found = @(Get-ChromiumExtensions 'chrome' $root)
        $found[0].Source | Should -Be 'unknown'
    }

    It 'notices disabled extensions, in both formats chrome has used' {
        New-Extension $default $a '1.0_0' 'List'
        New-Extension $default $b '1.0_0' 'Bitmask'
        New-Extension $default $c '1.0_0' 'Enabled'
        Write-Settings $default @{
            $a = @{ location = 1; path = "$a\1.0_0"; disable_reasons = @(1) }
            $b = @{ location = 1; path = "$b\1.0_0"; disable_reasons = 1 }
            $c = @{ location = 1; path = "$c\1.0_0"; disable_reasons = @() }
        }
        $found = @(Get-ChromiumExtensions 'chrome' $root)
        ($found | Where-Object Name -eq 'List').Disabled | Should -BeTrue
        ($found | Where-Object Name -eq 'Bitmask').Disabled | Should -BeTrue
        ($found | Where-Object Name -eq 'Enabled').Disabled | Should -BeFalse
    }
}

Describe 'where an extension came from' {
    BeforeAll {
        $root = Join-Path $TestDrive 'sources'
        $p = Join-Path $root 'Profile 7'
        New-Extension $p $a '1.0_0' 'Tampermonkey' -Permissions 'webRequestBlocking'
        New-Extension $p $b '1.0_0' 'Lightspeed Filter Agent' -Permissions 'history', 'proxy', 'management'
        New-Extension $p $c '1.0_0' 'Phish Alert Button' -Hosts @('https://mail.example.com/*')
        New-Extension $p $d '1.0_0' 'Single Sign On'
        New-Extension $p $e '1.0_0' 'Cached Policy Install'
        Write-Settings $p @{
            $a = @{ location = 1; path = "$a\1.0_0" }
            $b = @{ location = 7; path = "$b\1.0_0" }
            $c = @{ location = 7; path = "$c\1.0_0" }
            $d = @{ location = 6; path = "$d\1.0_0"; was_installed_by_default = $false }
            $e = @{ location = 9; path = "$e\1.0_0" }
        }
        $found = @(Get-ChromiumExtensions 'chrome' $root)
        function Get-Found([string]$Name) { $found | Where-Object Name -eq $Name }
    }

    It 'treats a store install as the user''s' {
        (Get-Found 'Tampermonkey').Source | Should -Be 'user'
        (Get-Found 'Tampermonkey').Facts | Should -Be @('all sites', 'intercepts requests')
    }

    It 'recognises force-installed extensions as policy installs' {
        (Get-Found 'Lightspeed Filter Agent').Source | Should -Be 'policy'
        (Get-Found 'Cached Policy Install').Source | Should -Be 'policy'
    }

    It 'still knows a managed extension without broad access is managed' {
        $x = Get-Found 'Phish Alert Button'
        $x.Source | Should -Be 'policy'
        $x.Facts | Should -BeNullOrEmpty
    }

    It 'does not call an extension managed because of what it can do' {
        (Get-Found 'Tampermonkey').Source | Should -Not -Be 'policy'
    }

    It 'notes extensions another program put there' {
        (Get-Found 'Single Sign On').Source | Should -Be 'other program'
    }
}

Describe 'firefox' {
    It 'recognises add-ons the policy engine installed' {
        $ff = Join-Path $TestDrive 'ffsrc\Mozilla\Firefox'
        $null = New-Item -ItemType Directory -Force -Path "$ff\Profiles\x.default"
        Set-Content -LiteralPath "$ff\profiles.ini" -Value "[Profile0]`nIsRelative=1`nPath=Profiles/x.default"
        Write-Json "$ff\Profiles\x.default\extensions.json" @{ addons = @(
                @{ id = 'mine@x'; type = 'extension'; location = 'app-profile'; active = $true; defaultLocale = @{ name = 'Mine' }; userPermissions = @{ permissions = @(); origins = @('<all_urls>') } }
                @{ id = 'school@x'; type = 'extension'; location = 'app-profile'; active = $false; defaultLocale = @{ name = 'School' }; installTelemetryInfo = @{ source = 'enterprise-policy' }; userPermissions = @{ permissions = @('history'); origins = @() } }
            ) }
        Mock -ModuleName schizo Expand-RulePath { $ff } -ParameterFilter { $Path -eq '%APPDATA%\Mozilla\Firefox' }
        $found = @(Get-FirefoxExtensions)
        ($found | Where-Object Name -eq 'Mine').Source | Should -Be 'user'
        ($found | Where-Object Name -eq 'School').Source | Should -Be 'policy'
        ($found | Where-Object Name -eq 'School').Disabled | Should -BeTrue
    }
}

Describe 'one line per extension' {
    It 'drops an extension that turns up twice' {
        $one = @{ Browser = 'chrome'; Profile = 'Default'; Id = $a; Name = 'Proctor'; Facts = @('all sites') }
        Mock -ModuleName schizo Get-ChromiumExtensions { if ($Browser -eq 'chrome') { $one; $one.Clone() } }
        Mock -ModuleName schizo Get-FirefoxExtensions { }
        @(Get-BrowserExtensions).Count | Should -Be 1
    }

    It 'keeps two extensions that share a name, and tells them apart by id' {
        $list = @(
            @{ Browser = 'chrome'; Profile = 'Default'; Id = 'fpmapakogndmenjcfoajifaaonnkpkei'; Name = 'Secure Exam Proctor'; Facts = @('all sites') }
            @{ Browser = 'chrome'; Profile = 'Default'; Id = 'gfolddmfcichcfnghdchbfgpmgodmkjd'; Name = 'Secure Exam Proctor'; Facts = @('all sites') }
            @{ Browser = 'chrome'; Profile = 'Default'; Id = $c; Name = 'Tampermonkey'; Facts = @('all sites') }
        )
        Set-ExtensionLabel $list
        $list[0].Label | Should -Be 'Secure Exam Proctor (fpmapako)'
        $list[1].Label | Should -Be 'Secure Exam Proctor (gfolddmf)'
        $list[2].Label | Should -Be 'Tampermonkey' -Because 'ids only appear when names collide'
    }

    It 'shows the profile only when it tells something apart' {
        $list = @(
            @{ Browser = 'chrome'; Profile = 'Profile 6'; Id = $a; Name = 'Grammarly'; Facts = @('all sites') }
            @{ Browser = 'chrome'; Profile = 'Profile 7'; Id = $a; Name = 'Grammarly'; Facts = @('all sites') }
            @{ Browser = 'edge'; Profile = 'Default'; Id = $a; Name = 'Grammarly'; Facts = @('all sites') }
        )
        Set-ExtensionLabel $list
        $list[0].Label | Should -Be 'Grammarly [Profile 6]'
        $list[1].Label | Should -Be 'Grammarly [Profile 7]'
        $list[2].Label | Should -Be 'Grammarly' -Because 'the browser is printed beside it, and edge has one profile here'
    }

    It 'keeps the same extension in two browsers apart' {
        $chrome = @{ Browser = 'chrome'; Profile = 'Default'; Id = $a; Name = 'uBlock' }
        $brave = @{ Browser = 'brave'; Profile = 'Default'; Id = $a; Name = 'uBlock' }
        Get-ExtensionKey $chrome | Should -Not -Be (Get-ExtensionKey $brave)
    }
}
