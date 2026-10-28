# Command-line tools that opt out through an environment variable. These are
# machine-wide variables, so every user's shells get them. Shells that are
# already open keep their old environment until restarted.
@{
    Apps  = @{
        'dotnet-sdk'     = @{
            Name      = '.NET SDK'
            Uninstall = '^Microsoft \.NET SDK\b'
        }
        powershell     = @{
            Name      = 'PowerShell 7'
            Uninstall = '^PowerShell 7\b'
            File      = '%ProgramFiles%\PowerShell\7\pwsh.exe'
            Appx      = 'Microsoft.PowerShell'
        }
        'azure-cli'      = @{
            Name      = 'Azure CLI'
            Uninstall = '^Microsoft Azure CLI\b'
        }
        'azure-func'     = @{
            Name      = 'Azure Functions Core Tools'
            Uninstall = '^Azure Functions Core Tools\b'
        }
        'github-cli'     = @{
            Name      = 'GitHub CLI'
            Uninstall = '^GitHub CLI$'
            File      = '%ProgramFiles%\GitHub CLI\gh.exe'
        }
    }
    Rules = @(
        @{
            Id       = 'dotnet.telemetry'
            App      = 'dotnet-sdk'
            Name     = 'sdk telemetry'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; Value = 'DOTNET_CLI_TELEMETRY_OPTOUT'; String = '1' }
            Why      = 'The dotnet CLI stops sending usage data on every command.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/dotnet/core/tools/telemetry'
            Tested   = '.net sdk 9.0.320, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'powershell.telemetry'
            App      = 'powershell'
            Name     = 'telemetry'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; Value = 'POWERSHELL_TELEMETRY_OPTOUT'; String = '1' }
            Why      = 'PowerShell 7 stops sending the telemetry it collects at startup and during the session. From 7.6.2 it also follows the Windows optional diagnostic data setting.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_telemetry'
            Tested   = 'powershell 7.6.9, win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'azure-cli.telemetry'
            App      = 'azure-cli'
            Name     = 'telemetry'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; Value = 'AZURE_CORE_COLLECT_TELEMETRY'; String = 'false' }
            Why      = 'az stops collecting usage data. Azure CLI reads AZURE_<section>_<name> variables for every config setting, and they override the config file.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/cli/azure/azure-cli-configuration'
            Tested   = 'azure cli, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'azure-func.telemetry'
            App      = 'azure-func'
            Name     = 'telemetry'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; Value = 'FUNCTIONS_CORE_TOOLS_TELEMETRY_OPTOUT'; String = '1' }
            Why      = 'func stops sending usage data.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://github.com/Azure/azure-functions-core-tools/blob/main/README.md'
            Tested   = 'functions core tools 4.16, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'github-cli.telemetry'
            App      = 'github-cli'
            Name     = 'telemetry'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'; Value = 'GH_TELEMETRY'; String = 'false' }
            Why      = 'gh stops sending usage telemetry. The variable takes precedence over DO_NOT_TRACK.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://cli.github.com/manual/gh_help_environment'
            Tested   = 'gh 2.103, win11 pro and home 26300 vms: applied and restored'
            Reviewed = '2026-10-27'
        }
    )
}
