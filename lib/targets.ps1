# every kind of thing schizo changes gets a Get-*State and a Set-*State.
# apply sets the rule's wanted state; restore sets the state it saved first.
# states are plain hashtables so they survive a round trip through json.

function Get-TargetState {
    param([hashtable]$Target)
    switch ($Target.Type) {
        'registry' { Get-RegistryState $Target }
        'service' { Get-ServiceState $Target }
        'firewall' { Get-FirewallState $Target }
        default { throw "unknown target type '$($Target.Type)'" }
    }
}

function Set-TargetState {
    param([hashtable]$Target, [hashtable]$State)
    switch ($Target.Type) {
        'registry' { Set-RegistryState $Target $State }
        'service' { Set-ServiceState $Target $State }
        'firewall' { Set-FirewallState $Target $State }
        default { throw "unknown target type '$($Target.Type)'" }
    }
}

# "matches" means as far as the rule cares. a disabled service that is still
# running is disabled; whether it runs is not part of the comparison.
function Test-StateMatch {
    param([string]$Type, [hashtable]$Current, [hashtable]$Want)

    if ([bool]$Current.Exists -ne [bool]$Want.Exists) { return $false }
    if (-not $Want.Exists) { return $true }
    switch ($Type) {
        'registry' {
            if ($Current.Kind -ne $Want.Kind) { return $false }
            if ($Want.Kind -in 'DWord', 'QWord') { return [long]$Current.Data -eq [long]$Want.Data }
            # ordinal, element by element. -ceq compares with culture rules,
            # which treat a soft hyphen or a NUL as if it weren't there.
            $a = @($Current.Data); $b = @($Want.Data)
            if ($Want.Kind -ne 'MultiString') { $a = @([string]$Current.Data); $b = @([string]$Want.Data) }
            if ($a.Count -ne $b.Count) { return $false }
            for ($i = 0; $i -lt $a.Count; $i++) {
                if (-not [string]::Equals([string]$a[$i], [string]$b[$i], [StringComparison]::Ordinal)) { return $false }
            }
            return $true
        }
        'service' { return $Current.Start -eq $Want.Start }
        'firewall' {
            return $Current.Program -eq $Want.Program -and $Current.Enabled -and
                $Current.Action -eq 'Block' -and $Current.Direction -eq 'Outbound'
        }
    }
}

function Test-PolicyKey {
    param([string]$Key)
    $Key -match '\\Policies\\'
}

# always the 64-bit view. a 32-bit host would otherwise land in WOW6432Node and
# write policies nothing reads.
function Open-RegistryBase {
    param([string]$Key)
    $hive, $sub = $Key -split '\\', 2
    $root = switch ($hive) {
        'HKLM' { [Microsoft.Win32.RegistryHive]::LocalMachine }
        'HKCU' { [Microsoft.Win32.RegistryHive]::CurrentUser }
        default { throw "unsupported hive in $Key" }
    }
    [Microsoft.Win32.RegistryKey]::OpenBaseKey($root, [Microsoft.Win32.RegistryView]::Registry64), $sub
}

function Get-RegistryState {
    param([hashtable]$Target)

    $base, $sub = Open-RegistryBase $Target.Key
    try {
        $key = $base.OpenSubKey($sub)
        if (-not $key) {
            # remember the highest key that is missing, so restore can remove
            # what schizo created and nothing else.
            $missing = $Target.Key
            $parent = $sub
            while ($parent -match '\\') {
                $parent = $parent.Substring(0, $parent.LastIndexOf('\'))
                $k = $base.OpenSubKey($parent)
                if ($k) { $k.Dispose(); break }
                $missing = ($Target.Key -split '\\', 2)[0] + '\' + $parent
            }
            return @{ Exists = $false; Missing = $missing }
        }
        try {
            if ($key.GetValueNames() -notcontains $Target.Value) { return @{ Exists = $false } }
            $kind = $key.GetValueKind($Target.Value)
            $data = $key.GetValue($Target.Value, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            switch ($kind) {
                'DWord' { $data = [long][BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$data), 0) }
                'QWord' { $data = [long]$data }
                'Binary' { $data = [Convert]::ToBase64String([byte[]]$data) }
                'MultiString' { $data = [string[]]$data }
                'String' { }
                'ExpandString' { }
                default { return @{ Exists = $true; Kind = 'Unsupported' } }
            }
            @{ Exists = $true; Kind = [string]$kind; Data = $data }
        }
        finally { $key.Dispose() }
    }
    finally { $base.Dispose() }
}

function Set-RegistryState {
    param([hashtable]$Target, [hashtable]$State)

    $base, $sub = Open-RegistryBase $Target.Key
    try {
        if ($State.Exists) {
            if ($State.Kind -eq 'Unsupported') { throw "can't write an unsupported registry value type" }
            $key = $base.CreateSubKey($sub)
            try {
                # assigned per branch: a switch used as an expression unrolls
                # string[] and byte[] into object[], which SetValue rejects.
                switch ($State.Kind) {
                    'DWord' { $data = [BitConverter]::ToInt32([BitConverter]::GetBytes([uint32]$State.Data), 0) }
                    'QWord' { $data = [long]$State.Data }
                    'Binary' { [byte[]]$data = [Convert]::FromBase64String($State.Data) }
                    'MultiString' { [string[]]$data = @($State.Data) }
                    default { $data = [string]$State.Data }
                }
                $key.SetValue($Target.Value, $data, [Microsoft.Win32.RegistryValueKind]$State.Kind)
            }
            finally { $key.Dispose() }
            return
        }

        $key = $base.OpenSubKey($sub, $true)
        if ($key) {
            try { $key.DeleteValue($Target.Value, $false) } finally { $key.Dispose() }
        }
        if ($State.Missing) { Remove-EmptyKeys $base $sub (($State.Missing -split '\\', 2)[1]) }
    }
    finally { $base.Dispose() }
}

# walk up from $Sub to $Top deleting keys that are empty. stops at the first
# key that still holds anything, because then it isn't only ours.
function Remove-EmptyKeys {
    param([Microsoft.Win32.RegistryKey]$Base, [string]$Sub, [string]$Top)

    $path = $Sub
    while ($path.Length -ge $Top.Length) {
        $key = $Base.OpenSubKey($path)
        if (-not $key) {
            if ($path -eq $Top) { return }
        }
        else {
            $empty = $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
            $key.Dispose()
            if (-not $empty) { return }
            $Base.DeleteSubKey($path, $false)
        }
        if ($path -eq $Top -or $path -notmatch '\\') { return }
        $path = $path.Substring(0, $path.LastIndexOf('\'))
    }
}

$script:StartNames = @{ 2 = 'Automatic'; 3 = 'Manual'; 4 = 'Disabled' }

function Get-ServiceState {
    param([hashtable]$Target)

    $svc = Get-Service -Name $Target.Service -ErrorAction SilentlyContinue
    if (-not $svc) { return @{ Exists = $false } }

    # read the start type from the service key: Get-Service in 5.1 can't tell
    # Automatic from Automatic (Delayed Start).
    $key = "HKLM:\SYSTEM\CurrentControlSet\Services\$($Target.Service)"
    $props = Get-ItemProperty -LiteralPath $key -ErrorAction Stop
    $start = [int]$props.Start
    $name = $script:StartNames[$start]
    if (-not $name) { $name = "Raw$start" }
    if ($start -eq 2 -and ($props.PSObject.Properties.Name -contains 'DelayedAutostart') -and $props.DelayedAutostart -eq 1) {
        $name = 'AutomaticDelayed'
    }
    @{ Exists = $true; Start = $name; Running = ($svc.Status -ne 'Stopped') }
}

function Set-ServiceState {
    param([hashtable]$Target, [hashtable]$State)

    if (-not $State.Exists) { return }
    $mode = switch ($State.Start) {
        'Automatic' { 'auto' }
        'AutomaticDelayed' { 'delayed-auto' }
        'Manual' { 'demand' }
        'Disabled' { 'disabled' }
        default { throw "won't set service start type '$($State.Start)'" }
    }
    # sc, not Set-Service: 5.1's Set-Service can't do delayed start. the space
    # after "start=" is sc's syntax, not a typo. and it's sc.exe because "sc"
    # is Set-Content.
    $out = & { $ErrorActionPreference = 'Continue'; & sc.exe config $Target.Service start= $mode 2>&1 }
    if ($LASTEXITCODE -ne 0) { throw "sc.exe config $($Target.Service) failed: $(($out | Out-String).Trim())" }

    $svc = Get-Service -Name $Target.Service
    if (-not $State.Running -and $svc.Status -ne 'Stopped') {
        Stop-Service -Name $Target.Service -ErrorAction Stop
    }
    elseif ($State.Running -and $svc.Status -eq 'Stopped') {
        Start-Service -Name $Target.Service -ErrorAction Stop
    }
}

function Get-FirewallState {
    param([hashtable]$Target)
    $rule = Get-NetFirewallRule -Name $Target.Name -ErrorAction SilentlyContinue
    if (-not $rule) { return @{ Exists = $false } }
    $app = $rule | Get-NetFirewallApplicationFilter
    @{
        Exists    = $true
        Program   = [string]$app.Program
        Enabled   = ([string]$rule.Enabled -eq 'True')
        Action    = [string]$rule.Action
        Direction = [string]$rule.Direction
    }
}

function Set-FirewallState {
    param([hashtable]$Target, [hashtable]$State)

    # only ever touch rules schizo named. anything else is somebody else's.
    if ($Target.Name -notlike 'schizo-*') { throw "refusing to touch firewall rule $($Target.Name)" }

    Remove-NetFirewallRule -Name $Target.Name -ErrorAction SilentlyContinue
    if (-not $State.Exists) { return }
    # restore can get here with a program path read back from the journal.
    if ($State.Program -notmatch '^[A-Za-z]:\\[^*?]+\.exe$') { throw "won't create a firewall rule for $($State.Program)" }

    $null = New-NetFirewallRule -Name $Target.Name -DisplayName "schizo: block $([IO.Path]::GetFileName($State.Program))" `
        -Group 'schizo' -Description "added by schizo. restore.ps1 removes it." `
        -Direction Outbound -Action Block -Program $State.Program -Profile Any -Enabled True -ErrorAction Stop
}
