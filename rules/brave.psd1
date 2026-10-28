# Brave machine policies: Brave's own, from brave-core's policy definitions.
# Brave shows "managed by your organization" once any policy is set.
@{
    Apps  = @{
        brave = @{
            Name      = 'Brave'
            Uninstall = '^Brave$'
            File      = '%ProgramFiles%\BraveSoftware\Brave-Browser\Application\brave.exe', '%LOCALAPPDATA%\BraveSoftware\Brave-Browser\Application\brave.exe'
        }
    }
    Rules = @(
        @{
            Id       = 'brave.usage-ping'
            App      = 'brave'
            Name     = 'usage ping and p3a'
            State    = 'off'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\BraveSoftware\Brave'; Value = 'BraveStatsPingEnabled'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\BraveSoftware\Brave'; Value = 'BraveP3AEnabled'; Dword = 0 }
            )
            Why      = 'Turns off the daily usage ping and Privacy-Preserving Product Analytics. Both are on by default.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://github.com/brave/brave-core/blob/master/components/policy/resources/templates/policy_definitions/BraveSoftware/BraveStatsPingEnabled.yaml',
                       'https://github.com/brave/brave-core/blob/master/components/policy/resources/templates/policy_definitions/BraveSoftware/BraveP3AEnabled.yaml'
            Tested   = 'brave, win11 pro 26300 vm: accepted (brave://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'brave.web-discovery'
            App      = 'brave'
            Name     = 'web discovery project'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\BraveSoftware\Brave'; Value = 'BraveWebDiscoveryEnabled'; Dword = 0 }
            Why      = 'Keeps the Web Discovery Project, which contributes browsing data to Brave Search, switched off. Off is the default.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://github.com/brave/brave-core/blob/master/components/policy/resources/templates/policy_definitions/BraveSoftware/BraveWebDiscoveryEnabled.yaml'
            Tested   = 'brave, win11 pro 26300 vm: accepted (brave://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'brave.rewards'
            App      = 'brave'
            Name     = 'rewards (ads)'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\BraveSoftware\Brave'; Value = 'BraveRewardsDisabled'; Dword = 1 }
            Why      = 'Disables Brave Rewards, Brave''s opt-in ad system.'
            Breaks   = 'Brave Rewards and anything you earn through it.'
            Level    = 'aggressive'
            Source   = 'https://github.com/brave/brave-core/blob/master/components/policy/resources/templates/policy_definitions/BraveSoftware/BraveRewardsDisabled.yaml'
            Tested   = 'brave, win11 pro 26300 vm: accepted (brave://policy shows OK), restored'
            Reviewed = '2026-10-27'
        }
    )
}
