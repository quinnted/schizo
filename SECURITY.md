# Security

schizo runs as Administrator, so bugs in it are worth reporting. Use GitHub's
private vulnerability reporting on this repository ("Security" tab, "Report a
vulnerability"). Please don't open a public issue for something exploitable.

## Where to keep it

Whoever can write to the folder you run schizo from can run code as
Administrator the next time you run it. On your own PC, in your own profile,
that's you. On a shared PC, or if an administrator elevates schizo for a
standard user, put it somewhere only administrators can write (for example
under `C:\Program Files`) and read it there.

## What schizo does to stay boring

- No network access. Nothing is downloaded and nothing is sent. The tests
  fail if shipped code calls `Invoke-WebRequest`, `Invoke-Expression`,
  `Add-Type` and similar. The VM integration tests run with the network
  adapter disconnected. `tools\Test-Sources.ps1` is a maintainer tool that
  checks documentation links; schizo never calls it.
- Rules are `.psd1` data files loaded with `Import-PowerShellDataFile`, which
  rejects code. Registry rules can only write to an explicit list of keys
  (`$AllowedKeys` in `lib\rules.ps1`), and machine environment variables only
  when the name contains `TELEMETRY` or `DO_NOT_TRACK`. Defender, Windows
  Update, firewall, SmartScreen and UAC policies are refused by name, as are
  security services. Firewall programs must be literal paths under a drive, a
  known folder, or the app's install folder.
  This contains mistakes in rules and tampering with the journal. It does not
  make a tampered checkout safe: whoever can edit `rules\` can edit `lib\`.
- `%ProgramFiles%` and friends are resolved through the Windows known-folder
  API, not environment variables. `InstallLocation` values from the registry
  are ignored unless they are local paths, so a planted uninstall entry
  can't make schizo touch a network share.
- The Windows modules it uses (NetSecurity, Appx) are loaded
  by full path from System32 rather than found on `PSModulePath`.
- The backup folder `C:\ProgramData\schizo` is created in one call with an
  ACL that only allows SYSTEM and Administrators. Standard users can create
  folders in `C:\ProgramData`, so if it already exists schizo checks that it
  isn't a link, is owned by SYSTEM, Administrators or TrustedInstaller, and
  that nobody else can write to it. Otherwise it stops.
- `restore.ps1` re-validates every journal record the way rules are
  validated, only removes firewall rules whose names start with `schizo-`,
  and only restores per-user settings for the user who made them.
- Strings from the machine (uninstall entries, extension manifests, registry
  data) have control characters stripped before they reach the console.
- No elevation tricks. Without admin rights it prints one line and exits 2.

## What the backup contains

Only what restore needs: for each thing schizo changed, its path or name, the
value before, the value schizo set, the rule id, a timestamp, and for
per-user settings the user's SID. Firewall rule records contain the program
path, which can include your user name. Nothing is collected about software
schizo doesn't change.
