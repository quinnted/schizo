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

function Get-ExtensionFindings {
    param([string[]]$Permissions, [string[]]$Hosts)

    $facts = @()
    if (@($Hosts + $Permissions | Where-Object { $_ -in $script:AllSites }).Count) { $facts += 'all sites' }
    foreach ($p in $script:LoudPermissions.Keys) {
        if ($Permissions -contains $p) { $facts += $script:LoudPermissions[$p] }
    }
    $facts
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

function Get-ChromiumExtensions {
    param([string]$Browser, [string]$UserData)

    $root = Expand-RulePath $UserData
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return }
    $profiles = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }

    foreach ($profileDir in $profiles) {
        $extRoot = Join-Path $profileDir.FullName 'Extensions'
        if (-not (Test-Path -LiteralPath $extRoot -PathType Container)) { continue }
        foreach ($ext in Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction SilentlyContinue) {
            if ($ext.Name -notmatch '^[a-p]{32}$') { continue }
            # usually one folder per extension. mid-update there are two, and
            # the newer folder is the one that runs.
            $versionDir = Get-ChildItem -LiteralPath $ext.FullName -Directory -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime | Select-Object -Last 1
            if (-not $versionDir) { continue }
            $manifestPath = Join-Path $versionDir.FullName 'manifest.json'
            if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { continue }
            try { $m = Read-JsonFile $manifestPath }
            catch {
                @{ Browser = $Browser; Profile = $profileDir.Name; Id = $ext.Name; Name = $ext.Name; Facts = @('manifest unreadable') }
                continue
            }

            $perms = @($m.permissions | Where-Object { $_ -is [string] })
            $hosts = @($m.host_permissions | Where-Object { $_ -is [string] })
            foreach ($cs in @($m.content_scripts)) { if ($cs) { $hosts += @($cs.matches) } }
            # mv2 put host patterns in permissions too.
            $hosts += @($perms | Where-Object { $_ -match '[:/*]' })

            $facts = @(Get-ExtensionFindings $perms $hosts)
            if (-not $facts.Count) { continue }
            @{
                Browser = $Browser
                Profile = $profileDir.Name
                Id      = $ext.Name
                Name    = (Resolve-ExtensionName $m $versionDir.FullName)
                Facts   = $facts
            }
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
            $facts = @(Get-ExtensionFindings $perms $hosts)
            if (-not $facts.Count) { continue }
            @{
                Browser = 'firefox'
                Profile = Split-Path -Leaf $dir
                Id      = [string]$a.id
                Name    = [string]$a.defaultLocale.name
                Facts   = $facts
            }
        }
    }
}

function Get-BrowserExtensions {
    foreach ($b in $script:ChromiumBrowsers.Keys) { Get-ChromiumExtensions $b $script:ChromiumBrowsers[$b] }
    Get-FirefoxExtensions
}
