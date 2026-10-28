# schizo

Windows and the software on it talk too much.

schizo looks at what's installed and applies the privacy settings in this
repository that match your machine. Every setting has a documented source, a
note on what it breaks, and a backup so `restore.ps1` can put it back.

It doesn't guess. Software it has no rule for is listed and left alone. Where
the only off switch is a checkbox in an app or a setting on a vendor's
website, it tells you where to click instead of poking at undocumented
registry values.

Read the code before you run it. You shouldn't run random PowerShell from the
internet as Administrator, and this is random PowerShell from the internet.

## Running it

```powershell
git clone https://github.com/<you>/schizo
cd schizo
# read schizo.ps1, lib\ and rules\
.\schizo.ps1 -Audit -ShowUnknown   # what would change; no admin needed
.\schizo.ps1                       # from an Administrator PowerShell
```

If PowerShell answers "running scripts is disabled on this system", that's
the Windows default (`Restricted`). Allow local scripts for that one window
only:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

It lasts until you close the window and doesn't change your machine. If you
downloaded a zip instead of cloning, Windows marks every file as downloaded
and `RemoteSigned` still refuses them; read them, then run
`Get-ChildItem -Recurse | Unblock-File` in the folder.

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
    chrome://settings/syncSetup > turn off "Help improve Chrome's features and performance". The policy for this only works on managed PCs.

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

Browser extensions that can read every site get their own list (names,
profiles and permissions only; nothing is removed or disabled):

```
browser extensions with broad access (no rules; not touched)
  chrome   Tampermonkey [Default]
           all sites, intercepts requests
```

Run it again whenever you like. The second run on that VM printed
`0 changed` and `54 already set`, and made no backup folder. If an update
puts something back, the next run sets it again.
| Option | |
|---|---|
| `-Audit` | Show what would change. Changes nothing, writes nothing. |
| `-Aggressive` | Also apply rules that cost a feature (voice typing, Phone Link, search suggestions, OneDrive results in Start search, Edge's coupons, third-party cookies, the DiagTrack service, ...). Each one says what it breaks. |
| `-ShowUnknown` | List installed software that no rule covers. |

Exit codes: 0 fine, 1 something failed, 2 didn't run (not admin, broken
rules, untrusted backup folder, managed machine).

## Restoring

```powershell
.\restore.ps1                      # from an Administrator PowerShell
```

Restore puts back the state from before schizo *first* changed each thing,
across any number of runs. A registry value that didn't exist is deleted
again, along with any keys schizo had to create. A service that was Manual
goes back to Manual. Firewall rules schizo created are removed.

If you changed something yourself after schizo set it, restore leaves it
alone and says so. `-Force` restores it anyway. `-Audit` shows what restore
would do; unlike `schizo.ps1 -Audit` it needs admin, because the backups are
admin-only.

Some things can't be undone by anyone: data a vendor already received, and
Recall snapshots that Windows deletes when snapshots are turned off.

## What it changes

Today: Windows, Edge, Chrome, Brave, Firefox, Thunderbird, Microsoft 365,
OneDrive, VS Code, Visual Studio, Zoom, 7-Zip, and the telemetry switches of
the .NET SDK, PowerShell 7, Azure CLI, Azure Functions Core Tools and GitHub
CLI. Read `rules\` for the full list; each rule says why it exists, what it
breaks, and links to the vendor's documentation.

How:

- **policies** the vendor documents (registry values under `...\Policies\...`).
  Browsers and Windows will say some settings are "managed by your
  organization". That's what a policy looks like from the inside.
- **environment variables** command-line tools document as their opt-out.
- **one service**, DiagTrack, with `-Aggressive` only.
- **outbound firewall rules** for programs that have no business on the
  network. Currently 7-Zip, which has no updater and no HTTP or socket code.

What it won't do: change Defender, Windows Update, Windows Firewall's own
settings, SmartScreen, UAC, or the crash reporting Microsoft uses for
security fixes. Those stay exactly as they are; a rule that tries to modify
them is rejected when the rules load. It also won't edit the hosts file,
block IP addresses, uninstall your software or remove browser extensions.
`docs\not-shipped.md` lists the popular tweaks that aren't here and why.

### Levels

`verified`: documented by the vendor, and what it costs is small and listed
in the rule. Applied by default.

`aggressive`: documented, but it switches off something people use on
purpose. Only with `-Aggressive`.

Undocumented registry folklore isn't a level. It isn't here.

### Home edition

Microsoft documents most of these Windows policies for Pro, Enterprise and
Education, and says nothing either way about Home. schizo applies them on
Home anyway (writing a policy Windows doesn't read is harmless) and says so
in its output; it has only been tested on Pro. Rules Microsoft explicitly limits to
Enterprise/Education, like turning diagnostic data fully off, are only
applied there.

## Backups

`C:\ProgramData\schizo\runs\<utc date>_<time>Z\journal.jsonl`, one folder per run
that changed something. The folder is readable by SYSTEM and Administrators
only. Each line records one change: what was changed, the value before, the
value after, and the rule. Nothing else about your machine is stored, and
nothing leaves it. After a complete restore the runs move to
`C:\ProgramData\schizo\restored\`. Delete that whenever you like.

Changes are written to the journal before they're made, so a crash or a
closed window halfway through leaves a backup that restore still
understands.

## Limits

- Applies the rules it has. It doesn't find telemetry nobody has documented,
  and it can't see what an app sends over HTTPS.
- Per-user settings are applied to the account that runs schizo. If an
  administrator elevates for a standard user, those rules are skipped and
  schizo says so.
- Inventory is the uninstall registry, Store packages, services and known
  install paths. Portable apps in random folders aren't seen.
- Windows 11 24H2 (build 26100) and later. Server and managed (domain-joined
  or MDM-enrolled) machines are refused; `-Audit` still works. Applying and
  restoring has been tested on Windows 11 Pro build 26300 (it reports itself
  as 26H2) in a VM. On 26200 Home only `-Audit` has been run, and 24H2 hasn't
  been tried.
- Windows protects a few policy values from everything but Group Policy (the
  widgets one, for example). schizo doesn't fight that; such settings are in
  `docs\not-shipped.md`.
- Updates can put things back. Run schizo again after big updates.
- Browser extension report reads the current user's Chrome, Edge, Brave and
  Firefox profiles and lists permissions as requested in the manifest. It
  doesn't know whether you withheld site access.

## Tests

Unit tests run anywhere and only touch a scratch key under `HKCU` and a temp
folder. Everything that changes HKLM, services or the firewall is tested in a
throwaway Windows VM with its network unplugged: apply, apply again, restore,
drift, existing policies, a write Windows refuses, untrusted backup folders,
and a comparison of every target, also through `reg.exe` and `sc.exe`, against
the state before the first run. With the rules applied, `chrome://policy`,
`edge://policy`, `brave://policy` and Firefox's `about:policies` showed every
policy accepted.
Each rule's `Tested` field says what was actually checked for it. See
CONTRIBUTING.md.

## Contributing

New rules need evidence. CONTRIBUTING.md says what that means.

## License

MIT.
