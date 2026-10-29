BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\schizo.psm1') -Force

    function Write-Json {
        param([string]$Path, $Object)
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path)
        [IO.File]::WriteAllText($Path, ($Object | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $true))
    }
}

Describe 'finding installed apps' {
    BeforeAll {
        $appDir = Join-Path $TestDrive 'Foo'
        $null = New-Item -ItemType Directory -Force -Path $appDir
        $installed = @(
            @{ Name = 'Foo Editor 2'; Version = '2.1'; Publisher = 'Foo Ltd'; Dir = "`"$appDir\`""; Source = 'uninstall' }
            @{ Name = 'Fake Foo Editor 2'; Version = '9'; Publisher = 'Somebody'; Dir = ''; Source = 'uninstall' }
            @{ Name = 'Vendor.StoreThing'; Version = '1.0'; Publisher = 'Vendor'; Dir = 'C:\x'; Source = 'store' }
        )
    }

    It 'matches uninstall entries by name and publisher' {
        $hit = Find-App @{ Name = 'Foo'; Uninstall = 'Foo Editor'; Publisher = '^Foo Ltd$' } $installed @()
        $hit.Name | Should -Be 'Foo Editor 2'
        $hit.Dir | Should -Be $appDir -Because 'quotes and trailing slashes in InstallLocation are common'
    }

    It 'does not match a different publisher' {
        Find-App @{ Name = 'Foo'; Uninstall = '^Fake'; Publisher = '^Foo Ltd$' } $installed @() | Should -BeNullOrEmpty
    }

    It 'finds apps by file' {
        $exe = Join-Path $TestDrive 'bin\tool.exe'
        $null = New-Item -ItemType File -Force -Path $exe
        (Find-App @{ Name = 'Tool'; File = $exe } @() @()).Dir | Should -Be (Join-Path $TestDrive 'bin')
    }

    It 'resolves %folders% through the known-folder api, not the environment' {
        $env:LOCALAPPDATA_BACKUP = $env:LOCALAPPDATA
        try {
            $env:LOCALAPPDATA = 'C:\not-really'
            Expand-RulePath '%LOCALAPPDATA%\x' | Should -Be (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'x')
        }
        finally { $env:LOCALAPPDATA = $env:LOCALAPPDATA_BACKUP; Remove-Item Env:\LOCALAPPDATA_BACKUP }
    }

    It 'never follows an install location to a network share' {
        $entry = @(@{ Name = 'Sneaky'; Version = '1'; Publisher = 'x'; Dir = '\\attacker\share'; Source = 'uninstall' })
        (Find-App @{ Name = 'S'; Uninstall = '^Sneaky' } $entry @()).Dir | Should -BeNullOrEmpty
    }
    It 'finds store packages and services' {
        (Find-App @{ Name = 'S'; Appx = 'Vendor.StoreThing' } $installed @()).Dir | Should -Be 'C:\x'
        Find-App @{ Name = 'Svc'; Service = 'FooSvc' } @() @('FooSvc') | Should -Not -BeNullOrEmpty
        Find-App @{ Name = 'Svc'; Service = 'FooSvc' } @() @('Other') | Should -BeNullOrEmpty
    }
}

Describe 'reading this machine' {
    It 'identifies windows from the build number, not ProductName' {
        $w = Get-WindowsInfo
        $w.Build | Should -BeGreaterThan 0
        if ($w.Build -ge 22000) { $w.Label | Should -Match '^windows 11' }
    }

    It 'lists installed software without Win32_Product' {
        $source = Get-Content (Join-Path $PSScriptRoot '..\lib\machine.ps1') -Raw
        ($source -split "`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n" | Should -Not -Match 'Win32_Product'
        @(Get-InstalledApps).Count | Should -BeGreaterThan 0
    }
}

Describe 'browser extensions' {
    BeforeAll {
        $userData = Join-Path $TestDrive 'User Data'
        $ext = Join-Path $userData 'Default\Extensions'

        Write-Json "$ext\aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\1.0_0\manifest.json" @{
            name = '__MSG_appName__'; default_locale = 'en'; manifest_version = 3
            permissions = @('history', 'storage'); host_permissions = @('<all_urls>')
        }
        Write-Json "$ext\aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\1.0_0\_locales\en\messages.json" @{ appname = @{ message = 'Coupon Thing' } }

        Write-Json "$ext\bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\2.0_0\manifest.json" @{
            name = 'Old Style'; manifest_version = 2; permissions = @('tabs', 'http://*/*', 'https://*/*')
        }
        Write-Json "$ext\cccccccccccccccccccccccccccccccc\1_0\manifest.json" @{
            name = 'Narrow'; manifest_version = 3; permissions = @('storage'); host_permissions = @('https://example.com/*')
        }
        Write-Json "$ext\dddddddddddddddddddddddddddddddd\1_0\manifest.json" @{
            name = 'Injects Everywhere'; manifest_version = 3; content_scripts = @(@{ matches = @('*://*/*'); js = @('a.js') })
        }
        Write-Json "$userData\Profile 2\Extensions\eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\1_0\manifest.json" @{
            name = 'Native Bridge'; manifest_version = 3; permissions = @('nativeMessaging')
        }
        $null = New-Item -ItemType Directory -Force -Path "$ext\Temp"

        $found = @(Get-ChromiumExtensions 'chrome' $userData)
    }

    It 'resolves localized names, case-insensitively' {
        ($found | Where-Object Id -eq ('a' * 32)).Name | Should -Be 'Coupon Thing'
    }

    It 'reports facts, not verdicts' {
        ($found | Where-Object Id -eq ('a' * 32)).Facts | Should -Be @('all sites', 'browsing history')
    }

    It 'catches manifest v2 host permissions and content scripts' {
        ($found | Where-Object Id -eq ('b' * 32)).Facts | Should -Contain 'all sites'
        ($found | Where-Object Id -eq ('d' * 32)).Facts | Should -Contain 'all sites'
    }

    It 'finds nothing broad about narrow extensions' {
        ($found | Where-Object Id -eq ('c' * 32)).Facts | Should -BeNullOrEmpty
    }

    It 'looks in every profile' {
        ($found | Where-Object Id -eq ('e' * 32)).Profile | Should -Be 'Profile 2'
    }

    It 'skips folders that are not extension ids' {
        $found | Where-Object Id -eq 'Temp' | Should -BeNullOrEmpty
    }

    It 'survives a broken manifest' {
        $bad = Join-Path $TestDrive 'Broken'
        $p = "$bad\Default\Extensions\ffffffffffffffffffffffffffffffff\1_0\manifest.json"
        $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p)
        Set-Content -LiteralPath $p -Value '{ not json'
        (@(Get-ChromiumExtensions 'chrome' $bad))[0].Facts | Should -Be 'manifest unreadable'
    }
}

Describe 'firefox extensions' {
    It 'reads add-ons from the profile and ignores built-in ones' {
        $appdata = Join-Path $TestDrive 'appdata'
        $ff = Join-Path $appdata 'Mozilla\Firefox'
        $null = New-Item -ItemType Directory -Force -Path "$ff\Profiles\abc.default"
        Set-Content -LiteralPath "$ff\profiles.ini" -Value "[Profile0]`nName=default`nIsRelative=1`nPath=Profiles/abc.default`n`n[Profile1]`nIsRelative=0`nPath=\\server\share\evil"
        Write-Json "$ff\Profiles\abc.default\extensions.json" @{ addons = @(
                @{ id = 'mv2@x'; type = 'extension'; location = 'app-profile'; defaultLocale = @{ name = 'Old One' }; userPermissions = @{ permissions = @('history'); origins = @('<all_urls>') } }
                @{ id = 'mv3@x'; type = 'extension'; location = 'app-profile'; defaultLocale = @{ name = 'New One' }; userPermissions = @{ permissions = @(); origins = @() }; requestedPermissions = @{ origins = @('*://*/*') } }
                @{ id = 'builtin@mozilla.org'; type = 'extension'; location = 'app-builtin'; defaultLocale = @{ name = 'Built In' }; userPermissions = @{ permissions = @('history'); origins = @('<all_urls>') } }
            ) }
        Mock -ModuleName schizo Expand-RulePath { $ff } -ParameterFilter { $Path -eq '%APPDATA%\Mozilla\Firefox' }
        $found = @(Get-FirefoxExtensions)
        @($found | ForEach-Object { $_.Name }) | Should -Be @('Old One', 'New One')
        ($found | Where-Object Name -eq 'Old One').Facts | Should -Be @('all sites', 'browsing history')
    }
}
