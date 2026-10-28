# names and versions come from uninstall entries and extension manifests,
# which anyone can write. keep terminal control characters out of the console.
function Format-Untrusted {
    param([string]$Text, [int]$Max = 60)
    $clean = ($Text -replace '\p{C}', '').Trim()
    if ($clean.Length -gt $Max) { $clean = $clean.Substring(0, $Max - 3) + '...' }
    $clean
}

# what actually went wrong, without powershell's "Exception calling X with N
# argument(s)" wrapping around it.
function Get-ErrorText {
    param([Management.Automation.ErrorRecord]$ErrorRecord)
    $e = $ErrorRecord.Exception.GetBaseException()
    if ($e -is [UnauthorizedAccessException] -or $e -is [Security.SecurityException]) { return 'access denied' }
    $e.Message
}

function Format-State {
    param([hashtable]$State)
    if (-not $State -or -not $State.Exists) { return 'not set' }
    # registry data can be written by anyone who can write the key
    if ($State.ContainsKey('Data')) { return "$(Format-Untrusted (@($State.Data) -join ', ') 80) ($($State.Kind))" }
    if ($State.ContainsKey('Start')) { return $State.Start.ToLowerInvariant() }
    if ($State.ContainsKey('Program')) { return "rule for $($State.Program)" }
    'set'
}

function Format-Target {
    param([hashtable]$Target)
    switch ($Target.Type) {
        'registry' { "$($Target.Key)\$($Target.Value)" }
        'service' { "service $($Target.Service)" }
        'firewall' { "firewall rule $($Target.Name)" }
    }
}

# one rule, every target in it. returns what happened; never throws for a
# failure that belongs to this rule, so one broken rule doesn't stop the rest.
function Invoke-Rule {
    param([hashtable]$Rule, [hashtable]$Machine, [hashtable]$Run, $Owned)

    $result = @{ Rule = $Rule; Status = 'already'; Notes = @() }
    $statuses = @()

    try {
        if ($Rule.Unless) {
            $blocker = Expand-RulePath $Rule.Unless $Rule $Machine
            if (Test-Path -LiteralPath $blocker) {
                $result.Status = 'conflict'
                $result.Notes += "$blocker exists and would be overridden; left alone"
                return $result
            }
        }
        $targets = @(Resolve-RuleTargets $Rule $Machine)
    }
    catch {
        $result.Status = 'failed'
        $result.Notes += $_.Exception.Message
        return $result
    }
    if (-not $targets.Count) {
        $result.Status = 'absent'
        return $result
    }

    foreach ($t in $targets) {
        $where = Format-Target $t
        try { $current = Get-TargetState $t }
        catch {
            $statuses += 'failed'
            $result.Notes += "can't read $where`: $(Get-ErrorText $_)"
            continue
        }

        if ($t.Type -eq 'service' -and -not $current.Exists) {
            $statuses += 'absent'
            continue
        }
        if (Test-StateMatch $t.Type $current $t.Want) {
            $statuses += 'already'
            continue
        }
        # a policy value that is there already belongs to whoever put it there,
        # unless that was schizo (say, an older version of this rule).
        $mine = $Owned -and $Owned.Contains((Get-TargetId $t)) -and @($Owned[(Get-TargetId $t)] | Where-Object { Test-StateMatch $t.Type $current $_ }).Count
        if ($t.Type -eq 'registry' -and $current.Exists -and (Test-PolicyKey $t.Key) -and -not $mine) {
            $statuses += 'conflict'
            $result.Notes += "$where is already $(Format-State $current); left alone"
            continue
        }
        if ($current.Kind -eq 'Unsupported') {
            $statuses += 'failed'
            $result.Notes += "$where has a value type schizo can't back up; left alone"
            continue
        }
        if (-not $Run) {
            $statuses += 'would'
            continue
        }

        $targetRecord = @{}
        foreach ($k in $t.Keys) { if ($k -ne 'Want') { $targetRecord[$k] = $t[$k] } }
        Add-JournalRecord $Run @{ kind = 'change'; rule = $Rule.Id; target = $targetRecord; before = $current; after = $t.Want }
        try {
            Set-TargetState $t $t.Want
            $now = Get-TargetState $t
            if (-not (Test-StateMatch $t.Type $now $t.Want)) { throw "didn't stick, $where is $(Format-State $now)" }
            Add-JournalRecord $Run @{ kind = 'done'; rule = $Rule.Id; target = (Get-TargetId $t); ok = $true }
            $statuses += 'changed'
        }
        catch {
            $msg = Get-ErrorText $_
            # don't leave half a change behind (a key created but no value, a
            # service disabled but still running). the journal still has the
            # record, so restore can finish the job if this fails too.
            try { Set-TargetState $t $current }
            catch { $msg += " (putting it back failed too: $(Get-ErrorText $_))" }
            Add-JournalRecord $Run @{ kind = 'done'; rule = $Rule.Id; target = (Get-TargetId $t); ok = $false; error = $msg }
            $statuses += 'failed'
            $result.Notes += "$where`: $msg"
        }
    }

    foreach ($s in 'failed', 'conflict', 'changed', 'would', 'already', 'absent') {
        if ($statuses -contains $s) { $result.Status = $s; break }
    }
    $result
}

function Invoke-Schizo {
    param(
        [hashtable]$Rulebase,
        [hashtable]$Machine,
        [hashtable]$Run,
        [switch]$Aggressive,
        # target id -> states schizo has set there, from earlier runs' journals
        $Owned = @{}
    )

    foreach ($rule in $Rulebase.Rules) {
        if (-not (Test-RuleApplies $rule $Machine)) { continue }
        if ($rule.Advice) {
            @{ Rule = $rule; Status = 'advice'; Notes = @() }
            continue
        }
        if ($rule.Level -eq 'aggressive' -and -not $Aggressive) {
            @{ Rule = $rule; Status = 'aggressive'; Notes = @() }
            continue
        }
        $userRule = @(@($rule.Set) | Where-Object { $_.Key -like 'HKCU\*' }).Count -gt 0
        if ($userRule -and $Machine.OtherUser) {
            @{ Rule = $rule; Status = 'otheruser'; Notes = @() }
            continue
        }
        $r = Invoke-Rule $rule $Machine $Run $Owned
        if ($Run) {
            Add-JournalRecord $Run @{ kind = 'rule'; rule = $rule.Id; result = $r.Status }
        }
        $r
    }
}

# every target schizo has changed in runs not yet restored: the oldest
# "before" is the original, the newest "after" is what schizo last set.
function Read-Changes {
    param([object[]]$Runs)

    $groups = [ordered]@{}
    $problems = @()
    foreach ($run in $Runs) {
        foreach ($rec in Read-Journal (Join-Path $run.FullName 'journal.jsonl')) {
            if ($rec.kind -eq 'damaged') {
                $problems += "$($run.Name): unreadable journal line $($rec.line), skipped"
                continue
            }
            if ($rec.kind -ne 'change') { continue }
            $bad = Test-JournalTarget $rec.target
            if (-not $bad -and ($rec.before -isnot [hashtable] -or $rec.after -isnot [hashtable])) { $bad = 'missing before/after state' }
            if (-not $bad -and ($rec.before.Data -is [datetime] -or $rec.after.Data -is [datetime])) {
                $bad = 'a value that looks like a date was mangled by this PowerShell; use Windows PowerShell or 7.5+'
            }
            if ($bad) {
                $problems += "$($run.Name): ignored a change record: $bad"
                continue
            }
            $id = Get-TargetId $rec.target
            # every value schizo ever wrote here counts as schizo's, including
            # writes that reported failure: a service can end up disabled even
            # though stopping it failed.
            if (-not $groups.Contains($id)) {
                $groups[$id] = @{ Target = $rec.target; Rule = $rec.rule; Original = $rec.before; Last = $rec.after; Set = @($rec.after) }
            }
            else {
                $groups[$id].Last = $rec.after
                $groups[$id].Set += $rec.after
            }
        }
    }
    @{ Groups = $groups; Problems = $problems }
}

# puts each target back the way it was before schizo first touched it. if
# the live state still matches what schizo set, restore the original. if it
# matches neither, somebody changed it since, and restore leaves it alone
# unless -Force.
function Invoke-Restore {
    param([string]$Root, [switch]$Force, [switch]$Audit)

    $runs = @(Get-ActiveRuns $Root)
    $out = @{ Runs = @($runs | ForEach-Object { $_.Name }); Items = @(); Problems = @() }
    if (-not $runs.Count) { return $out }

    $changes = Read-Changes $runs
    $groups = $changes.Groups
    $out.Problems = $changes.Problems
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    # newest first, so values inside a key schizo created go before the key.
    $ids = @($groups.Keys)
    [array]::Reverse($ids)
    foreach ($id in $ids) {
        $g = $groups[$id]
        $item = @{ Rule = $g.Rule; Target = $g.Target; Status = ''; Note = '' }
        if ($g.Target.User -and $g.Target.User -ne $me) {
            # HKCU here is a different hive from the one schizo changed.
            $item.Status = 'otheruser'
            $item.Note = "per-user setting of $(Get-AccountName $g.Target.User); run restore as that user"
            $out.Items += $item
            continue
        }
        try {
            $current = Get-TargetState $g.Target
            $schizos = @($g.Set | Where-Object { Test-StateMatch $g.Target.Type $current $_ }).Count -gt 0
            if (Test-StateMatch $g.Target.Type $current $g.Original) {
                $item.Status = 'already'
                # the value is gone but a key schizo created for it may not be.
                if ($g.Original.Missing -and (Test-Path -LiteralPath ('Registry::' + ($g.Original.Missing -replace '^HKLM', 'HKEY_LOCAL_MACHINE' -replace '^HKCU', 'HKEY_CURRENT_USER')))) {
                    if ($Audit) { $item.Status = 'would' }
                    else { Set-TargetState $g.Target $g.Original; $item.Status = 'restored' }
                }
            }
            elseif ($g.Target.Type -eq 'service' -and -not $current.Exists) {
                $item.Status = 'gone'
                $item.Note = 'no longer exists'
            }
            elseif ($schizos -or $Force) {
                if ($Audit) { $item.Status = 'would' }
                else {
                    Set-TargetState $g.Target $g.Original
                    $now = Get-TargetState $g.Target
                    if (-not (Test-StateMatch $g.Target.Type $now $g.Original)) { throw "didn't stick, now $(Format-State $now)" }
                    $item.Status = 'restored'
                }
            }
            else {
                $item.Status = 'drifted'
                $item.Note = "is $(Format-State $current), schizo set $(Format-State $g.Last), was $(Format-State $g.Original)"
            }
        }
        catch {
            $item.Status = 'failed'
            $item.Note = Get-ErrorText $_
        }
        $out.Items += $item
    }

    # a run is only archived when every change in every run is accounted
    # for. anything unread, skipped or refused keeps the backups where they
    # are, because archived runs are no longer consulted.
    $unfinished = @($out.Items | Where-Object { $_.Status -in 'failed', 'drifted', 'otheruser' }).Count + $out.Problems.Count
    if (-not $Audit -and -not $unfinished) {
        $done = Join-Path $Root 'restored'
        if (-not (Test-Path -LiteralPath $done)) { $null = New-Item -ItemType Directory -Path $done }
        # newest first: if a move fails halfway, the runs left behind are the
        # oldest ones, and they hold the true originals.
        $moved = 0
        foreach ($run in ($runs | Sort-Object Name -Descending)) {
            try {
                Move-Item -LiteralPath $run.FullName -Destination (Join-Path $done $run.Name)
                $moved++
            }
            catch {
                $out.Problems += "couldn't move $($run.Name) to restored\: $($_.Exception.Message)"
                break
            }
        }
        if ($moved -eq $runs.Count) { $out.Archived = $true }
    }
    $out
}

function Get-AccountName {
    param([string]$Sid)
    try { (New-Object Security.Principal.SecurityIdentifier $Sid).Translate([Security.Principal.NTAccount]).Value }
    catch { $Sid }
}