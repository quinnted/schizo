# Firefox and Thunderbird read policies from the registry and from
# distribution\policies.json next to the exe. When both exist, the registry
# replaces whole top-level policies from the json file. So if someone already
# manages the browser with policies.json, schizo stays out of it (Unless).
#
# Firefox shows "Your browser is being managed by your organization" in
# Settings once any policy is active.
@{
    Apps  = @{
        firefox     = @{
            Name      = 'Mozilla Firefox'
            Uninstall = '^Mozilla Firefox\b'
            Publisher = '^Mozilla'
            File      = '%ProgramFiles%\Mozilla Firefox\firefox.exe'
        }
        thunderbird = @{
            Name      = 'Mozilla Thunderbird'
            Uninstall = '^Mozilla Thunderbird\b'
            Publisher = '^Mozilla'
            File      = '%ProgramFiles%\Mozilla Thunderbird\thunderbird.exe'
        }
    }
    Rules = @(
        @{
            Id       = 'firefox.telemetry'
            App      = 'firefox'
            Name     = 'telemetry'
            State    = 'off'
            Unless   = '{dir}\distribution\policies.json'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox'; Value = 'DisableTelemetry'; Dword = 1 }
            Why      = 'Stops telemetry upload and local telemetry storage, and hides the data collection settings.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://mozilla.github.io/policy-templates/#disabletelemetry'
            Tested   = 'firefox 159, win11 pro 26300 vm: accepted (about:policies, no errors), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'firefox.studies'
            App      = 'firefox'
            Name     = 'studies'
            State    = 'off'
            Unless   = '{dir}\distribution\policies.json'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox'; Value = 'DisableFirefoxStudies'; Dword = 1 }
            Why      = 'Firefox can no longer install and run Shield studies and experiments.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://mozilla.github.io/policy-templates/#disablefirefoxstudies'
            Tested   = 'firefox 159, win11 pro 26300 vm: accepted (about:policies, no errors), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'firefox.default-browser-agent'
            App      = 'firefox'
            Name     = 'default browser agent'
            State    = 'off'
            Unless   = '{dir}\distribution\policies.json'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox'; Value = 'DisableDefaultBrowserAgent'; Dword = 1 }
            Why      = 'Stops the scheduled task that reports your default browser settings to Mozilla.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://mozilla.github.io/policy-templates/#disabledefaultbrowseragent'
            Tested   = 'firefox 159, win11 pro 26300 vm: accepted (about:policies, no errors), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'firefox.sponsored-new-tab'
            App      = 'firefox'
            Name     = 'new tab: sponsored content'
            State    = 'off'
            Unless   = '{dir}\distribution\policies.json'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox\FirefoxHome'; Value = 'SponsoredTopSites'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox\FirefoxHome'; Value = 'SponsoredStories'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox\FirefoxHome'; Value = 'Locked'; Dword = 1 }
            )
            Why      = 'No sponsored shortcuts or sponsored stories on the new tab page. Locked, because otherwise a value you set earlier still wins.'
            Breaks   = 'Nothing. Your own shortcuts stay.'
            Level    = 'verified'
            Source   = 'https://mozilla.github.io/policy-templates/#firefoxhome'
            Tested   = 'firefox 159, win11 pro 26300 vm: accepted (about:policies, no errors), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'firefox.suggest'
            App      = 'firefox'
            Name     = 'sponsored and online suggestions'
            State    = 'off'
            Unless   = '{dir}\distribution\policies.json'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox\FirefoxSuggest'; Value = 'SponsoredSuggestions'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox\FirefoxSuggest'; Value = 'OnlineEnabled'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Firefox\FirefoxSuggest'; Value = 'Locked'; Dword = 1 }
            )
            Why      = 'No sponsored suggestions, and what you type is not sent to Mozilla''s suggestion service. Firefox Suggest only exists in some regions.'
            Breaks   = 'Online Firefox Suggest results.'
            Level    = 'verified'
            Source   = 'https://mozilla.github.io/policy-templates/#firefoxsuggest',
                       'https://github.com/mozilla-firefox/firefox/blob/release/browser/components/enterprisepolicies/schemas/policies-schema.json'
            Tested   = 'firefox 159, win11 pro 26300 vm: accepted (about:policies, no errors), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'thunderbird.telemetry'
            App      = 'thunderbird'
            Name     = 'telemetry'
            State    = 'off'
            Unless   = '{dir}\distribution\policies.json'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Mozilla\Thunderbird'; Value = 'DisableTelemetry'; Dword = 1 }
            Why      = 'Stops telemetry upload and local telemetry storage.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://github.com/thunderbird/policy-templates/blob/master/docs/policies/release/README.md'
            Tested   = 'thunderbird, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
    )
}
