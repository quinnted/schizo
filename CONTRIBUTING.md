# Contributing

The rulebase is the product. A rule ships when someone can show it does what
it says, and that restore undoes it. "Found this on reddit" is a lead, not a
rule; so is "privacy.sexy has it". Trace it to the source.

## Adding a rule

Rules live in `rules\*.psd1`, one file per vendor or area. They are
PowerShell data files: no code, and the loader refuses anything that isn't
plain data.

```powershell
@{
    Apps  = @{
        foo = @{
            Name      = 'Foo Editor'
            Uninstall = '^Foo Editor\b'          # regex on the uninstall DisplayName
            Publisher = '^Foo Ltd$'              # optional, regex on Publisher
            File      = '%ProgramFiles%\Foo\foo.exe'   # and/or a file that exists
        }
    }
    Rules = @(
        @{
            Id       = 'foo.telemetry'
            App      = 'foo'
            Name     = 'telemetry'               # what the output line says
            State    = 'off'                     # ...and its right-hand column
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Foo'; Value = 'DisableTelemetry'; Dword = 1 }
            Why      = 'What this stops, in one or two sentences.'
            Breaks   = 'What stops working. "Nothing." is a valid answer if it is true.'
            Level    = 'verified'
            Source   = 'https://foo.example/docs/admin-policies#disabletelemetry'
            Tested   = 'win11 pro 26200, foo 4.2'
            Reviewed = '2026-10-27'
        }
    )
}
```

`Set` is one entry or a list. Each entry is exactly one of:

| Kind | Fields | Restore puts back |
|---|---|---|
| registry | `Key`, `Value`, `Dword` or `String` | the old value and type, or deletes it and any keys schizo created |
| service | `Service`, `Start` (`Disabled`/`Manual`) | the old start type, and starts it again if it was running |
| firewall | `BlockOutbound` (exe path, `{dir}` = app's install folder) | removes the rule schizo created |

Registry rules can only write to the keys listed in `$AllowedKeys` in
`lib\rules.ps1`. A rule for a new key adds it there, and that part of the PR
gets reviewed as a security change: policy keys also hold things that launch
code. Paths may start with a drive letter, `{dir}`, or one of
`%ProgramFiles%`, `%ProgramFiles(x86)%`, `%ProgramData%`, `%LOCALAPPDATA%`,
`%APPDATA%`, `%SystemRoot%`. `Name` is at most 34 characters so the output
lines up.

Other fields: `Edition` (`home`, `pro`, `education`, `enterprise`) for
edition-gated settings, `MinBuild` for Windows builds, `Unless` for a file
whose presence means someone else already manages this (see
`rules\mozilla.psd1`).

If the only documented control is a checkbox in the app or a setting on the
vendor's website, write an advice rule instead: `Advice = '...'` and no
`Set`, `State`, `Level`, `Breaks` or `Tested`. schizo prints it under
"needs a human".

### What a rule needs to prove

In the PR description:

- product and version you checked
- the exact mechanism (key, value, type, data; or service; or program)
- where it is documented. Vendor docs or the vendor's own source first;
  ADMX files that ship with the product count. Second-hand write-ups are
  leads, not sources.
- what you observed before and after, and how (Settings shows "managed by
  your organization", `edge://policy` shows the value as OK, the request
  stops in a packet capture, ...)
- what breaks
- that `restore.ps1` puts it back (the VM tests do this for you, see below)

`Source` must be an https URL a reviewer can open. `tools\Test-Sources.ps1`
fetches every source, checks Microsoft Learn anchors, and warns when no source
mentions the value a rule sets. It can't check pages that are built by
javascript or that refuse scripts; open those yourself.

### verified or aggressive

`verified`: documented, and what it costs is small and written in `Breaks`.
Applied by default.

`aggressive`: documented, but it switches off something people use on
purpose (voice typing, search suggestions, coupons) or has a reliability
cost. Only applied with `-Aggressive`. `Breaks` must say what.

Anything else is not a rule yet. Put it in `docs\not-shipped.md` with what is
missing.

### Things schizo won't do

Turn off Defender, Windows Update, the firewall, SmartScreen, UAC, certificate
checks or crash reporting used for security fixes. The loader enforces part
of this (`$Untouchable` in `lib\rules.ps1`); review enforces the rest.

Also no hosts-file or IP blocklists, no uninstalling applications, and no
rules for software schizo can't detect. Scheduled tasks aren't a rule kind:
none has met the bar yet, so the code for them isn't here either.

## Code

PowerShell 5.1 and 7, no dependencies, ASCII only. `Set-StrictMode -Version 1`
because rule data is hashtables and missing keys are normal. Keep comments for
things a reader would otherwise get wrong.

## Tests

```powershell
Install-Module Pester -MinimumVersion 5.5 -Scope CurrentUser
Invoke-Pester .\tests
'schizo.ps1', 'restore.ps1', 'lib', 'tools' | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Recurse -Settings .\PSScriptAnalyzerSettings.psd1 }
```

These change nothing outside `HKCU\Software\schizo-test-*` and Pester's temp
folder.

Anything that touches services, the firewall or HKLM runs in a throwaway VM.
Never run the apply/restore tests on a machine you care about.
`tests\vm\Invoke-VmTest.ps1` reverts a VMware snapshot, copies the repo in,
applies every rule, restores, and checks the machine matches what it was
before. Its help text says what the VM needs.
