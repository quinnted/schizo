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

To apply the rules:

```powershell
.\schizo.ps1
```

Run that from an Administrator PowerShell.

<<<<<<< HEAD
For the rules that disable an actual feature:
=======
On a shared PC, keep the folder somewhere only administrators can write; see
SECURITY.md.

There is no installer, service, scheduled task, tray icon or account. schizo
runs, changes things, prints what it did and exits. The settings it makes
stay; schizo doesn't.

From the test VM (Windows 11 Pro with Edge, Chrome, Brave, Firefox,
Thunderbird, VS Code, 7-Zip, PowerShell 7 and GitHub CLI installed),
shortened:

```
windows 11 pro 26H2 (26300)
65 apps found

windows
  diagnostic data                     required only
  feedback prompts                    off
  advertising id                      off
  tailored experiences                off
  activity history                    off
  ...
7-zip
  outbound network                    blocked
brave
  usage ping and p3a                  off
  web discovery project               off
google chrome
  visited urls to google              off
  domain reliability reports          off
  ...
microsoft edge
  diagnostic data                     required only
  browsing data for ads and news      off
  ...

needs a human
  google chrome: usage statistics and crash reports
    chrome://settings/syncSetup > turn off "Help improve Chrome's features and
    performance". The policy for this only works on managed PCs.

54 changed
0 already set
0 failed
1 need a human
10 aggressive rules not applied (-Aggressive)
55 apps have no rules (-ShowUnknown)

backup:
  C:\ProgramData\schizo\runs\2026-10-28_030131Z

done.
```

Browser extensions with broad access get their own list: names and what
they can do, nothing else, and nothing is removed or disabled. Extensions a
school or company installed through browser policy are listed separately:

```
browser extensions with broad access (no rules; not touched)
  chrome   Tampermonkey [Default]
           all sites, intercepts requests

managed browser extensions with broad access (installed by policy; not touched)
  chrome   Lightspeed Filter Agent [Profile 7]
           all sites, browsing history, controls the proxy, manages other
           extensions, intercepts requests
```

Run it again whenever you like. The second run on that VM printed
`0 changed` and `54 already set`, and made no backup folder. If an update
puts something back, the next run sets it again.

| Option | |
|---|---|
| `-Audit` | Show what would change. Changes nothing, writes nothing. |
| `-Aggressive` | Also apply rules that cost a feature (voice typing, Phone Link, search suggestions, OneDrive results in Start search, Edge's coupons, third-party cookies, the DiagTrack service, ...). Each one says what it breaks. |
| `-ShowUnknown` | List installed applications that no rule covers. Runtimes, drivers, Store packages with nothing in the Start menu, parts of Windows and Steam games are counted, not listed. |
| `-ShowUnknownAll` | List everything the inventory found that no rule covers, each marked with what schizo took it for. |

Exit codes: 0 fine, 1 something failed, 2 didn't run (not admin, broken
rules, untrusted backup folder, managed machine).

## Restoring
>>>>>>> 94f7f99 (clean up real machine audit output)

```powershell
.\schizo.ps1 -Aggressive
```

## what it covers

There are currently 80 rules.

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

<<<<<<< HEAD
```text
C:\ProgramData\schizo\runs\
```
=======
- Applies the rules it has. It doesn't find telemetry nobody has documented,
  and it can't see what an app sends over HTTPS.
- Per-user settings are applied to the account that runs schizo. If an
  administrator elevates for a standard user, those rules are skipped and
  schizo says so.
- Inventory is the uninstall registry, Store packages, services and known
  install paths. Portable apps in random folders aren't seen.
- Windows 11 24H2 (build 26100) and later. Server and managed (domain-joined
  or MDM-enrolled) machines are refused; `-Audit` still works. Applying and
  restoring has been tested on Windows 11 26H2 (build 26300) Home and Pro in
  VMs. 25H2 (26200) has only had `-Audit` runs, because Microsoft no longer
  offers 25H2 install media; 24H2 Home and Pro are out of servicing and
  aren't targeted.
- Windows protects a few policy values from everything but Group Policy (on
  Pro, the widgets one). schizo doesn't fight that; such settings are in
  `docs\not-shipped.md`.
- Updates can put things back. Run schizo again after big updates.
- Browser extension report reads the current user's Chrome, Edge, Brave and
  Firefox profiles and lists permissions as requested in the manifest. It
  doesn't know whether you withheld site access. "Installed by policy" comes
  from the browser's own record of where an extension came from; when a
  profile's prefs can't be read, nothing is claimed about the source.
>>>>>>> 94f7f99 (clean up real machine audit output)

## things schizo does not change

Defender, Windows Update, Windows Firewall configuration, SmartScreen and UAC are outside the allowed rule paths.

It also does not uninstall software, remove browser extensions, edit the hosts file or start blocking IP addresses.

Unknown software is left alone.

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

Domain-joined and MDM-managed machines are audit-only.

And obviously none of this deletes data a company already has.

## tests

204 unit tests currently pass under Windows PowerShell 5.1 and PowerShell 7.

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
