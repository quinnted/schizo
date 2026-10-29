$script:EditionFamily = [ordered]@{
    '^Core'                     = 'home'
    # Pro Education is not Education. microsoft documents the enterprise and
    # education-only settings for those two editions and nothing else.
    '^Professional'             = 'pro'
    '^Education'                = 'education'
    '^(Enterprise|IoTEnterprise)' = 'enterprise'
}

function Get-WindowsInfo {
    $cv = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $build = [int]$cv.CurrentBuildNumber
    $editionId = [string]$cv.EditionID

    $edition = $null
    foreach ($pattern in $script:EditionFamily.Keys) {
        if ($editionId -match $pattern) { $edition = $script:EditionFamily[$pattern]; break }
    }

    # ProductName still says "Windows 10" on Windows 11. the build number is
    # the only thing that tells the truth.
    $product = if ($build -ge 22000) { 'windows 11' } else { 'windows 10' }
    $label = $product
    if ($edition) { $label += " $edition" } else { $label += " $editionId".ToLowerInvariant() }
    if ($cv.DisplayVersion) { $label += " $($cv.DisplayVersion)" }
    $label += " ($build)"

    @{
        Build     = $build
        EditionId = $editionId
        Edition   = $edition
        Server    = ([string]$cv.InstallationType -eq 'Server')
        Label     = $label
    }
}

# never Win32_Product for this. querying it makes msi run a consistency check
# on every msi package, which can "repair" (reconfigure) installed software.
function Get-InstalledApps {
    $sources = @(
        @{ Hive = 'LocalMachine'; View = 'Registry64'; Scope = 'machine' }
        @{ Hive = 'LocalMachine'; View = 'Registry32'; Scope = 'machine' }
        @{ Hive = 'CurrentUser'; View = 'Registry64'; Scope = 'user' }
        @{ Hive = 'CurrentUser'; View = 'Registry32'; Scope = 'user' }
    )
    $seen = @{}
    foreach ($s in $sources) {
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($s.Hive, $s.View)
        try {
            $root = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')
            if (-not $root) { continue }
            try {
                foreach ($name in $root.GetSubKeyNames()) {
                    $k = $root.OpenSubKey($name)
                    if (-not $k) { continue }
                    try {
                        # some installers write a trailing NUL into REG_SZ values (roblox
                        # does), which then never compares equal to anything.
                        $text = { param($v) ([string]$k.GetValue($v)).Trim([char]0, ' ') }
                        $display = & $text 'DisplayName'
                        if (-not $display.Trim()) { continue }
                        if ($k.GetValue('SystemComponent') -eq 1) { continue }
                        if ($k.GetValue('ParentKeyName')) { continue }
                        if ([string]$k.GetValue('ReleaseType') -match 'Update|Hotfix|Service Pack') { continue }

                        # the 32 and 64-bit views share some keys on purpose, and some
                        # installers write both. one entry per name and version.
                        $version = & $text 'DisplayVersion'
                        $id = "$display|$version".ToLowerInvariant()
                        if ($seen.ContainsKey($id)) { continue }
                        $seen[$id] = $true

                        @{
                            Name      = $display.Trim()
                            Version   = $version
                            Publisher = & $text 'Publisher'
                            Dir       = & $text 'InstallLocation'
                            Scope     = $s.Scope
                            Source    = 'uninstall'
                            Key       = $name
                        }
                    }
                    finally { $k.Dispose() }
                }
            }
            finally { $root.Dispose() }
        }
        finally { $base.Dispose() }
    }
}

function Get-StoreApps {
    # Get-AppxPackage only sees the current user, which is also the only user
    # schizo changes settings for.
    $packages = Get-AppxPackage -ErrorAction Stop
    foreach ($p in $packages) {
        if ($p.IsFramework -or $p.IsResourcePackage -or $p.IsBundle) { continue }
        if ([string]$p.SignatureKind -eq 'System') { continue }
        $entry = @{
            Name      = [string]$p.Name
            Version   = [string]$p.Version
            Publisher = ''
            Dir       = [string]$p.InstallLocation
            Scope     = 'user'
            Source    = 'store'
            Title     = ''
            Listed    = $true
        }
        # the manifest has the names a person would recognise, and says whether
        # the package puts anything in the Start menu. codecs, runtimes and the
        # sparse packages behind shell extensions don't.
        $manifest = Join-Path $entry.Dir 'AppxManifest.xml'
        if ($entry.Dir -match '^[A-Za-z]:\\' -and (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            try {
                [xml]$x = [IO.File]::ReadAllText($manifest)
                $props = $x.Package.Properties
                if ([string]$props.DisplayName -notmatch '^ms-resource:') { $entry.Title = [string]$props.DisplayName }
                if ([string]$props.PublisherDisplayName -notmatch '^ms-resource:') { $entry.Publisher = [string]$props.PublisherDisplayName }
                $apps = @($x.Package.Applications.Application | Where-Object { $_ })
                $entry.Listed = @($apps | Where-Object { $_.VisualElements.AppListEntry -ne 'none' }).Count -gt 0
            }
            # an unreadable manifest leaves the package name, and the package listed:
            # when unsure, show it.
            catch { $entry.Listed = $true }
        }
        $entry
    }
}

# who is sitting at the console. per-user rules change HKCU, and HKCU belongs
# to whoever ran schizo, which is not always the same person when an admin
# elevates for a standard user.
function Get-ConsoleUserSid {
    $sids = @()
    foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name = 'explorer.exe'" -ErrorAction SilentlyContinue)) {
        $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        # missing sid just means that explorer exited between the two calls.
        if ($owner -and $owner.Sid) { $sids += $owner.Sid }
    }
    $sids | Select-Object -Unique
}

function Test-AppEntry {
    param([hashtable]$App, [hashtable]$Entry)
    if ($Entry.Source -eq 'uninstall') {
        return [bool]($App.Uninstall -and $Entry.Name -match $App.Uninstall -and (-not $App.Publisher -or $Entry.Publisher -match $App.Publisher))
    }
    [bool](@($App.Appx) -contains $Entry.Name)
}

function Find-App {
    param([hashtable]$App, [object[]]$Installed, [object[]]$Services)

    $file = $null
    foreach ($f in @($App.File)) {
        if (-not $f) { continue }
        $path = Expand-RulePath $f
        if (Test-Path -LiteralPath $path -PathType Leaf) { $file = $path; break }
    }

    if ($App.Uninstall) {
        foreach ($i in $Installed) {
            if ($i.Source -ne 'uninstall' -or -not (Test-AppEntry $App $i)) { continue }
            $dir = $i.Dir
            if ($dir) { $dir = $dir.Trim().Trim('"').TrimEnd('\') }
            # InstallLocation in HKCU is anyone's to write. a \\server\share path
            # would make an elevated Test-Path hand that server our credentials.
            if ($dir -and ($dir -notmatch '^[A-Za-z]:\\' -or -not (Test-Path -LiteralPath $dir -PathType Container))) { $dir = $null }
            # plenty of msi packages never fill in InstallLocation.
            if (-not $dir -and $file) { $dir = Split-Path -Parent $file }
            return @{ Name = $i.Name; Version = $i.Version; Dir = $dir; Entry = $i }
        }
    }
    if ($file) {
        $version = (Get-Item -LiteralPath $file).VersionInfo.ProductVersion
        return @{ Name = $App.Name; Version = $version; Dir = (Split-Path -Parent $file) }
    }
    foreach ($a in @($App.Appx)) {
        if (-not $a) { continue }
        foreach ($i in $Installed) {
            if ($i.Source -eq 'store' -and $i.Name -eq $a) {
                return @{ Name = $App.Name; Version = $i.Version; Dir = $i.Dir; Entry = $i }
            }
        }
    }
    foreach ($s in @($App.Service)) {
        if ($s -and ($Services -contains $s)) { return @{ Name = $App.Name; Version = '' ; Dir = $null } }
    }
}

# schizo is for machines the user controls. on a managed machine the
# organization owns policy, and adding to it is not schizo's call.
function Get-ManagedReason {
    $cs = Get-CimInstance Win32_ComputerSystem
    if ($cs.PartOfDomain) { return "joined to $($cs.Domain)" }
    foreach ($k in @(Get-ChildItem -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction SilentlyContinue)) {
        $props = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
        if ($props -and $props.PSObject.Properties['ProviderID'] -and $props.ProviderID -eq 'MS DM Server') {
            return "mdm enrollment $($k.PSChildName)"
        }
    }
}

# there is no managed call that only broadcasts WM_SETTINGCHANGE. setting a
# machine variable broadcasts as a side effect, so delete one that isn't there.
function Send-EnvironmentChange {
    [Environment]::SetEnvironmentVariable('SCHIZO_UNUSED', $null, 'Machine')
}

function Get-Machine {
    param([hashtable]$Apps)

    $windows = Get-WindowsInfo
    $gaps = @()

    $installed = @(Get-InstalledApps)
    try { $installed += @(Get-StoreApps) }
    catch { $gaps += "store apps not listed: $($_.Exception.Message)" }

    $services = @(Get-Service -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })

    $found = @{}
    foreach ($id in $Apps.Keys) {
        if ($id -eq 'windows') { continue }
        $hit = Find-App $Apps[$id] $installed $services
        if ($hit) { $found[$id] = $hit }
    }
    # everything a rule's app definition covers is known, not just the entry
    # Find-App happened to pick: one adobe rule covers every adobe app.
    $unknown = @($installed | Where-Object {
            $entry = $_
            -not @($Apps.Values | Where-Object { Test-AppEntry $_ $entry }).Count
        })
    foreach ($u in $unknown) { $u.Kind = Get-UnknownKind $u }

    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $console = @(Get-ConsoleUserSid)
    $otherUser = $console.Count -gt 0 -and ($console -notcontains $me.User.Value)

    @{
        Build      = $windows.Build
        Edition    = $windows.Edition
        EditionId  = $windows.EditionId
        Server     = $windows.Server
        Label      = $windows.Label
        Installed  = $installed
        Found      = $found
        Unknown    = $unknown
        Gaps       = $gaps
        User       = $me.Name
        UserSid    = $me.User.Value
        OtherUser  = $otherUser
    }
}

# what an unknown entry is, when it plainly isn't an application someone
# would research: a runtime, a driver, a store package with nothing in the
# Start menu, a piece of windows, a steam game. $null means "show it".
# when the evidence is thin it stays $null.
function Get-UnknownKind {
    param([hashtable]$Entry)

    $name = [string]$Entry.Name
    if ($name -match 'Redistributable|\bRuntime\b|Common Components|Framework Redistributable|\.NET Framework') { return 'runtime' }
    if ($name -match '\bLanguage (Experience )?Pack\b') { return 'language pack' }
    # "Realtek Audio Driver", "Windows Driver Package - ...", but not "Driver Booster".
    if ($name -match '\bDrivers?( Package)?(\s*[-(\d].*)?$') { return 'driver' }
    if ($Entry.Source -eq 'store') {
        if (-not $Entry.Listed) { return 'support package' }
        # microsoft names the packages that ship as part of windows this way.
        if ($name -match '^(Microsoft\.Windows|MicrosoftWindows\.)') { return 'part of windows' }
    }
    # steam registers every game as "Steam App <id>"; steam itself is the app.
    if ($Entry.Key -match '^Steam App \d+$') { return 'steam game' }
    $null
}

# a name to tell "Python 3.14.6" and "Python 3.14.6 (64-bit)" are the same
# thing: no versions, no bitness, no "for <user>".
function Get-AppKey {
    param([hashtable]$Entry)
    $n = [string]$Entry.Title
    if (-not $n) { $n = [string]$Entry.Name }
    $n = $n.ToLowerInvariant()
    $n = $n -replace '\(?\b(x64|x86|64-bit|32-bit|amd64)\b\)?', ''
    $n = $n -replace "\bfor $([regex]::Escape($env:USERNAME.ToLowerInvariant()))$", ''
    $n = $n -replace '\bv?\d+(\.\d+)+[\w.-]*', '' -replace '\bversion\b', ''
    ($n -replace '[^a-z0-9]+', ' ').Trim()
}

function Format-UnknownApp {
    param([hashtable]$Entry)
    $name = [string]$Entry.Title
    if (-not $name) { $name = [string]$Entry.Name -replace '^[0-9A-F]{8}\.', '' }
    $line = Format-Untrusted $name
    # plenty of installers put the version in the name already.
    if ($Entry.Version -and $name -notmatch [regex]::Escape($Entry.Version)) { $line += " $(Format-Untrusted $Entry.Version 20)" }
    $publisher = [string]$Entry.Publisher
    if ($publisher -and $publisher -notmatch '^[0-9A-F]{8}(-[0-9A-F]{4}){3}-[0-9A-F]{12}$' -and
        -not $name.StartsWith(($publisher -split ' ')[0], [StringComparison]::OrdinalIgnoreCase)) {
        $line += " ($(Format-Untrusted $publisher 40))"
    }
    $line
}
