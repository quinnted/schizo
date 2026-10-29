# Third-party desktop software. Most vendors document no local telemetry
# switch at all; where the only documented control is a checkbox in the app
# or a setting on the vendor's website, schizo says so instead of poking at
# undocumented registry values.
@{
    Apps  = @{
        '7zip'           = @{
            Name      = '7-Zip'
            Uninstall = '^7-Zip\b'
            Publisher = '^Igor Pavlov$'
            File      = '%ProgramFiles%\7-Zip\7zFM.exe'
        }
        zoom           = @{
            Name      = 'Zoom Workplace'
            Uninstall = '^Zoom( Workplace)?\b'
            Publisher = '^Zoom (Video )?Communications'
            File      = '%ProgramFiles%\Zoom\bin\Zoom.exe', '%APPDATA%\Zoom\bin\Zoom.exe'
        }
        'amd-uep'        = @{
            Name    = 'AMD Software'
            Service = 'AUEPLauncher'
        }
        'nvidia-cpl'     = @{
            Name = 'NVIDIA Control Panel'
            Appx = 'NVIDIACorp.NVIDIAControlPanel'
            File = '%ProgramFiles%\NVIDIA Corporation\Control Panel Client\nvcplui.exe'
        }
        adobe          = @{
            Name      = 'Adobe'
            Uninstall = '^Adobe\b'
            Publisher = '^Adobe\b'
        }
        discord        = @{
            Name      = 'Discord'
            Uninstall = '^Discord$'
            Publisher = '^Discord'
        }
    }
    Rules = @(
        @{
            Id       = '7zip.network'
            App      = '7zip'
            Name     = 'outbound network'
            State    = 'blocked'
            Set      = @(
                @{ BlockOutbound = '{dir}\7zFM.exe' }
                @{ BlockOutbound = '{dir}\7zG.exe' }
                @{ BlockOutbound = '{dir}\7z.exe' }
            )
            Why      = '7-Zip has no updater, no telemetry and no HTTP or socket code. Its only network calls ask Windows to browse and connect file shares, which the system does itself. Nothing in it should connect anywhere, so if a malicious archive ever got code running inside 7-Zip, it could not call out either.'
            Breaks   = 'Nothing known. Archives on network shares are read through Windows, not by 7-Zip itself.'
            Level    = 'verified'
            Source   = 'https://github.com/ip7z/7zip/blob/main/CPP/Windows/Net.cpp',
                       'https://github.com/ip7z/7zip/blob/main/CPP/7zip/UI/FileManager/AboutDialog.cpp'
            Tested   = '7-zip 26.05, win11 pro and home 26300 vms: rules created and removed'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'zoom.crash-uploads'
            App      = 'zoom'
            Name     = 'automatic crash and log uploads'
            State    = 'off'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Zoom\Zoom Meetings\General'; Value = 'EnableAutoUploadDumps'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Zoom\Zoom Meetings\General'; Value = 'EnableAutoUploadMemlogs'; Dword = 0 }
            )
            Why      = 'Crash dumps and failure logs are not uploaded to Zoom automatically. Off is Zoom''s default; the policy keeps it off. Zoom documents no policy for general usage analytics.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://support.zoom.com/hc/en/article?id=zm_kb&sysparm_article=KB0065466'
            Tested   = 'zoom workplace, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'amd.user-experience-program'
            App      = 'amd-uep'
            Name     = 'user experience program'
            Advice   = 'AMD Software > Settings (gear) > Preferences > AMD User Experience Program > Unsubscribe. AMD says this uninstalls the uploader and leaves drivers alone. A driver reinstall asks again.'
            Why      = 'The AMD User Experience Program uploader service is installed. AMD documents only the in-app opt-out, not a setting schizo could change safely.'
            Source   = 'https://www.amd.com/en/legal/privacy/user-experience-program.html'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'nvidia.error-data'
            App      = 'nvidia-cpl'
            Name     = 'technical and error data'
            Advice   = 'NVIDIA Control Panel > Help > untick "Send technical and error data to NVIDIA". The registry values other tools set for this are not documented by NVIDIA.'
            Why      = 'NVIDIA documents this checkbox as the opt-out for driver technical and error data.'
            Source   = 'https://www.nvidia.com/en-gb/privacy-center/'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'adobe.desktop-app-usage'
            App      = 'adobe'
            Name     = 'desktop app usage'
            Advice   = 'account.adobe.com > Data and privacy > turn off "Desktop app usage". One account setting covers every Adobe desktop app; work and school accounts don''t have it.'
            Why      = 'Adobe collects usage of all its desktop apps per account, and documents no local switch. Adobe says it doesn''t collect it for business and education accounts.'
            Source   = 'https://www.adobe.com/privacy/app-usage-info-faq.html'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'discord.data-use'
            App      = 'discord'
            Name     = 'usage data'
            Advice   = 'Discord > User Settings > Data & Privacy > turn off "Use data to improve Discord". Discord says the app still sends the same signals; the switch only stops Discord using them for this. No local setting is known that stops the signals and leaves Discord working.'
            Why      = 'This is the only documented control, and it is an account setting, not a local one.'
            Source   = 'https://support.discord.com/hc/articles/21864805694999'
            Reviewed = '2026-10-27'
        }
    )
}
