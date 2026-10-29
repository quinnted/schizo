# the unknown-software report and app detection, with entries copied from a
# real audit of a gaming/creative pc with 220 entries.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..\lib\schizo.psm1') -Force

    function New-Entry {
        param([string]$Name, [string]$Publisher = '', [string]$Version = '', [string]$Source = 'uninstall', [string]$Key = '', [bool]$Listed = $true, [string]$Title = '')
        $e = @{ Name = $Name; Publisher = $Publisher; Version = $Version; Source = $Source; Dir = ''; Scope = 'machine'; Key = $Key }
        if ($Source -eq 'store') { $e.Listed = $Listed; $e.Title = $Title }
        $e
    }
}

Describe 'what the unknown report leaves out' {
    It 'hides <name> as <kind>' -ForEach @(
        @{ name = 'Microsoft Visual C++ 2013 Redistributable (x64) - 12.0.40664'; kind = 'runtime' }
        @{ name = 'Microsoft Windows Desktop Runtime - 9.0.8 (x64)'; kind = 'runtime' }
        @{ name = 'Microsoft .NET Runtime - 8.0.21 (x64)'; kind = 'runtime' }
        @{ name = 'Microsoft XNA Framework Redistributable 4.0'; kind = 'runtime' }
        @{ name = 'PlayStation(R) PC SDK Runtime'; kind = 'runtime' }
        @{ name = 'Blackmagic RAW Common Components'; kind = 'runtime' }
        @{ name = 'Realtek Audio Driver'; kind = 'driver' }
        @{ name = 'Realtek Ethernet Controller Driver'; kind = 'driver' }
        @{ name = 'NVIDIA Graphics Driver 581.57'; kind = 'driver' }
        @{ name = 'Windows Driver Package - Logitech (WUSB) USB  (05/20/2020 1.0.0.0)'; kind = 'driver' }
    ) {
        Get-UnknownKind (New-Entry $name) | Should -Be $kind
    }

    It 'hides store packages that put nothing in the Start menu' {
        foreach ($n in 'Microsoft.HEVCVideoExtension', 'Microsoft.VP9VideoExtensions', 'MicrosoftCorporationII.WinAppRuntime.Main.1.8', 'WinRAR.ShellExtension', 'Microsoft.PowerToys.PowerRenameContextMenu') {
            Get-UnknownKind (New-Entry $n -Source store -Listed $false) | Should -Be 'support package' -Because $n
        }
    }

    It 'treats Microsoft.Windows* store packages as part of windows' {
        Get-UnknownKind (New-Entry 'Microsoft.WindowsCalculator' -Source store) | Should -Be 'part of windows'
        Get-UnknownKind (New-Entry 'MicrosoftWindows.Client.WebExperience' -Source store) | Should -Be 'part of windows'
    }

    It 'groups steam games under steam' {
        Get-UnknownKind (New-Entry 'Counter-Strike 2' 'Valve' -Key 'Steam App 730') | Should -Be 'steam game'
    }
}

Describe 'what the unknown report shows' {
    It 'shows <name>' -ForEach @(
        @{ name = 'Adobe After Effects 2026'; publisher = 'Adobe Inc.' }
        @{ name = 'Armoury Crate Service'; publisher = 'ASUSTeK COMPUTER INC.' }
        @{ name = 'ASUS DriverHub'; publisher = 'ASUSTeK COMPUTER INC.' }
        @{ name = 'Overwolf'; publisher = 'Overwolf Ltd.' }
        @{ name = 'CurseForge 1.306.1-34456'; publisher = 'Overwolf' }
        @{ name = 'Epic Games Launcher'; publisher = 'Epic Games, Inc.' }
        @{ name = 'Riot Vanguard'; publisher = 'Riot Games, Inc.' }
        @{ name = 'Spotify'; publisher = 'Spotify AB' }
        @{ name = 'Mullvad VPN 2026.5'; publisher = 'Mullvad VPN' }
        @{ name = 'Ollama version 0.33.2'; publisher = 'Ollama' }
        @{ name = 'Steam'; publisher = 'Valve Corporation' }
        @{ name = 'Driver Booster 12'; publisher = 'IObit' }
    ) {
        Get-UnknownKind (New-Entry $name $publisher) | Should -BeNullOrEmpty
    }

    It 'shows a microsoft application; the publisher alone hides nothing' {
        Get-UnknownKind (New-Entry 'Microsoft.OutlookForWindows' 'Microsoft Corporation' -Source store -Title 'Outlook for Windows') | Should -BeNullOrEmpty
        Get-UnknownKind (New-Entry 'PowerToys (Preview) x64' 'Microsoft Corporation') | Should -BeNullOrEmpty
    }

    It 'shows things it can''t place rather than guessing' {
        Get-UnknownKind (New-Entry 'Epic Online Services' 'Epic Games, Inc.') | Should -BeNullOrEmpty
        Get-UnknownKind (New-Entry 'aescripts + aeplugins components' 'aescripts + aeplugins') | Should -BeNullOrEmpty
    }

    It 'shows a store app with a Start menu entry' {
        Get-UnknownKind (New-Entry 'B9ECED6F.ArmouryCrate' -Source store -Title 'Armoury Crate') | Should -BeNullOrEmpty
    }
}

Describe 'how an unknown app is printed' {
    It 'merges <a> and <b>' -ForEach @(
        @{ a = 'Python 3.14.6'; b = 'Python 3.14.6 (64-bit)' }
        @{ a = 'Roblox Player'; b = "Roblox Player for $env:USERNAME" }
        @{ a = 'SignalRgb'; b = 'SignalRGB' }
    ) {
        Get-AppKey (New-Entry $a) | Should -Be (Get-AppKey (New-Entry $b))
    }

    It 'keeps different programs apart' {
        Get-AppKey (New-Entry 'Roblox Player') | Should -Not -Be (Get-AppKey (New-Entry 'Roblox Studio'))
        Get-AppKey (New-Entry 'Armoury Crate') | Should -Not -Be (Get-AppKey (New-Entry 'Armoury Crate Service'))
    }

    It 'does not repeat a version that is already in the name' {
        Format-UnknownApp (New-Entry 'Audacity 3.7.6' 'Audacity Team' '3.7.6') | Should -Be 'Audacity 3.7.6'
    }

    It 'leaves out a publisher that is a guid, or the first word of the name' {
        Format-UnknownApp (New-Entry 'B9ECED6F.ArmouryCrate' '38BC0208-0916-4E44-909B-E6832F47CDE7' '6.7.6.0' -Source store) | Should -Be 'ArmouryCrate 6.7.6.0'
        Format-UnknownApp (New-Entry 'Spotify' 'Spotify AB' '1.3.0') | Should -Be 'Spotify 1.3.0'
        Format-UnknownApp (New-Entry 'DaVinci Resolve' 'Blackmagic Design' '20.3') | Should -Be 'DaVinci Resolve 20.3 (Blackmagic Design)'
    }

    It 'uses the store display name when there is one' {
        Format-UnknownApp (New-Entry 'B9ECED6F.ArmouryCrate' 'ASUSTeK COMPUTER INC.' '6.7.6.0' -Source store -Title 'Armoury Crate') | Should -Be 'Armoury Crate 6.7.6.0 (ASUSTeK COMPUTER INC.)'
    }
}

Describe 'detection and the unknown list together' {
    BeforeAll {
        $rulebase = Import-Rules (Join-Path $PSScriptRoot '..\rules')
        $inventory = @(
            New-Entry 'Adobe After Effects 2026' 'Adobe Inc.' '26.0'
            New-Entry 'Adobe Photoshop 2026' 'Adobe Inc.' '27.0'
            New-Entry 'Adobe Fonts Something' 'Not Adobe Ltd.' '1.0'
            New-Entry 'Microsoft 365 - en-us' 'Microsoft Corporation' '16.0.20527'
            New-Entry 'Microsoft Visual C++ v14 Redistributable (x64) - 14.51.36247' 'Microsoft Corporation' '14.51'
            New-Entry 'Spotify' 'Spotify AB' '1.3.0'
        )
        Mock -ModuleName schizo Get-InstalledApps { $inventory }
        Mock -ModuleName schizo Get-StoreApps { }
        Mock -ModuleName schizo Get-Service { }
        Mock -ModuleName schizo Get-ConsoleUserSid { }
        Mock -ModuleName schizo Test-Path { $false } -ParameterFilter { $PathType -eq 'Leaf' }
        $machine = Get-Machine $rulebase.Apps
    }

    It 'gives every adobe desktop app the adobe advice, not just one of them' {
        $machine.Found.Keys | Should -Contain 'adobe'
        $names = @($machine.Unknown | ForEach-Object { $_.Name })
        $names | Should -Not -Contain 'Adobe After Effects 2026'
        $names | Should -Not -Contain 'Adobe Photoshop 2026'
        $names | Should -Contain 'Adobe Fonts Something' -Because 'the publisher is not adobe'
    }

    It 'treats microsoft 365 as office' {
        $machine.Found.Keys | Should -Contain 'office'
        @($machine.Unknown | ForEach-Object { $_.Name }) | Should -Not -Contain 'Microsoft 365 - en-us'
    }

    It 'keeps hidden entries in the inventory rules match against' {
        @($machine.Installed | Where-Object { $_.Name -like 'Microsoft Visual C++*' }).Count | Should -Be 1
        $app = @{ Name = 'VC'; Uninstall = '^Microsoft Visual C\+\+' }
        (Find-App $app $machine.Installed @()).Name | Should -BeLike 'Microsoft Visual C++*'
    }

    It 'marks the runtime as a runtime and the app as an app' {
        ($machine.Unknown | Where-Object Name -like 'Microsoft Visual C++*').Kind | Should -Be 'runtime'
        ($machine.Unknown | Where-Object Name -eq 'Spotify').Kind | Should -BeNullOrEmpty
    }
}

Describe 'advice text' {
    BeforeAll {
        $rules = (Import-Rules (Join-Path $PSScriptRoot '..\rules')).Rules
        function Get-Advice([string]$Id) { ($rules | Where-Object Id -eq $Id).Advice }
    }

    It 'does not claim discord''s signals cannot be stopped at all' {
        $text = Get-Advice 'discord.data-use'
        $text | Should -Not -Match 'nothing on this pc|cannot be stopped|can''t be stopped|impossible'
        $text | Should -Match 'local setting'
    }

    It 'points adobe users at the one account setting' {
        Get-Advice 'adobe.desktop-app-usage' | Should -Match 'Desktop app usage'
    }
}
