# C:\ProgramData\schizo\
#   lock                      held while schizo or restore runs
#   runs\<yyyy-MM-dd_HHmmss>Z\journal.jsonl  one line per event, appended
#   restored\<...>            runs that restore.ps1 has fully undone
#
# the journal is append-only json lines. every change is written, with the
# state it replaces, *before* the change is made, and flushed to disk. if
# schizo dies halfway, restore sees a change record without a result, reads
# the live state, and still knows what to put back. a torn last line is
# ignored. no rename dance needed: nothing is ever rewritten.

$script:AdminSids = @(
    'S-1-5-18'          # SYSTEM
    'S-1-5-32-544'      # Administrators
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'  # TrustedInstaller
)

$script:WriteRights = [System.Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, DeleteSubdirectoriesAndFiles, WriteAttributes, Delete, ChangePermissions, TakeOwnership'
# GENERIC_ALL and GENERIC_WRITE. they show up unmapped in inheritable aces
# and FileSystemRights has no names for them.
$script:GenericWrite = 0x10000000 -bor 0x40000000

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# a standard user can create C:\ProgramData\<anything> before schizo ever runs.
# if they own the folder, they own the journal, and restore.ps1 runs elevated
# with whatever the journal says. so: refuse folders we don't trust.
function Test-PrivateDir {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path -Force
    if (-not $item.PSIsContainer) { return "$Path is not a folder" }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return "$Path is a link" }

    $acl = Get-Acl -LiteralPath $Path
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -notin $script:AdminSids) { return "$Path is owned by $($acl.Owner)" }

    foreach ($ace in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($ace.AccessControlType -ne 'Allow') { continue }
        if ($ace.IdentityReference.Value -in $script:AdminSids) { continue }
        if (($ace.FileSystemRights -band $script:WriteRights) -or ([int]$ace.FileSystemRights -band $script:GenericWrite)) {
            $who = try { $ace.IdentityReference.Translate([Security.Principal.NTAccount]).Value } catch { $ace.IdentityReference.Value }
            return "$who can write to $Path"
        }
    }
}

function New-PrivateDir {
    param([string]$Path)

    $sec = New-Object System.Security.AccessControl.DirectorySecurity
    $sec.SetAccessRuleProtection($true, $false)
    foreach ($sid in 'S-1-5-18', 'S-1-5-32-544') {
        $who = New-Object Security.Principal.SecurityIdentifier $sid
        $sec.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule $who, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
    }
    # create the folder with its acl in one call; creating it first and fixing
    # the acl after leaves a window where users inherit write access.
    if ($PSVersionTable.PSEdition -eq 'Core') {
        [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]$Path, $sec)
    }
    else {
        $null = [IO.Directory]::CreateDirectory($Path, $sec)
    }
}

function Get-StateRoot {
    param([string]$Root, [switch]$Create)

    if (-not (Test-Path -LiteralPath $Root)) {
        if (-not $Create) { return $null }
        New-PrivateDir $Root
    }
    $problem = Test-PrivateDir $Root
    if ($problem) { throw "won't use $Root`: $problem" }
    $Root
}

function Lock-StateRoot {
    param([string]$Root)
    try {
        New-Object IO.FileStream (Join-Path $Root 'lock'), 'OpenOrCreate', 'ReadWrite', 'None', 1, 'DeleteOnClose'
    }
    catch [IO.IOException] {
        throw 'another schizo or restore is running.'
    }
}

function Open-Run {
    param([string]$Root)

    $Root = Get-StateRoot $Root -Create
    $lock = Lock-StateRoot $Root
    try {
        $runs = Join-Path $Root 'runs'
        if (-not (Test-Path -LiteralPath $runs)) { $null = New-Item -ItemType Directory -Path $runs }
        # utc, so the names sort in the order the runs happened even across a
        # dst change. restore depends on that order.
        $dir = Join-Path $runs ((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd_HHmmss') + 'Z')
        while (Test-Path -LiteralPath $dir) {
            Start-Sleep -Milliseconds 1100
            $dir = Join-Path $runs ((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd_HHmmss') + 'Z')
        }
        $null = New-Item -ItemType Directory -Path $dir

        $stream = New-Object IO.FileStream (Join-Path $dir 'journal.jsonl'), 'CreateNew', 'Write', 'Read', 4096, 'WriteThrough'
        @{ Root = $Root; Dir = $dir; Stream = $stream; Lock = $lock; Changes = 0 }
    }
    catch {
        $lock.Dispose()
        throw
    }
}

# a run that changed nothing has nothing to restore; don't leave a folder
# behind for every no-op rerun.
function Close-Run {
    param([hashtable]$Run)
    if (-not $Run) { return }
    if ($Run.Stream) { $Run.Stream.Dispose() }
    # best effort: an empty run folder left behind is harmless, an exception here
    # would hide the results of the run.
    if (-not $Run.Changes) { Remove-Item -LiteralPath $Run.Dir -Recurse -Force -ErrorAction SilentlyContinue }
    if ($Run.Lock) { $Run.Lock.Dispose() }
}

function Add-JournalRecord {
    param([hashtable]$Run, [hashtable]$Record)

    $Record['at'] = (Get-Date).ToString('o')
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Record | ConvertTo-Json -Compress -Depth 8) + "`n")
    $Run.Stream.Write($bytes, 0, $bytes.Length)
    $Run.Stream.Flush($true)
    if ($Record.kind -eq 'change') { $Run.Changes++ }
}

# 5.1 has no ConvertFrom-Json -AsHashtable.
function ConvertTo-Hashtable {
    param($InputObject)
    if ($InputObject -is [Management.Automation.PSCustomObject]) {
        $h = @{}
        foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = ConvertTo-Hashtable $p.Value }
        return $h
    }
    if ($InputObject -is [array]) { return , @($InputObject | ForEach-Object { ConvertTo-Hashtable $_ }) }
    $InputObject
}

function Read-Journal {
    param([string]$Path)

    # powershell 7 turns strings that look like dates into DateTime unless told
    # not to, and only 7.5+ can be told. Read-Changes refuses what got mangled.
    $json = @{}
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) { $json.DateKind = 'String' }

    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($Path, [Text.Encoding]::UTF8)) {
        $n++
        if (-not $line.Trim()) { continue }
        try { $record = ConvertTo-Hashtable ($line | ConvertFrom-Json @json) }
        catch { $record = $null }
        if ($record -isnot [hashtable] -or -not $record.kind) { $record = @{ kind = 'damaged'; line = $n } }
        $record
    }
}

# journal records were written by schizo, and the folder is admin-only, but
# restore runs elevated, so it re-checks every target the same way rules are
# checked rather than trusting the file.
function Test-JournalTarget {
    param($Target)

    if ($Target -isnot [hashtable]) { return 'target is not an object' }
    switch ($Target.Type) {
        'registry' {
            $p = @(Test-SetEntry @{ Key = $Target.Key; Value = $Target.Value; Dword = 0 })
            if ($p.Count) { return $p[0] }
            if ($Target.Key -like 'HKCU\*' -and $Target.User -notmatch '^S-1-5-21-[\d-]+$') { return 'per-user record without a user' }
        }
        'service' {
            $p = @(Test-SetEntry @{ Service = $Target.Service; Start = 'Disabled' })
            if ($p.Count) { return $p[0] }
        }
        'firewall' {
            if ($Target.Name -isnot [string] -or $Target.Name -notmatch '^schizo-[a-z0-9.-]+-[^\\/]+\.exe$') { return "bad firewall rule name $($Target.Name)" }
        }
        default { return "unknown target type '$($Target.Type)'" }
    }
}

function Get-ActiveRuns {
    param([string]$Root)
    $runs = Join-Path $Root 'runs'
    if (-not (Test-Path -LiteralPath $runs)) { return }
    Get-ChildItem -LiteralPath $runs -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'journal.jsonl') } | Sort-Object Name
}
