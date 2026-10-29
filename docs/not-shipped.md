# Looked at, not shipped

Things that show up in other privacy scripts, or that were researched for
schizo, and why they are not rules. Some of these are fine ideas that just
lack evidence; a few are actively harmful. If you have the evidence that
would change one of these, open a PR with it (see CONTRIBUTING.md).

Last reviewed 2026-10-27 against Windows 11 25H2 and current vendor docs.

## Windows

| Thing | Why not |
|---|---|
| `AllowTelemetry = 0` on Home/Pro | Microsoft documents that Home and Pro treat 0 as 1. Setting it and printing "telemetry off" would be a lie. schizo sets 1 there and 0 only on Enterprise/Education. |
| `DisableDeviceDelete`, `DisableDiagnosticDataViewer` | Both work against you: they stop you deleting or viewing your own diagnostic data. |
| `LimitDiagnosticLogCollection`, `LimitDumpCollection` | Only matter when optional diagnostic data is on, which the diagnostic data rule already prevents. |
| `AITEnable`, `DisableInventory` (AppCompat) | Microsoft says both are moot once CEIP is off, which `windows.ceip` does. Learn also doesn't state the data values. |
| `TurnOffWindowsCopilot` | Deprecated. Microsoft says it doesn't apply to the current Copilot app. The documented ways to get rid of Copilot are uninstalling the app or AppLocker. |
| `RemoveMicrosoftCopilotApp` | Enterprise/Education only, and only under narrow conditions. |
| `AllowRecallEnablement = 0` | Removes the Recall bits from the OS. Restoring the policy doesn't put them back without re-adding the optional feature, so restore couldn't undo it. `DisableAIDataAnalysis` (no snapshots) is shipped instead. |
| `DisableWindowsConsumerFeatures` and the other CloudContent/Spotlight policies on Home/Pro | Microsoft marks them Enterprise/Education only. schizo applies them on those editions and nowhere else. |
| `ConnectedSearchUseWeb`, `DisableWebSearch`, `DisableSearchBoxSuggestions` as "no Bing in Start" | The first is Enterprise/Education only. `DisableWebSearch` is scoped to legacy Windows Desktop Search in the ADMX. `DisableSearchBoxSuggestions` is documented for File Explorer's search box only. There is no documented way to remove web results from Start search on Home or Pro. |
| `ContentDeliveryManager\SubscribedContent-*`, `SilentInstalledAppsEnabled` and friends | No Microsoft documentation. They are reverse-engineered values that change between builds. |
| `HKCU\...\AdvertisingInfo\Enabled` | Not documented. The documented machine policy is shipped. |
| `HKCU\...\Input\TIPC\Enabled` | No Microsoft source. |
| `RestrictImplicitTextCollection` / `RestrictImplicitInkCollection` | Documented, but turning them on deletes the local learned dictionary, which restore can't bring back. |
| Siuf `NumberOfSIUFInPeriod` / `PeriodInNanoSeconds` | Microsoft calls them DWORDs while its own example values don't fit in a DWORD. `DoNotShowFeedbackNotifications` covers the same ground. |
| Widgets: `Dsh\AllowNewsAndInterests = 0` | Documented, but on 26H2 Pro Windows refuses to let anything but Group Policy write that one value or delete its key: `reg add` as Administrator gets Access denied, while other values in the same key, and the same name elsewhere, write fine. On 26H2 Home the same write succeeds. A rule that fails on Pro and does something undocumented on Home isn't one to ship. Use Settings > Personalisation > Taskbar > Widgets. |
| `DisableOneSettingsDownloads` | Microsoft warns that apps using the service may stop working, and stale configuration can affect update safeguards. |
| Turning Windows Error Reporting off (`Disabled = 1`, WerSvc) | Microsoft uses crash reports to find security bugs and says not to disable the service. schizo only declines follow-up data requests. |
| `DisableLocation`, `AllowFindMyDevice = 0` | Location breaks a lot of unrelated things; Find My Device is anti-theft. Both are better decided by a person in Settings. |
| `dmwappushservice` | Needed for MDM. Little value on an unmanaged PC. |
| CEIP-era scheduled tasks (Consolidator, UsbCeip, Autochk\Proxy, DiskDiagnosticDataCollector) | Only documented in VDI image guidance, and they do nothing once CEIP is off. Disabling them would be activity, not privacy. No scheduled task has met the bar, so schizo has no code for changing them. |
| `Microsoft Compatibility Appraiser` task | Windows Update uses its output for upgrade safeguard holds. Disabling it can get you an upgrade that is known to break your hardware. |
| `DmClient`, `DmClientOnScenarioDownload` tasks | No documentation found for what they do. |
| Delivery Optimization `DODownloadMode = 99` or `100` | Microsoft's current FAQ says 0 for "no peering"; 99 is for offline devices and 100 is deprecated. |
| `NoActiveProbe`, `NoCloudApplicationNotification` | Break connectivity detection and push notifications. |
| Defender cloud protection, sample submission, SmartScreen | Security features. schizo refuses rules that touch Defender, Windows Update, the firewall service or UAC; see `$Untouchable` in lib\rules.ps1. |
| hosts-file blocklists, IP blocklists for Microsoft endpoints | Hosts files don't do wildcards, resolved IPs go stale, and several endpoints carry required traffic (updates, activation, certificate revocation). Disabling collection at the source is the honest version. |

## Browsers

| Thing | Why not |
|---|---|
| Chrome `MetricsReportingEnabled` | Chrome ignores it unless the PC is domain-joined or enrolled. It would make Chrome say "managed" and do nothing. schizo prints where the setting is instead. |
| Chrome `GenAiDefaultSettings` | Only honored from Google's cloud admin console. |
| Chrome `PrivacySandbox*`, `SafeBrowsingExtendedReportingEnabled` | Deprecated / no effect in current versions. |
| Chrome per-feature AI policies (`GeminiSettings`, `HelpMeWriteSettings`, ...) | Real, but the values differ per policy and change often. Not verified closely enough yet. |
| `ChromeVariations` | About remote configuration, not telemetry, and value 2 can block security fixes delivered as variations. |
| Edge `DiagnosticData = 0` | Microsoft labels it not recommended; it also stops required data. 1 is shipped. |
| Edge `ExperimentationAndConfigurationServiceControl = 0` | Drops site compatibility fixes. 1 is shipped. |
| Edge `MetricsReportingEnabled`, `EdgeCollectionsEnabled`, `EdgeFollowEnabled`, `AddressBarMicrosoftSearchInBingProviderEnabled` | Obsolete. |
| Edge Copilot policies (`CopilotPageContext`, `Microsoft365CopilotChatIconEnabled`, ...) | Work/school (Entra) profiles only. Nothing documented hides Copilot in Edge on a home PC. |
| Edge `NewTabPageQuickLinksEnabled = 0` | Removes your own quick links too, not just sponsored ones. |
| Edge `TextPredictionEnabled` | Plausible, but not reviewed closely enough to call verified. |
| Firefox `DisablePocket` | In the schema, no implementation. |
| Firefox `Preferences` (crash auto-submit etc.) | Needs REG_MULTI_SZ JSON, which schizo doesn't write yet, and the shipped default is already off. |
| Brave `MetricsReportingEnabled` | Other projects say Brave honors it on unmanaged PCs and that it controls crash reports there. The source found for that doesn't show either. Not shipped until someone shows it. |
| Brave `BraveWalletDisabled`, `BraveVPNDisabled`, `TorDisabled` | Cut off funds, a paid subscription, or a privacy feature. Not schizo's call. |

## Apps

| Thing | Why not |
|---|---|
| NVIDIA `OptInOrOutPreference`, `FTS\EnableRID*`, `nvlddmkm\...\SendTelemetryData`, `NvTelemetryContainer`, `NvTmRep*` tasks | Not documented by NVIDIA. The documented control is a checkbox in NVIDIA Control Panel, which schizo points you to. `NvTelemetryContainer` is gone from current drivers. |
| AMD User Experience Program: uninstalling the MSI or disabling `AUEPLauncher` | AMD documents the in-app unsubscribe, which uninstalls it. schizo points you there instead of doing an undocumented equivalent. |
| Adobe Acrobat `FeatureLockDown\bUsageMeasurement` | Documented, but the product/version key path varies and Adobe only shows the WOW6432Node form. Needs testing against installed Acrobat versions first. |
| Office `sendtelemetry = 3` (Neither) | Valid, but schizo uses "required only" everywhere for consistency with how it treats Windows crash data. |
| Office `disconnectedstate` | Turns off co-authoring and OneDrive saving. Breaks Office for most people. |
| Office feedback/survey policies | Learn doesn't publish the registry value names; only the ADMX does. Not verified yet. |
| Visual Studio feedback policies | Value types not documented. |
| winget, Azure CLI config file, VS Code settings.json | Per-user JSON/INI files. schizo doesn't rewrite config files yet; VS Code and Azure CLI are covered through a policy and an environment variable instead. |
| Docker Desktop | The analytics key isn't documented, and the admin settings file forces sign-in. |
| Discord, Adobe desktop apps | Account-side settings only. schizo prints where they are when the app is installed. |
| Spotify | The only documented control is an account setting for ad personalization; there is nothing documented for usage data. |
| Slack, Dropbox, Steam, Epic, Razer, Corsair, Logitech G HUB | No documented telemetry control. |
| Firewall-blocking Notepad++, KeePass, Paint.NET, VLC, OBS | Either they need the network for updates (a security cost) or plugins in the same process do. 7-Zip has neither, so it is the one shipped. |
| Update-check settings in general | Not telemetry, and turning them off means missing security fixes. |
