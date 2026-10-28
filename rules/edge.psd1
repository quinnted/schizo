# Microsoft Edge machine policies. Any policy makes Edge show "Managed by your
# organization" in its menu and at edge://management. That is expected.
#
# Edge skips some policies for profiles signed in with a personal Microsoft
# account. Microsoft documents that for managed devices and says nothing about
# home PCs. Check edge://policy if it matters to you.
@{
    Apps  = @{
        edge = @{
            Name      = 'Microsoft Edge'
            Uninstall = '^Microsoft Edge$'
            File      = '%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe', '%ProgramFiles%\Microsoft\Edge\Application\msedge.exe'
        }
    }
    Rules = @(
        @{
            Id       = 'edge.diagnostic-data'
            App      = 'edge'
            Name     = 'diagnostic data'
            State    = 'required only'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'DiagnosticData'; Dword = 1 }
            Why      = 'Edge stops sending optional diagnostic data: browsing and usage data and crash details. Edge collects this separately from Windows.'
            Breaks   = 'Nothing known. (0 would also cut required data, which Microsoft recommends against.)'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/diagnosticdata'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.personalization-reporting'
            App      = 'edge'
            Name     = 'browsing data for ads and news'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'PersonalizationReportingEnabled'; Dword = 0 }
            Why      = 'Edge stops sending browsing history, favorites and usage to Microsoft to personalize ads, news and search.'
            Breaks   = 'Less personalized MSN and Bing content.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/personalizationreportingenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.search-telemetry'
            App      = 'edge'
            Name     = 'third-party search telemetry'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'Edge3PSerpTelemetryEnabled'; Dword = 0 }
            Why      = 'Edge stops recording searches you make on search engines other than Bing.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/edge3pserptelemetryenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.experiments'
            App      = 'edge'
            Name     = 'experiments'
            State    = 'configuration only'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'ExperimentationAndConfigurationServiceControl'; Dword = 1 }
            Why      = 'Edge still downloads compatibility configuration but is no longer enrolled in experiments. This is the default for managed Edge.'
            Breaks   = 'Nothing known. (0 would also drop site compatibility fixes, which Microsoft recommends against.)'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/experimentationandconfigurationservicecontrol'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.feedback'
            App      = 'edge'
            Name     = 'feedback'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'UserFeedbackAllowed'; Dword = 0 }
            Why      = 'Removes the Send feedback tool, which can attach screenshots, URLs and diagnostics.'
            Breaks   = 'Sending feedback to Microsoft from Edge.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/userfeedbackallowed'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.spotlight'
            App      = 'edge'
            Name     = 'recommendations and tips'
            State    = 'off'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'SpotlightExperiencesAndRecommendationsEnabled'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'ShowRecommendationsEnabled'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'DefaultBrowserSettingsCampaignEnabled'; Dword = 0 }
            )
            Why      = 'No promotional tips, feature recommendations, or prompts to make Edge and Bing your defaults.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/spotlightexperiencesandrecommendationsenabled',
                       'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/showrecommendationsenabled',
                       'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/defaultbrowsersettingscampaignenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.shopping'
            App      = 'edge'
            Name     = 'shopping assistant'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'EdgeShoppingAssistantEnabled'; Dword = 0 }
            Why      = 'Edge stops checking the pages you shop on against Microsoft''s price and coupon service.'
            Breaks   = 'Price comparison, coupons and cashback offers in Edge.'
            Level    = 'aggressive'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/edgeshoppingassistantenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.new-tab-content'
            App      = 'edge'
            Name     = 'new tab news and sponsored tiles'
            State    = 'off'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'NewTabPageContentEnabled'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'NewTabPageHideDefaultTopSites'; Dword = 1 }
            )
            Why      = 'The new tab page stops loading the MSN news feed and Microsoft-provided site tiles.'
            Breaks   = 'The news feed on the new tab page. Your own top sites stay.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/newtabpagecontentenabled',
                       'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/newtabpagehidedefaulttopsites'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.error-page-services'
            App      = 'edge'
            Name     = 'error page web services'
            State    = 'off'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'AlternateErrorPagesEnabled'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'ResolveNavigationErrorsUseWebService'; Dword = 0 }
            )
            Why      = 'Failed navigations are no longer sent to a Microsoft web service for suggestions or diagnosis.'
            Breaks   = 'Suggested similar pages on error pages. Captive portal detection falls back to Windows.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/alternateerrorpagesenabled',
                       'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/resolvenavigationerrorsusewebservice'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.cloud-spellcheck'
            App      = 'edge'
            Name     = 'cloud spellcheck'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'MicrosoftEditorProofingEnabled'; Dword = 0 }
            Why      = 'Text you type is no longer sent to the Microsoft Editor service. Spellcheck keeps working with the local Windows engine.'
            Breaks   = 'Grammar suggestions; spelling suggestions get simpler.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/microsofteditorproofingenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.payment-probing'
            App      = 'edge'
            Name     = 'saved payment method probing'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'PaymentMethodQueryEnabled'; Dword = 0 }
            Why      = 'Websites can no longer ask whether you have payment methods saved, which is a fingerprinting signal.'
            Breaks   = 'Some express checkout buttons may not appear.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/paymentmethodqueryenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.ads-transparency'
            App      = 'edge'
            Name     = 'ad provider tracking exceptions'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'AdsTransparencyEnabled'; Dword = 0 }
            Why      = 'Balanced tracking prevention no longer relaxes itself for ad providers that meet Microsoft''s transparency program.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/adstransparencyenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.sign-in-prompts'
            App      = 'edge'
            Name     = 'automatic account sign-in'
            State    = 'off'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'ImplicitSignInEnabled'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'WebToBrowserSignInEnabled'; Dword = 0 }
            )
            Why      = 'New Edge profiles are not signed in to your Windows Microsoft account automatically, and signing in to a Microsoft website no longer offers to sign in the browser.'
            Breaks   = 'Sync starts only when you sign in to Edge yourself. Profiles that are already signed in stay signed in.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/implicitsigninenabled',
                       'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/webtobrowsersigninenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.startup-boost'
            App      = 'edge'
            Name     = 'startup boost'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'StartupBoostEnabled'; Dword = 0 }
            Why      = 'Edge no longer starts in the background when you sign in to Windows, whether or not you use it.'
            Breaks   = 'The first Edge window opens a little slower.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/startupboostenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: accepted (edge://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'edge.search-suggestions'
            App      = 'edge'
            Name     = 'address bar suggestions'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'; Value = 'SearchSuggestEnabled'; Dword = 0 }
            Why      = 'What you type in the address bar is no longer sent to the search engine before you press Enter.'
            Breaks   = 'Search suggestions while typing.'
            Level    = 'aggressive'
            Source   = 'https://learn.microsoft.com/en-us/deployedge/microsoft-edge-browser-policies/searchsuggestenabled'
            Tested   = 'edge 156, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
    )
}
