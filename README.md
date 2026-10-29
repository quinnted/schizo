# schizo

PowerShell script for turning off Windows and application telemetry I could verify.

It checks what is installed, applies the matching rules in `rules\`, saves the old values, and exits.

Nothing is downloaded while it runs and nothing is sent anywhere.

Windows PowerShell 5.1 and PowerShell 7 are supported.

## run

Read the script first.

```powershell
git clone https://github.com/quinnted/schizo
cd schizo
.\schizo.ps1 -Audit -ShowUnknown
```

`-Audit` does not change anything and does not need Administrator.

`-ShowUnknown` lists installed applications no rule covers. Runtimes, drivers, Store packages with nothing in the Start menu, parts of Windows and Steam games are only counted. `-ShowUnknownAll` lists those too.

To apply the rules:

```powershell
.\schizo.ps1
```

Run that from an Administrator PowerShell.

For the rules that disable an actual feature:

```powershell
.\schizo.ps1 -Aggressive
```

## what it covers

There are currently 76 rules that change something (12 of them only with `-Aggressive`) and 5 that just print where the setting is.

Windows settings include diagnostic data, advertising ID, tailored experiences, activity history, Recall, search/cloud suggestions, CEIP, typing data, Delivery Optimization and some Start menu junk.

There are also rules for:

- Edge
- Chrome
- Brave
- Firefox
- Thunderbird
- Microsoft 365
- OneDrive
- VS Code
- Visual Studio
- Zoom
- 7-Zip
- .NET
- PowerShell 7
- Azure CLI
- Azure Functions Core Tools
- GitHub CLI

The rule files are under `rules\`.

Each rule has its source, what it changes and whether it has actually been tested.

If I could not find a reliable way to change something, it is not changed. In a few cases schizo prints the setting you need to change yourself.

`docs\not-shipped.md` has some of the things I looked at and left out.

## restore

```powershell
.\restore.ps1
```

schizo records the original state before the first change.

Restore uses that state rather than assuming what the Windows default was.

If you changed the same setting yourself afterwards, restore leaves it alone and reports it.

Use:

```powershell
.\restore.ps1 -Force
```

if you want the old value restored anyway.

Backups are under:

```text
C:\ProgramData\schizo\runs\
```

## things schizo does not change

Defender, Windows Update, Windows Firewall configuration, SmartScreen and UAC are outside the allowed rule paths.

It also does not uninstall software, remove browser extensions, edit the hosts file or start blocking IP addresses.

Unknown software is left alone.

Browser extensions with broad access (all sites, history, proxy and so on) in Chrome, Edge, Brave and Firefox are listed with what they can do. Extensions installed by browser policy, for example by a school, are listed separately. Nothing is removed or disabled.

## repeated runs

Running it more than once is fine.

Already-applied rules are skipped. If Windows or an application update changes one of them back, running schizo again applies it again.

## home

Home is annoying.

Microsoft documents a number of these policies for Pro, Enterprise and Education but not Home.

26H2 Home and Pro have both been tested for applying and restoring the rules. Some policies work on Home. Some appear to be ignored.

schizo tells you when it is applying one of those.

## limits

This is not packet inspection and it does not reverse engineer applications.

It cannot tell you what an application sends inside HTTPS.

It cannot disable telemetry nobody has found yet.

Portable applications in random directories may not show up in inventory.

Windows 11 24H2 (build 26100) or later. Windows Server, domain-joined and MDM-managed machines are audit-only.

Applying and restoring has only been tested on 26H2 (build 26300) VMs. 25H2 (26200) has had `-Audit` runs on real hardware but no apply/restore. Enterprise and Education have not been tested at all.

And obviously none of this deletes data a company already has.

## tests

266 unit tests currently pass under Windows PowerShell 5.1 and PowerShell 7.

System-changing tests are run in throwaway Windows 11 26H2 Home and Pro VMs.

The integration tests cover applying rules, running them again, restore, user changes made after schizo ran, existing policy values, failed writes, concurrent runs and backup permissions.

Browser policies were also checked through the browsers' own policy pages.

Not every application rule has been exercised yet. The `Tested` field in each rule says what has.

Run the tests with:

```powershell
Invoke-Pester .\tests
```

## contributing

If you add a rule, there needs to be evidence for it.

See `CONTRIBUTING.md`.

## license
GNU General Public License v3.0
