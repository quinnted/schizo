# read-only. schizo reports extensions, it never removes or disables them.
# a password manager needs to read every site; that's what it's for. the
# report lists what an extension can do and leaves the judgement to a human.

$script:ChromiumBrowsers = [ordered]@{
    chrome = '%LOCALAPPDATA%\Google\Chrome\User Data'
    edge   = '%LOCALAPPDATA%\Microsoft\Edge\User Data'
    brave  = '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\User Data'
}

$script:AllSites = '<all_urls>', '*://*/*', 'http://*/*', 'https://*/*', '*://*/', 'file:///*'

$script:LoudPermissions = [ordered]@{
    history         = 'browsing history'
    nativeMessaging = 'talks to programs outside the browser'
    debugger        = 'debugger access'
    clipboardRead   = 'reads the clipboard'
    proxy           = 'controls the proxy'
    management      = 'manages other extensions'
    webRequestBlocking = 'intercepts requests'
}

# where chromium says an extension came from. the numbers are the
# ManifestLocation enum in extensions/common/mojom/manifest.mojom, as
# chromium stores it in the profile prefs.
$script:ChromiumSource = @{
    1  = 'user'           # web store, or a user install
    2  = 'other program'  # external_extensions.json
    3  = 'other program'  # windows registry
    4  = 'unpacked'       # developer mode
    6  = 'other program'  # external json with an update url
    7  = 'policy'         # ExtensionInstallForcelist and friends
    8  = 'unpacked'       # --load-extension
    9  = 'policy'         # policy, installed from a local cache
}
# 5 and 10 are pieces of the browser itself and never shown to users.
$script:ChromiumBuiltIn = 5, 10

function Get-ExtensionFindings {
    param([string[]]$Permissions, [string[]]$Hosts)

    $facts = @()
    if (@($Hosts + $Permissions | Where-Object { $_ -in $script:AllSites }).Count) { $facts += 'all sites' }
    foreach ($p in $script:LoudPermissions.Keys) {
        if ($Permissions -contains $p) { $facts += $script:LoudPermissions[$p] }
    }
    $facts
}

function Get-ExtensionKey {
    param([hashtable]$Extension)
    "$($Extension.Browser)|$($Extension.Profile)|$($Extension.Id)".ToLowerInvariant()
}

function Read-JsonFile {
    param([string]$Path)
    # chrome writes manifests as utf-8, sometimes with a bom. 5.1's Get-Content
    # guesses ansi without one, so read the bytes explicitly.
    [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Resolve-ExtensionName {
    param($Manifest, [string]$Dir)

    $name = [string]$Manifest.name
    if ($name -notmatch '^__MSG_(.+)__$') { return $name }
    $msgKey = $Matches[1]
    $locales = @()
    if ($Manifest.PSObject.Properties.Name -contains 'default_locale') { $locales += [string]$Manifest.default_locale }
    $locales += 'en', 'en_US'
    foreach ($locale in $locales) {
        $file = Join-Path $Dir "_locales\$locale\messages.json"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try { $messages = Read-JsonFile $file } catch { continue }
        # message keys are case-insensitive in chrome; PSObject lookups are too.
        $entry = $messages.PSObject.Properties | Where-Object { $_.Name -eq $msgKey } | Select-Object -First 1
        if ($entry -and $entry.Value.message) { return [string]$entry.Value.message }
    }
    $name
}

# the profile's own record of installed extensions: id -> settings. the
# Extensions folder alone isn't enough; it keeps old versions and leftovers
# of removed extensions until chrome gets round to deleting them.
function Read-ChromiumSettings {
    param([string]$ProfileDir)

    $settings = @{}
    $read = $false
    # windows chrome keeps them in Secure Preferences; Preferences is older.
    foreach ($file in 'Preferences', 'Secure Preferences') {
        $path = Join-Path $ProfileDir $file
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try { $prefs = Read-JsonFile $path } catch { continue }
        $read = $true
        $list = $prefs.extensions.settings
        if (-not $list) { continue }
        foreach ($p in $list.PSObject.Properties) { $settings[$p.Name] = $p.Value }
    }
    if ($read) { $settings }
}

function Test-ExtensionDisabled {
    param($Setting)
    # newer chrome writes disable_reasons as a list, older as a bit mask.
    $reasons = $Setting.disable_reasons
    if ($reasons -is [array]) { if ($reasons.Count) { return $true } }
    elseif ($reasons) { return $true }
    $Setting.PSObject.Properties.Name -contains 'state' -and $Setting.state -eq 0
}

function Read-ChromiumExtension {
    param([string]$Browser, [string]$ProfileName, [string]$Id, [string]$Dir, [string]$Source, [bool]$Disabled)

    $manifestPath = Join-Path $Dir 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return }
    $found = @{ Browser = $Browser; Profile = $ProfileName; Id = $Id; Name = $Id; Source = $Source; Disabled = $Disabled; Facts = @() }
    try { $m = Read-JsonFile $manifestPath }
    catch {
        $found.Facts = @('manifest unreadable')
        return $found
    }

    $perms = @($m.permissions | Where-Object { $_ -is [string] })
    $hosts = @($m.host_permissions | Where-Object { $_ -is [string] })
    foreach ($cs in @($m.content_scripts)) { if ($cs) { $hosts += @($cs.matches) } }
    # mv2 put host patterns in permissions too.
    $hosts += @($perms | Where-Object { $_ -match '[:/*]' })

    $found.Facts = @(Get-ExtensionFindings $perms $hosts)
    $found.Name = Resolve-ExtensionName $m $Dir
    $found
}

function Get-ChromiumExtensions {
    param([string]$Browser, [string]$UserData)

    $root = Expand-RulePath $UserData
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }
    $profiles = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }

    foreach ($profileDir in $profiles) {
        $extRoot = Join-Path $profileDir.FullName 'Extensions'
        $settings = Read-ChromiumSettings $profileDir.FullName

        if ($null -eq $settings) {
            # no readable prefs: fall back to the folders, newest version of
            # each, and say nothing about where they came from.
            if (-not (Test-Path -LiteralPath $extRoot -PathType Container)) { continue }
            foreach ($ext in Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction SilentlyContinue) {
                if ($ext.Name -notmatch '^[a-p]{32}$') { continue }
                $versionDir = Get-ChildItem -LiteralPath $ext.FullName -Directory -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime | Select-Object -Last 1
                if ($versionDir) { Read-ChromiumExtension $Browser $profileDir.Name $ext.Name $versionDir.FullName 'unknown' $false }
            }
            continue
        }

        foreach ($id in $settings.Keys) {
            if ($id -notmatch '^[a-p]{32}$') { continue }
            $s = $settings[$id]
            $location = [int]$s.location
            if ($location -in $script:ChromiumBuiltIn) { continue }

            # path points at the version that is installed now: relative to
            # Extensions for packed ones, absolute for unpacked ones.
            $path = [string]$s.path
            if (-not $path) { continue }
            if ($path -match '^[A-Za-z]:\\') { $dir = $path }
            elseif ([IO.Path]::IsPathRooted($path)) { continue }   # \\server\share: not followed
            else { $dir = Join-Path $extRoot $path }

            $source = $script:ChromiumSource[$location]
            if (-not $source) { $source = 'unknown' }
            if ($source -eq 'other program' -and $s.was_installed_by_default) { $source = 'browser default' }
            Read-ChromiumExtension $Browser $profileDir.Name $id $dir $source (Test-ExtensionDisabled $s)
        }
    }
}

function Get-FirefoxExtensions {
    $root = Expand-RulePath '%APPDATA%\Mozilla\Firefox'
    $ini = Join-Path $root 'profiles.ini'
    if (-not (Test-Path -LiteralPath $ini -PathType Leaf)) { return }

    $profiles = @()
    $current = @{}
    foreach ($line in Get-Content -LiteralPath $ini) {
        if ($line -match '^\[') {
            if ($current.Path) { $profiles += $current }
            $current = @{}
        }
        elseif ($line -match '^(Path|IsRelative)=(.*)$') { $current[$Matches[1]] = $Matches[2].Trim() }
    }
    if ($current.Path) { $profiles += $current }

    foreach ($p in $profiles) {
        $dir = if ($p.IsRelative -eq '1') { Join-Path $root ($p.Path -replace '/', '\') } else { $p.Path }
        # profiles.ini is the user's file; don't follow it onto a network share.
        if ($dir -notmatch '^[A-Za-z]:\\') { continue }
        $file = Join-Path $dir 'extensions.json'
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try { $data = Read-JsonFile $file } catch { continue }
        foreach ($a in @($data.addons)) {
            # built-in and system add-ons ship with firefox; only report what a
            # user (or something acting as one) installed into the profile.
            if ($a.type -ne 'extension' -or $a.location -ne 'app-profile') { continue }
            $perms = @($a.userPermissions.permissions)
            # manifest v3 add-ons list the sites they ask for here instead.
            $hosts = @($a.userPermissions.origins) + @($a.requestedPermissions.origins)
            # firefox tags what its policy engine installed this way, and
            # checks the same field itself when it cleans up policy installs.
            $source = if ($a.installTelemetryInfo.source -eq 'enterprise-policy') { 'policy' } else { 'user' }
            @{
                Browser  = 'firefox'
                Profile  = Split-Path -Leaf $dir
                Id       = [string]$a.id
                Name     = [string]$a.defaultLocale.name
                Source   = $source
                Disabled = ($a.active -eq $false)
                Facts    = @(Get-ExtensionFindings $perms $hosts)
            }
        }
    }
}

# everything installed, keyed by browser, profile and extension id, so the
# same extension is never listed twice. callers decide what is worth printing.
function Get-BrowserExtensions {
    $seen = @{}
    $all = @(foreach ($b in $script:ChromiumBrowsers.Keys) { Get-ChromiumExtensions $b $script:ChromiumBrowsers[$b] }) + @(Get-FirefoxExtensions)
    foreach ($e in $all) {
        if (-not $e) { continue }
        $key = Get-ExtensionKey $e
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $e
    }
}

# how each extension is named in the report: its name, the profile when the
# list spans more than one profile of that browser, and the start of the id
# when two extensions in one profile share a name (it happens: two versions
# of an exam proctor published under different ids).
function Set-ExtensionLabel {
    param([object[]]$Extensions)

    $profiles = @{}
    $names = @{}
    foreach ($e in $Extensions) {
        $profiles["$($e.Browser)|$($e.Profile)"] = $e.Browser
        $n = "$($e.Browser)|$($e.Profile)|$($e.Name)".ToLowerInvariant()
        $names[$n] = 1 + [int]$names[$n]
    }
    foreach ($e in $Extensions) {
        $label = Format-Untrusted $e.Name 50
        if (@($profiles.Values | Where-Object { $_ -eq $e.Browser }).Count -gt 1) { $label += " [$(Format-Untrusted $e.Profile 30)]" }
        if ($names["$($e.Browser)|$($e.Profile)|$($e.Name)".ToLowerInvariant()] -gt 1) {
            $label += " ($(Format-Untrusted $e.Id.Substring(0, [Math]::Min(8, $e.Id.Length)) 8))"
        }
        $e.Label = $label
    }
}
