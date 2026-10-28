$script:RuleFields = 'Id', 'App', 'Name', 'State', 'Set', 'Unless', 'Level', 'Why', 'Breaks', 'Source', 'Tested', 'Reviewed', 'Edition', 'MinBuild'
$script:RequiredRuleFields = 'Id', 'App', 'Name', 'State', 'Set', 'Level', 'Why', 'Breaks', 'Source', 'Tested', 'Reviewed'
# advice rules change nothing. they tell a human about a documented opt-out
# that only exists as a checkbox in an app or a setting on a website.
$script:AdviceFields = 'Id', 'App', 'Name', 'Advice', 'Why', 'Source', 'Reviewed', 'Edition', 'MinBuild'
$script:AppFields = 'Name', 'Uninstall', 'Publisher', 'File', 'Appx', 'Service'
$script:Editions = 'home', 'pro', 'education', 'enterprise'

# the registry keys rules may write to, exactly; an entry ending in \ also
# covers everything under it. an allowlist, because even policy keys hold
# things that launch code (Policies\Explorer\Run, extension force-install
# lists, logon scripts). a rule for a new key means adding it here, and that
# gets reviewed as the security change it is.
$script:AllowedKeys = @(
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\System'
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    'HKCU\Software\Policies\Microsoft\Windows\CloudContent'
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
    'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer'
    'HKCU\Software\Policies\Microsoft\Windows\CurrentVersion\AccountNotifications'
    'HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows'
    'HKLM\SOFTWARE\Policies\Microsoft\InputPersonalization'
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput'
    'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    'HKCU\Control Panel\International\User Profile'
    'HKLM\SOFTWARE\Policies\Microsoft\Edge'
    'HKLM\SOFTWARE\Policies\Google\Chrome'
    'HKLM\SOFTWARE\Policies\BraveSoftware\Brave'
    'HKLM\SOFTWARE\Policies\Mozilla\Firefox'
    'HKLM\SOFTWARE\Policies\Mozilla\Firefox\FirefoxHome'
    'HKLM\SOFTWARE\Policies\Mozilla\Firefox\FirefoxSuggest'
    'HKLM\SOFTWARE\Policies\Mozilla\Thunderbird'
    'HKCU\Software\Policies\Microsoft\office\common\clienttelemetry'
    'HKCU\Software\Policies\Microsoft\office\16.0\common\privacy'
    'HKLM\SOFTWARE\Policies\Microsoft\OneDrive'
    'HKLM\SOFTWARE\Policies\Microsoft\VSCode'
    'HKLM\SOFTWARE\Policies\Microsoft\VisualStudio\SQM'
    'HKLM\SOFTWARE\Policies\Zoom\Zoom Meetings\General'
    'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
)
# machine environment variables can redirect code (PATH, PSModulePath,
# COMSPEC). only telemetry switches are allowed there.
$script:EnvironmentKey = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
$script:EnvironmentNames = '^[A-Z0-9_]*(TELEMETRY|DO_NOT_TRACK)[A-Z0-9_]*$'

# inside the allowed roots: things a privacy rule is never allowed to touch,
# no matter how good the evidence looks. turning these off trades security
# for silence.
$script:Untouchable = @(
    @{ Kind = 'registry'; Pattern = '^HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows Defender(\\|$)' }
    @{ Kind = 'registry'; Pattern = '^HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows Defender Security Center(\\|$)' }
    @{ Kind = 'registry'; Pattern = '^HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\WindowsUpdate(\\|$)' }
    @{ Kind = 'registry'; Pattern = '^HKLM\\SOFTWARE\\Policies\\Microsoft\\WindowsFirewall(\\|$)' }
    @{ Kind = 'registry'; Pattern = '^HKLM\\SOFTWARE\\Policies\\Microsoft\\Windows\\System$' ; Value = '^(EnableSmartScreen|ShellSmartScreenLevel)$' }
    @{ Kind = 'registry'; Pattern = '^HKLM\\SOFTWARE\\Policies\\Microsoft\\(Edge|MicrosoftEdge)(\\|$)'; Value = '^SmartScreen' }
    @{ Kind = 'registry'; Pattern = '^HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System(\\|$)' }
    @{ Kind = 'service'; Pattern = '^(WinDefend|WdNisSvc|WdNisDrv|WdFilter|WdBoot|Sense|SecurityHealthService|wscsvc|mpssvc|BFE|wuauserv|UsoSvc|WaaSMedicSvc|BITS|CryptSvc|TrustedInstaller|EventLog|AppIDSvc|SgrmBroker|DoSvc)$' }
)

# the only %VARIABLES% a rule path may use, resolved through the known-folder
# api rather than the environment, which the user running schizo controls.
$script:KnownFolders = @{
    ProgramFiles        = 'ProgramFiles'
    'ProgramFiles(x86)' = 'ProgramFilesX86'
    ProgramData         = 'CommonApplicationData'
    LOCALAPPDATA        = 'LocalApplicationData'
    APPDATA             = 'ApplicationData'
    SystemRoot          = 'Windows'
}
function Import-Rules {
    <#
    .SYNOPSIS
    Loads and validates every rules\*.psd1 file. Throws with all problems listed if anything is wrong.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $apps = @{ windows = @{ Name = 'Windows' } }
    $rules = New-Object System.Collections.Generic.List[hashtable]
    $problems = New-Object System.Collections.Generic.List[string]

    # windows first so the output starts with the OS, then vendors alphabetically.
    $files = @(Get-ChildItem -LiteralPath $Path -Filter *.psd1 -File | Sort-Object { $_.Name -ne 'windows.psd1' }, Name)
    if (-not $files) { throw "no rule files in $Path" }

    foreach ($file in $files) {
        # Import-PowerShellDataFile only accepts the restricted data language, so a
        # rule file can't run code. that is most of why rules are psd1 and not ps1.
        try { $data = Import-PowerShellDataFile -LiteralPath $file.FullName }
        catch { $problems.Add("$($file.Name): $($_.Exception.Message)"); continue }

        foreach ($key in $data.Keys) {
            if ($key -notin 'Apps', 'Rules') { $problems.Add("$($file.Name): unknown top-level key '$key'") }
        }

        if ($data.Apps) {
            foreach ($id in $data.Apps.Keys) {
                if ($apps.ContainsKey($id)) { $problems.Add("$($file.Name): app '$id' is defined twice"); continue }
                foreach ($p in (Test-AppDefinition $id $data.Apps[$id])) { $problems.Add("$($file.Name): $p") }
                $apps[$id] = $data.Apps[$id]
            }
        }

        foreach ($rule in @($data.Rules)) {
            if ($rule -isnot [hashtable]) { $problems.Add("$($file.Name): a rule is not a hashtable"); continue }
            $rule['File'] = $file.Name
            $rules.Add($rule)
        }
    }

    $seen = @{}
    foreach ($rule in $rules) {
        foreach ($p in (Test-RuleDefinition $rule $apps)) { $problems.Add("$($rule.File): $p") }
        if ($rule.Id) {
            if ($seen.ContainsKey($rule.Id)) { $problems.Add("$($rule.File): duplicate rule id '$($rule.Id)' (also in $($seen[$rule.Id]))") }
            else { $seen[$rule.Id] = $rule.File }
        }
    }

    if (-not $problems.Count) {
        foreach ($p in (Find-RuleConflicts $rules)) { $problems.Add($p) }
    }

    if ($problems.Count) {
        throw ("rules are broken:`n  " + ($problems -join "`n  "))
    }

    @{ Apps = $apps; Rules = $rules.ToArray() }
}

function Test-AppDefinition {
    param([string]$Id, $App)

    if ($Id -notmatch '^[a-z0-9][a-z0-9-]*$') { "app id '$Id' should be lowercase letters, digits and dashes" }
    if ($App -isnot [hashtable]) { "app '$Id' is not a hashtable"; return }
    foreach ($k in $App.Keys) {
        if ($k -notin $script:AppFields) { "app '$Id' has unknown field '$k'" }
    }
    if (-not ($App.Name -is [string] -and $App.Name)) { "app '$Id' needs a Name" }
    if (-not ($App.Uninstall -or $App.File -or $App.Appx -or $App.Service)) { "app '$Id' has no way to detect it" }
    if ($App.Publisher -and -not $App.Uninstall) { "app '$Id' has Publisher without Uninstall" }
    foreach ($pattern in @($App.Uninstall) + @($App.Publisher)) {
        if ($null -eq $pattern) { continue }
        try { [void][regex]::new($pattern) } catch { "app '$Id' has a bad regex: $pattern" }
    }
    foreach ($f in @($App.File)) {
        if ($null -eq $f) { continue }
        $why = Test-RulePath $f
        if ($why) { "app '$Id' file $why" }
    }
}

function Test-RuleDefinition {
    param([hashtable]$Rule, [hashtable]$Apps)

    $id = if ($Rule.Id) { $Rule.Id } else { '(no id)' }
    $advice = $Rule.ContainsKey('Advice')
    $allowed = if ($advice) { $script:AdviceFields } else { $script:RuleFields }
    $required = if ($advice) { $script:AdviceFields | Where-Object { $_ -notin 'Edition', 'MinBuild' } } else { $script:RequiredRuleFields }
    foreach ($k in $Rule.Keys) {
        if ($k -eq 'File') { continue }
        if ($k -notin $allowed) {
            if ($advice -and $k -in $script:RuleFields) { "rule '$id' has Advice, so it can't have $k" }
            else { "rule '$id' has unknown field '$k'" }
        }
    }
    foreach ($k in $required) {
        if ($null -eq $Rule[$k] -or ($Rule[$k] -is [string] -and -not $Rule[$k].Trim())) { "rule '$id' is missing $k" }
    }
    if ($Rule.Id -and $Rule.Id -notmatch '^[a-z0-9-]+(\.[a-z0-9-]+)+$') { "rule id '$id' should look like app.thing" }
    # the output is two columns; a longer name pushes the second one out of line.
    if ($Rule.Name -is [string] -and $Rule.Name.Length -gt 34) { "rule '$id' Name is longer than 34 characters" }
    if ($Rule.App -and -not $Apps.ContainsKey($Rule.App)) { "rule '$id' refers to unknown app '$($Rule.App)'" }
    if ($Rule.Level -and $Rule.Level -notin 'verified', 'aggressive') { "rule '$id' level must be verified or aggressive" }
    foreach ($s in @($Rule.Source)) {
        if ($null -ne $s -and $s -notmatch '^https://\S+$') { "rule '$id' source is not an https url: $s" }
    }
    if ($Rule.Reviewed) {
        $d = [datetime]::MinValue
        if (-not [datetime]::TryParseExact([string]$Rule.Reviewed, 'yyyy-MM-dd', $null, 'None', [ref]$d)) {
            "rule '$id' Reviewed must be yyyy-MM-dd"
        }
    }
    foreach ($e in @($Rule.Edition)) {
        if ($null -ne $e -and $e -notin $script:Editions) { "rule '$id' has unknown edition '$e'" }
    }
    if ($null -ne $Rule.MinBuild -and $Rule.MinBuild -isnot [int]) { "rule '$id' MinBuild must be a number" }
    if ($Rule.Unless) {
        $why = Test-RulePath $Rule.Unless -AllowDir
        if ($why) { "rule '$id' Unless $why" }
    }

    if ($advice) { return }
    $sets = @($Rule.Set)
    if (-not $sets.Count) { return }
    foreach ($set in $sets) {
        if ($set -isnot [hashtable]) { "rule '$id' has a Set entry that is not a hashtable"; continue }
        foreach ($p in (Test-SetEntry $set)) { "rule '$id': $p" }
    }
}

function Get-SetKind {
    param([hashtable]$Set)
    $kinds = @()
    if ($Set.ContainsKey('Key')) { $kinds += 'registry' }
    if ($Set.ContainsKey('Service')) { $kinds += 'service' }
    if ($Set.ContainsKey('BlockOutbound')) { $kinds += 'firewall' }
    if ($kinds.Count -eq 1) { $kinds[0] }
}

function Test-SetEntry {
    param([hashtable]$Set)

    $kind = Get-SetKind $Set
    if (-not $kind) { 'Set entry needs exactly one of Key, Service, BlockOutbound'; return }

    switch ($kind) {
        'registry' {
            foreach ($k in $Set.Keys) { if ($k -notin 'Key', 'Value', 'Dword', 'String') { "unknown registry field '$k'" } }
            if ($Set.Key -isnot [string] -or $Set.Key -notmatch '^(HKLM|HKCU)\\[^\\]') { "registry key must start with HKLM\ or HKCU\: $($Set.Key)" }
            elseif ($Set.Key -match '[*?]|\\\\|\\$|\\\.\.?(\\|$)') { "registry key looks wrong: $($Set.Key)" }
            if (-not ($Set.Value -is [string] -and $Set.Value)) { 'registry Value name is required' }
            elseif ($Set.Value -match '[*?\\]') { "registry value name looks wrong: $($Set.Value)" }
            $hasDword = $Set.ContainsKey('Dword'); $hasString = $Set.ContainsKey('String')
            if ($hasDword -eq $hasString) { 'registry entry needs exactly one of Dword or String' }
            if ($hasDword -and -not ($Set.Dword -is [int] -or $Set.Dword -is [long]) ) { 'Dword must be a number' }
            elseif ($hasDword -and ($Set.Dword -lt 0 -or $Set.Dword -gt [uint32]::MaxValue)) { 'Dword out of range' }
            if ($hasString -and $Set.String -isnot [string]) { 'String must be a string' }
            if ($Set.Key -is [string]) {
                $allowed = @($script:AllowedKeys | Where-Object {
                        if ($_.EndsWith('\')) { $Set.Key.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }
                        else { [string]::Equals($Set.Key, $_, [StringComparison]::OrdinalIgnoreCase) }
                    }).Count
                if (-not $allowed) { "schizo does not write to $($Set.Key) (not an allowed key)" }
                elseif ($Set.Key -eq $script:EnvironmentKey -and $Set.Value -cnotmatch $script:EnvironmentNames) {
                    "only telemetry environment variables are allowed, not $($Set.Value)"
                }
                foreach ($u in $script:Untouchable) {
                    if ($u.Kind -eq 'registry' -and $Set.Key -match $u.Pattern -and (-not $u.Value -or $Set.Value -match $u.Value)) {
                        "schizo does not touch $($Set.Key)"
                    }
                }
            }
        }
        'service' {
            foreach ($k in $Set.Keys) { if ($k -notin 'Service', 'Start') { "unknown service field '$k'" } }
            if ($Set.Service -isnot [string] -or $Set.Service -notmatch '^[A-Za-z0-9_.-]+$') { "bad service name: $($Set.Service)" }
            if ($Set.Start -notin 'Disabled', 'Manual') { 'service Start must be Disabled or Manual' }
            foreach ($u in $script:Untouchable) {
                if ($u.Kind -eq 'service' -and $Set.Service -match $u.Pattern) { "schizo does not touch the $($Set.Service) service" }
            }
        }
        'firewall' {
            foreach ($k in $Set.Keys) { if ($k -ne 'BlockOutbound') { "unknown firewall field '$k'" } }
            $why = Test-RulePath $Set.BlockOutbound -AllowDir
            if ($why) { "BlockOutbound $why" }
            elseif ($Set.BlockOutbound -notmatch '\.exe$') { "BlockOutbound must be an .exe: $($Set.BlockOutbound)" }
        }
    }
}

# the identity of a thing a rule changes, so two rules changing the same thing
# can be caught before either of them runs.
function Get-TargetId {
    param([hashtable]$Target)
    switch ($Target.Type) {
        # HKCU means a different hive for every user; the sid makes it one place.
        'registry' { "registry:$($Target.User)$($Target.Key)\$($Target.Value)".ToLowerInvariant() }
        'service' { "service:$($Target.Service)".ToLowerInvariant() }
        'firewall' { "firewall:$($Target.Name)".ToLowerInvariant() }
    }
}

function Find-RuleConflicts {
    param($Rules)

    $owners = @{}
    foreach ($rule in $Rules) {
        foreach ($set in @($rule.Set)) {
            if ($set -isnot [hashtable]) { continue }
            $kind = Get-SetKind $set
            $key = switch ($kind) {
                'registry' { "registry:$($set.Key)\$($set.Value)".ToLowerInvariant() }
                'service' { "service:$($set.Service)".ToLowerInvariant() }
                'firewall' { "firewall:$($rule.App):$($set.BlockOutbound)".ToLowerInvariant() }
            }
            if (-not $owners.ContainsKey($key)) { $owners[$key] = @() }
            $owners[$key] += , $rule
        }
    }

    foreach ($key in $owners.Keys) {
        $list = @($owners[$key])
        for ($a = 0; $a -lt $list.Count; $a++) {
            for ($b = $a + 1; $b -lt $list.Count; $b++) {
                $x = $list[$a]; $y = $list[$b]
                if ($x.Id -eq $y.Id) {
                    "rule '$($x.Id)' changes $key twice"
                    continue
                }
                # the only way two rules may share a target is if no machine can
                # match both: disjoint edition lists.
                $ex = @($x.Edition | Where-Object { $_ }); $ey = @($y.Edition | Where-Object { $_ })
                $disjoint = $ex.Count -and $ey.Count -and -not @($ex | Where-Object { $_ -in $ey }).Count
                if (-not $disjoint) { "rules '$($x.Id)' and '$($y.Id)' both change $key" }
            }
        }
    }
}

function Test-RuleApplies {
    param([hashtable]$Rule, [hashtable]$Machine)

    if ($Rule.App -ne 'windows' -and -not $Machine.Found.ContainsKey($Rule.App)) { return $false }
    if ($Rule.Edition -and $Machine.Edition -notin @($Rule.Edition)) { return $false }
    if ($Rule.MinBuild -and $Machine.Build -lt $Rule.MinBuild) { return $false }
    $true
}

# turns a rule's Set entries into concrete targets for this machine:
# expands %folders% and {dir}, names firewall rules, and says what "done"
# looks like.
function Resolve-RuleTargets {
    param([hashtable]$Rule, [hashtable]$Machine)

    foreach ($set in @($Rule.Set)) {
        switch (Get-SetKind $set) {
            'registry' {
                if ($set.ContainsKey('Dword')) { $want = @{ Exists = $true; Kind = 'DWord'; Data = [long]$set.Dword } }
                else { $want = @{ Exists = $true; Kind = 'String'; Data = $set.String } }
                $target = @{ Type = 'registry'; Key = $set.Key; Value = $set.Value; Want = $want }
                if ($set.Key -like 'HKCU\*') { $target.User = $Machine.UserSid }
                $target
            }
            'service' {
                @{ Type = 'service'; Service = $set.Service; Want = @{ Exists = $true; Start = $set.Start; Running = $false } }
            }
            'firewall' {
                $path = Expand-RulePath $set.BlockOutbound $Rule $Machine
                # an exe this version doesn't ship is simply not there to block.
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    $name = 'schizo-' + $Rule.Id + '-' + [IO.Path]::GetFileName($path).ToLowerInvariant()
                    @{ Type = 'firewall'; Name = $name; Program = $path; Want = @{ Exists = $true; Program = $path } }
                }
            }
        }
    }
}

# a path in a rule: {dir}\..., %KnownFolder%\... or a drive path. no
# wildcards, no .., no other variables.
function Test-RulePath {
    param($Path, [switch]$AllowDir)
    if ($Path -isnot [string] -or -not $Path) { return 'must be a path' }
    if ($Path -match '[*?]' -or $Path -match '\\\.\.?(\\|$)') { return "must not contain wildcards or ..: $Path" }
    if ($AllowDir -and $Path -match '^\{dir\}\\[^%{}]+$') { return }
    if ($Path -match '^[A-Za-z]:\\[^%{}]+$') { return }
    if ($Path -match '^%([^%]+)%\\[^%{}]+$' -and $script:KnownFolders.ContainsKey($Matches[1])) { return }
    "must start with a drive, a known folder like %ProgramFiles%, or {dir}: $Path"
}

function Expand-RulePath {
    param([string]$Path, [hashtable]$Rule, [hashtable]$Machine)
    if ($Path.StartsWith('{dir}')) {
        $dir = $null
        if ($Rule) { $dir = $Machine.Found[$Rule.App].Dir }
        if (-not $dir) { throw "don't know where $($Rule.App) is installed" }
        return $dir.TrimEnd('\') + $Path.Substring(5)
    }
    if ($Path -match '^%([^%]+)%(\\.*)$') {
        $folder = $script:KnownFolders[$Matches[1]]
        if (-not $folder) { throw "unknown folder variable in $Path" }
        $base = [Environment]::GetFolderPath([Environment+SpecialFolder]$folder)
        if (-not $base) { throw "this machine has no $($Matches[1]) folder" }
        return $base.TrimEnd('\') + $Matches[2]
    }
    $Path
}