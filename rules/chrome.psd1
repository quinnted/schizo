# Google Chrome machine policies. Chrome shows "Your browser is managed by
# your organization" once any policy is set.
#
# usage statistics and crash reports are an advice rule, not a policy:
# Chrome ignores MetricsReportingEnabled on a PC that isn't domain-joined or
# cloud-enrolled.
@{
    Apps  = @{
        chrome = @{
            Name      = 'Google Chrome'
            Uninstall = '^Google Chrome$'
            File      = '%ProgramFiles%\Google\Chrome\Application\chrome.exe', '%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe'
        }
    }
    Rules = @(
        @{
            Id       = 'chrome.usage-statistics'
            App      = 'chrome'
            Name     = 'usage statistics and crash reports'
            Advice   = 'chrome://settings/syncSetup > turn off "Help improve Chrome''s features and performance". The policy for this only works on managed PCs.'
            Why      = 'Chrome sends usage statistics and crash reports unless you opt out, and its policy (MetricsReportingEnabled) is ignored on PCs that are not domain-joined or enrolled.'
            Source   = 'https://chromeenterprise.google/policies/#MetricsReportingEnabled'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.url-collection'
            App      = 'chrome'
            Name     = 'visited urls to google'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'UrlKeyedAnonymizedDataCollectionEnabled'; Dword = 0 }
            Why      = 'Chrome stops sending the URLs of pages you visit to Google ("make searches and browsing better").'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://chromeenterprise.google/policies/#UrlKeyedAnonymizedDataCollectionEnabled'
            Tested   = 'chrome 156, win11 pro 26300 vm: accepted (chrome://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.domain-reliability'
            App      = 'chrome'
            Name     = 'domain reliability reports'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'DomainReliabilityAllowed'; Dword = 0 }
            Why      = 'Chrome stops uploading connection success and failure reports for Google properties. Otherwise this follows the metrics setting, which schizo cannot set on a home PC.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://chromeenterprise.google/policies/#DomainReliabilityAllowed'
            Tested   = 'chrome 156, win11 pro 26300 vm: accepted (chrome://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.cloud-spellcheck'
            App      = 'chrome'
            Name     = 'cloud spellcheck'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'SpellCheckServiceEnabled'; Dword = 0 }
            Why      = 'Text you type is no longer sent to Google''s spelling service. The local dictionary keeps working.'
            Breaks   = 'Enhanced spellcheck suggestions.'
            Level    = 'verified'
            Source   = 'https://chromeenterprise.google/policies/#SpellCheckServiceEnabled'
            Tested   = 'chrome 156, win11 pro 26300 vm: accepted (chrome://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.feedback'
            App      = 'chrome'
            Name     = 'feedback and surveys'
            State    = 'off'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'UserFeedbackAllowed'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'FeedbackSurveysEnabled'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'SafeBrowsingSurveysEnabled'; Dword = 0 }
            )
            Why      = 'No feedback reports (which can carry screenshots and system data) and no in-product surveys. Safe Browsing protection itself is untouched.'
            Breaks   = 'Sending feedback to Google from Chrome.'
            Level    = 'verified'
            Source   = 'https://chromeenterprise.google/policies/#UserFeedbackAllowed',
                       'https://chromeenterprise.google/policies/#FeedbackSurveysEnabled',
                       'https://chromeenterprise.google/policies/#SafeBrowsingSurveysEnabled'
            Tested   = 'chrome 156, win11 pro 26300 vm: accepted (chrome://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.promotions'
            App      = 'chrome'
            Name     = 'promotional content'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'PromotionsEnabled'; Dword = 0 }
            Why      = 'No promotional tabs and campaigns from Google.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://chromeenterprise.google/policies/#PromotionsEnabled'
            Tested   = 'chrome 156, win11 pro 26300 vm: accepted (chrome://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.error-pages'
            App      = 'chrome'
            Name     = 'error page web service'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'AlternateErrorPagesEnabled'; Dword = 0 }
            Why      = 'Failed navigations are no longer sent to Google for "similar page" suggestions.'
            Breaks   = 'Suggestions on error pages.'
            Level    = 'verified'
            Source   = 'https://chromeenterprise.google/policies/#AlternateErrorPagesEnabled'
            Tested   = 'chrome 156, win11 pro 26300 vm: accepted (chrome://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.payment-probing'
            App      = 'chrome'
            Name     = 'saved payment method probing'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'PaymentMethodQueryEnabled'; Dword = 0 }
            Why      = 'Websites can no longer ask whether you have payment methods saved, which is a fingerprinting signal.'
            Breaks   = 'Some express checkout buttons may not appear.'
            Level    = 'verified'
            Source   = 'https://chromeenterprise.google/policies/#PaymentMethodQueryEnabled'
            Tested   = 'chrome 156, win11 pro 26300 vm: accepted (chrome://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.preloading'
            App      = 'chrome'
            Name     = 'link preloading'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'NetworkPredictionOptions'; Dword = 2 }
            Why      = 'Chrome stops resolving and connecting to links you have not clicked, which tells those servers about pages you only looked at.'
            Breaks   = 'Page loads can be slightly slower.'
            Level    = 'verified'
            Source   = 'https://chromeenterprise.google/policies/#NetworkPredictionOptions'
            Tested   = 'chrome 156, win11 pro 26300 vm: accepted (chrome://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.background-mode'
            App      = 'chrome'
            Name     = 'running after close'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'BackgroundModeEnabled'; Dword = 0 }
            Why      = 'Chrome exits when its last window closes instead of staying resident for extensions and apps. Off is the default; this keeps it off.'
            Breaks   = 'Extensions that run while Chrome is closed.'
            Level    = 'verified'
            Source   = 'https://chromeenterprise.google/policies/#BackgroundModeEnabled'
            Tested   = 'chrome 156, win11 pro 26300 vm: accepted (chrome://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.search-suggestions'
            App      = 'chrome'
            Name     = 'address bar suggestions'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'SearchSuggestEnabled'; Dword = 0 }
            Why      = 'What you type in the address bar is no longer sent to the search engine before you press Enter.'
            Breaks   = 'Search suggestions while typing.'
            Level    = 'aggressive'
            Source   = 'https://chromeenterprise.google/policies/#SearchSuggestEnabled'
            Tested   = 'chrome 156, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'chrome.third-party-cookies'
            App      = 'chrome'
            Name     = 'third-party cookies'
            State    = 'blocked'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Google\Chrome'; Value = 'BlockThirdPartyCookies'; Dword = 1 }
            Why      = 'Sites embedded in other sites can no longer set or read cookies, which is how most cross-site tracking works.'
            Breaks   = 'Some sign-in flows, embedded comments and payment widgets.'
            Level    = 'aggressive'
            Source   = 'https://chromeenterprise.google/policies/#BlockThirdPartyCookies'
            Tested   = 'chrome 156, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
    )
}
