# Windows itself. Policy values are the ones the matching Group Policy writes.
#
# Microsoft documents almost every policy here for Pro, Enterprise and
# Education and says nothing either way about Home. They are applied on Home
# too; see README "Home edition".
@{
    Rules = @(
        @{
            Id       = 'windows.diagnostic-data'
            App      = 'windows'
            Name     = 'diagnostic data'
            State    = 'required only'
            Edition  = 'home', 'pro'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Value = 'AllowTelemetry'; Dword = 1 }
            Why      = 'Stops optional diagnostic data (browsing, app usage, crash dumps) and locks the Settings toggle. Home and Pro cannot go below Required; Microsoft treats 0 as 1 there.'
            Breaks   = 'The Windows Insider Program, which needs optional diagnostic data.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-system#allowtelemetry',
                       'https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization'
            Tested   = 'win11 pro and home 26300 vms: applied and restored; home settings shows it enforced'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.diagnostic-data-off'
            App      = 'windows'
            Name     = 'diagnostic data'
            State    = 'off'
            Edition  = 'education', 'enterprise'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Value = 'AllowTelemetry'; Dword = 0 }
            Why      = 'Enterprise and Education can turn diagnostic data off entirely.'
            Breaks   = 'Windows Update for Business reports and similar org tooling that relies on diagnostic data.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-system#allowtelemetry'
            Tested   = 'not tested on enterprise or education'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.feedback-prompts'
            App      = 'windows'
            Name     = 'feedback prompts'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection'; Value = 'DoNotShowFeedbackNotifications'; Dword = 1 }
            Why      = 'Windows stops asking for feedback through the Feedback Hub.'
            Breaks   = 'Nothing. Feedback Hub still works if you open it yourself.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#donotshowfeedbacknotifications'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.advertising-id'
            App      = 'windows'
            Name     = 'advertising id'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo'; Value = 'DisabledByGroupPolicy'; Dword = 1 }
            Why      = 'Apps cannot read a per-user advertising identifier for cross-app ad targeting.'
            Breaks   = 'Ads in apps get less personalized.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#disableadvertisingid'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.tailored-experiences'
            App      = 'windows'
            Name     = 'tailored experiences'
            State    = 'off'
            Set      = @{ Key = 'HKCU\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Value = 'DisableTailoredExperiencesWithDiagnosticData'; Dword = 1 }
            Why      = 'Windows stops using your diagnostic data to pick tips, offers and recommendations.'
            Breaks   = 'Nothing. You still get tips, just less targeted ones.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowtailoredexperienceswithdiagnosticdata'
            Tested   = 'win11 pro and home 26300 vms: applied and restored; home settings shows it locked off'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.activity-history'
            App      = 'windows'
            Name     = 'activity history'
            State    = 'off'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; Value = 'EnableActivityFeed'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; Value = 'PublishUserActivities'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; Value = 'UploadUserActivities'; Dword = 0 }
            )
            Why      = 'Apps and Windows stop recording your activities and uploading them to your Microsoft account.'
            Breaks   = 'Cross-device "pick up where you left off" based on activity history.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#enableactivityfeed',
                       'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#publishuseractivities',
                       'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#uploaduseractivities'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.third-party-suggestions'
            App      = 'windows'
            Name     = 'third-party suggestions'
            State    = 'off'
            Set      = @{ Key = 'HKCU\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Value = 'DisableThirdPartySuggestions'; Dword = 1 }
            Why      = 'Removes suggested third-party apps and content from Windows Spotlight and similar surfaces.'
            Breaks   = 'Nothing. Microsoft''s own suggestions are not covered by this policy.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowthirdpartysuggestionsinwindowsspotlight'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.consumer-features'
            App      = 'windows'
            Name     = 'consumer features and tips'
            State    = 'off'
            Edition  = 'education', 'enterprise'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Value = 'DisableWindowsConsumerFeatures'; Dword = 1 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Value = 'DisableConsumerAccountStateContent'; Dword = 1 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Value = 'DisableCloudOptimizedContent'; Dword = 1 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Value = 'DisableSoftLanding'; Dword = 1 }
            )
            Why      = 'Stops promoted app installs, account-state nags, cloud-sourced content and Windows tips. Microsoft only honors these on Enterprise and Education.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowsconsumerfeatures',
                       'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#disableconsumeraccountstatecontent',
                       'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#disablecloudoptimizedcontent',
                       'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowstips'
            Tested   = 'not tested on enterprise or education'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.spotlight'
            App      = 'windows'
            Name     = 'windows spotlight'
            State    = 'off'
            Edition  = 'education', 'enterprise'
            Set      = @{ Key = 'HKCU\SOFTWARE\Policies\Microsoft\Windows\CloudContent'; Value = 'DisableWindowsSpotlightFeatures'; Dword = 1 }
            Why      = 'Turns off Spotlight on the lock screen, in Settings, and in the welcome experience. Enterprise and Education only.'
            Breaks   = 'The rotating lock screen pictures.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-experience#allowwindowsspotlight'
            Tested   = 'not tested on enterprise or education'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.search-cloud'
            App      = 'windows'
            Name     = 'search: cloud content'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Value = 'AllowCloudSearch'; Dword = 0 }
            Why      = 'Windows Search stops querying OneDrive and SharePoint content.'
            Breaks   = 'Search results from your OneDrive or work account in the Start menu.'
            Level    = 'aggressive'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search#allowcloudsearch'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.search-location'
            App      = 'windows'
            Name     = 'search: location'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Value = 'AllowSearchToUseLocation'; Dword = 0 }
            Why      = 'Search stops sending your location with queries.'
            Breaks   = 'Location-aware search results.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search#allowsearchtouselocation'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.search-highlights'
            App      = 'windows'
            Name     = 'search highlights'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Value = 'EnableDynamicContentInWSB'; Dword = 0 }
            Why      = 'Removes the fetched "highlights" content from the search box and search home.'
            Breaks   = 'Trending searches and daily illustrations in search.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search#allowsearchhighlights'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.search-web'
            App      = 'windows'
            Name     = 'search: web results'
            State    = 'off'
            Edition  = 'education', 'enterprise'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search'; Value = 'ConnectedSearchUseWeb'; Dword = 0 }
            Why      = 'Search stops sending queries to Bing. Microsoft only honors this on Enterprise and Education; there is no documented equivalent for Home or Pro.'
            Breaks   = 'Web results in the Start menu.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-search#donotusewebresults'
            Tested   = 'not tested on enterprise or education'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.recall-snapshots'
            App      = 'windows'
            Name     = 'recall snapshots'
            State    = 'off'
            MinBuild = 26100
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'; Value = 'DisableAIDataAnalysis'; Dword = 1 }
            Why      = 'Recall stops saving screen snapshots, and deletes the ones it has. Only Copilot+ PCs have Recall; elsewhere this changes nothing.'
            Breaks   = 'Recall. Snapshots deleted by this are not brought back by restore.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai#disableaidataanalysis',
                       'https://learn.microsoft.com/en-us/windows/client-management/manage-recall'
            Tested   = 'win11 pro and home 26300 vms: applied and restored (no recall hardware)'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.error-reporting-extra'
            App      = 'windows'
            Name     = 'error reporting follow-ups'
            State    = 'declined'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting'; Value = 'DontSendAdditionalData'; Dword = 1 }
            Why      = 'Windows automatically declines Microsoft''s requests for more data (memory, files) after a crash report. Crash reporting itself stays on because Microsoft uses it to find security bugs.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-errorreporting#donotsendadditionaldata'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.ceip'
            App      = 'windows'
            Name     = 'customer experience program'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows'; Value = 'CEIPEnable'; Dword = 0 }
            Why      = 'Opts out of the Customer Experience Improvement Program. Mostly superseded by diagnostic data levels, but still read, and it also turns off application telemetry and the inventory collector.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-icm#ceipenable',
                       'https://learn.microsoft.com/en-us/windows/win32/devnotes/ceipenable'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.inking-typing'
            App      = 'windows'
            Name     = 'inking and typing data'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\TextInput'; Value = 'AllowLinguisticDataCollection'; Dword = 0 }
            Why      = 'Stops sending samples of what you type and write to Microsoft to "improve inking and typing".'
            Breaks   = 'Nothing. Local suggestions keep working.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-textinput#allowlinguisticdatacollection'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.delivery-optimization'
            App      = 'windows'
            Name     = 'update sharing with other pcs'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'; Value = 'DODownloadMode'; Dword = 0 }
            Why      = 'Windows downloads updates over HTTP only and stops exchanging update pieces with other PCs. Microsoft''s own FAQ says 0, not 99, is the value for this.'
            Breaks   = 'Update downloads can use a little more internet bandwidth on networks with several PCs.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deliveryoptimization#dodownloadmode',
                       'https://learn.microsoft.com/en-us/windows/deployment/do/waas-delivery-optimization-faq'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.language-list'
            App      = 'windows'
            Name     = 'language list for websites'
            State    = 'hidden'
            Set      = @{ Key = 'HKCU\Control Panel\International\User Profile'; Value = 'HttpAcceptLanguageOptOut'; Dword = 1 }
            Why      = 'Websites no longer get your full Windows language list for local content.'
            Breaks   = 'Sites may guess your language from the browser instead.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services#181-general'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.app-launch-tracking'
            App      = 'windows'
            Name     = 'app launch tracking'
            State    = 'off'
            Set      = @{ Key = 'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'; Value = 'Start_TrackProgs'; Dword = 0 }
            Why      = 'Windows stops tracking which apps you launch to rank Start and search results.'
            Breaks   = 'The "most used" list in Start stops filling in.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/privacy/manage-connections-from-windows-operating-system-components-to-microsoft-services#181-general'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.start-personalized-sites'
            App      = 'windows'
            Name     = 'start: recommended websites'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer'; Value = 'HideRecommendedPersonalizedSites'; Dword = 1 }
            Why      = 'Start stops recommending websites based on your browsing.'
            Breaks   = 'Nothing else in Start.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-start#hiderecommendedpersonalizedsites'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.account-notifications'
            App      = 'windows'
            Name     = 'start: account nags'
            State    = 'off'
            MinBuild = 26100
            Set      = @{ Key = 'HKCU\SOFTWARE\Policies\Microsoft\Windows\CurrentVersion\AccountNotifications'; Value = 'DisableAccountNotifications'; Dword = 1 }
            Why      = 'Removes the Start menu account prompts to back up the PC, buy storage, or subscribe to Microsoft 365 or Game Pass.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-notifications#disableaccountnotifications'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.online-tips'
            App      = 'windows'
            Name     = 'settings: online tips'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'; Value = 'AllowOnlineTips'; Dword = 0 }
            Why      = 'Settings stops fetching tips and help content from Microsoft.'
            Breaks   = 'The online help links inside Settings pages.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-settings#allowonlinetips'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.online-speech'
            App      = 'windows'
            Name     = 'online speech recognition'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\InputPersonalization'; Value = 'AllowInputPersonalization'; Dword = 0 }
            Why      = 'Voice input is no longer sent to Microsoft''s cloud speech service.'
            Breaks   = 'Voice typing and dictation that rely on online speech recognition.'
            Level    = 'aggressive'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#allowinputpersonalization'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.cloud-clipboard'
            App      = 'windows'
            Name     = 'clipboard sync across devices'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; Value = 'AllowCrossDeviceClipboard'; Dword = 0 }
            Why      = 'Clipboard contents are no longer uploaded to sync with your other devices. It is off by default; this keeps it off.'
            Breaks   = 'Clipboard sync, if you turned it on. Local clipboard history keeps working.'
            Level    = 'aggressive'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-privacy#allowcrossdeviceclipboard'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.phone-link'
            App      = 'windows'
            Name     = 'phone link'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System'; Value = 'EnableMmx'; Dword = 0 }
            Why      = 'This PC can no longer be linked to a phone through Phone Link. Takes effect after a restart.'
            Breaks   = 'Phone Link: texts, calls, photos and notifications from your phone.'
            Level    = 'aggressive'
            Source   = 'https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-connectivity#allowphonepclinking'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'windows.diagtrack-service'
            App      = 'windows'
            Name     = 'diagtrack service'
            State    = 'disabled'
            Set      = @{ Service = 'DiagTrack'; Start = 'Disabled' }
            Why      = 'Connected User Experiences and Telemetry is the service that uploads diagnostic data, required data included. Crash reporting and other components can still contact Microsoft.'
            Breaks   = 'Microsoft only suggests this for disconnected VDI images and recommends at least required data for Windows Update reliability. Windows Update itself keeps working.'
            Level    = 'aggressive'
            Source   = 'https://learn.microsoft.com/en-us/windows-server/remote/remote-desktop-services/remote-desktop-services-vdi-optimize-configuration',
                       'https://learn.microsoft.com/en-us/windows/privacy/configure-windows-diagnostic-data-in-your-organization'
            Tested   = 'win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
    )
}
