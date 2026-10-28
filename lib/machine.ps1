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
                        $display = [string]$k.GetValue('DisplayName')
                        if (-not $display.Trim()) { continue }
                        if ($k.GetValue('SystemComponent') -eq 1) { continue }
                        if ($k.GetValue('ParentKeyName')) { continue }
                        if ([string]$k.GetValue('ReleaseType') -match 'Update|Hotfix|Service Pack') { continue }

                        # the 32 and 64-bit views share some keys on purpose, and some
                        # installers write both. one entry per name and version.
                        $version = [string]$k.GetValue('DisplayVersion')
                        $id = "$display|$version".ToLowerInvariant()
                        if ($seen.ContainsKey($id)) { continue }
                        $seen[$id] = $true

                        @{
                            Name      = $display.Trim()
                            Version   = $version
                            Publisher = [string]$k.GetValue('Publisher')
                            Dir       = [string]$k.GetValue('InstallLocation')
                            Scope     = $s.Scope
                            Source    = 'uninstall'
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
        @{
            Name      = [string]$p.Name
            Version   = [string]$p.Version
            Publisher = ([string]$p.Publisher -replace '^CN=([^,]+).*$', '$1')
            Dir       = [string]$p.InstallLocation
            Scope     = 'user'
            Source    = 'store'
        }
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
            if ($i.Source -ne 'uninstall' -or $i.Name -notmatch $App.Uninstall) { continue }
            if ($App.Publisher -and $i.Publisher -notmatch $App.Publisher) { continue }
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
    $matched = @{}
    foreach ($id in $Apps.Keys) {
        if ($id -eq 'windows') { continue }
        $hit = Find-App $Apps[$id] $installed $services
        if ($hit) {
            $found[$id] = $hit
            if ($hit.Entry) { $matched[[string]$hit.Entry.Name] = $true }
        }
    }

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
        Unknown    = @($installed | Where-Object { -not $matched.ContainsKey([string]$_.Name) })
        Gaps       = $gaps
        User       = $me.Name
        UserSid    = $me.User.Value
        OtherUser  = $otherUser
    }
}
