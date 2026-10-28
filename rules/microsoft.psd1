# Microsoft's desktop apps. Microsoft lists Microsoft 365 Personal among the
# products the Office privacy controls apply to, and documents setting them
# straight in the registry, without a domain.
@{
    Apps  = @{
        office        = @{
            Name = 'Microsoft 365 / Office'
            File = '%ProgramFiles%\Microsoft Office\root\Office16\WINWORD.EXE',
                   '%ProgramFiles(x86)%\Microsoft Office\root\Office16\WINWORD.EXE',
                   '%ProgramFiles%\Microsoft Office\root\Office16\EXCEL.EXE',
                   '%ProgramFiles(x86)%\Microsoft Office\root\Office16\EXCEL.EXE'
        }
        onedrive      = @{
            Name      = 'Microsoft OneDrive'
            Uninstall = '^Microsoft OneDrive$'
            File      = '%ProgramFiles%\Microsoft OneDrive\OneDrive.exe', '%LOCALAPPDATA%\Microsoft\OneDrive\OneDrive.exe'
            Appx      = 'Microsoft.OneDriveSync'
        }
        vscode        = @{
            Name      = 'Visual Studio Code'
            Uninstall = '^Microsoft Visual Studio Code( \(User\))?$'
            File      = '%ProgramFiles%\Microsoft VS Code\Code.exe', '%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe'
        }
        visualstudio  = @{
            Name      = 'Visual Studio'
            Uninstall = '^Visual Studio (Community|Professional|Enterprise|Build Tools) 20\d\d$'
        }
    }
    Rules = @(
        @{
            Id       = 'office.diagnostic-data'
            App      = 'office'
            Name     = 'diagnostic data'
            State    = 'required only'
            Set      = @{ Key = 'HKCU\Software\Policies\Microsoft\office\common\clienttelemetry'; Value = 'sendtelemetry'; Dword = 1 }
            Why      = 'Office stops sending optional diagnostic data. Without the policy it sends optional and required. Same level schizo picks for Windows and Edge.'
            Breaks   = 'Nothing known.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/microsoft-365-apps/privacy/manage-privacy-controls',
                       'https://learn.microsoft.com/en-us/microsoft-365-apps/privacy/products-versions-privacy-controls'
            Tested   = 'not run: office was not installed in the test vm'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'office.optional-connected-experiences'
            App      = 'office'
            Name     = 'optional connected experiences'
            State    = 'off'
            Set      = @{ Key = 'HKCU\Software\Policies\Microsoft\office\16.0\common\privacy'; Value = 'controllerconnectedservicesenabled'; Dword = 2 }
            Why      = 'Turns off the optional connected experiences: cloud features such as 3D maps and online pictures, which send data to Microsoft and partners.'
            Breaks   = 'Those features.'
            Level    = 'aggressive'
            Source   = 'https://learn.microsoft.com/en-us/microsoft-365-apps/privacy/manage-privacy-controls'
            Tested   = 'not run: office was not installed in the test vm'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'office.content-analysis'
            App      = 'office'
            Name     = 'cloud analysis of your documents'
            State    = 'off'
            Set      = @{ Key = 'HKCU\Software\Policies\Microsoft\office\16.0\common\privacy'; Value = 'usercontentdisabled'; Dword = 2 }
            Why      = 'Office stops sending document content to Microsoft for features that analyze it.'
            Breaks   = 'Designer, Translator, Editor''s cloud checks, dictation and similar features.'
            Level    = 'aggressive'
            Source   = 'https://learn.microsoft.com/en-us/microsoft-365-apps/privacy/manage-privacy-controls'
            Tested   = 'not run: office was not installed in the test vm'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'onedrive.feedback'
            App      = 'onedrive'
            Name     = 'feedback and surveys'
            State    = 'off'
            Set      = @(
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\OneDrive'; Value = 'EnableSendFeedback'; Dword = 0 }
                @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\OneDrive'; Value = 'EnableSurveyCampaigns'; Dword = 0 }
            )
            Why      = 'No in-app feedback submissions and no survey prompts. Contacting support stays available.'
            Breaks   = 'Sending feedback from the OneDrive app.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/sharepoint/use-group-policy'
            Tested   = 'win11 pro 26300 vm (inbox onedrive): applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'vscode.telemetry'
            App      = 'vscode'
            Name     = 'telemetry and crash reports'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\VSCode'; Value = 'TelemetryLevel'; String = 'off' }
            Why      = 'VS Code (1.99 and later) sends no usage data, error telemetry or crash reports, and the setting cannot be turned back on from inside the editor. Extensions that respect the setting stop too.'
            Breaks   = 'Nothing. Extensions with their own telemetry switch are not covered.'
            Level    = 'verified'
            Source   = 'https://code.visualstudio.com/docs/enterprise/policies',
                       'https://code.visualstudio.com/docs/configure/telemetry'
            Tested   = 'vs code 1.143, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'vscode.feedback'
            App      = 'vscode'
            Name     = 'feedback and surveys'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\VSCode'; Value = 'EnableFeedback'; Dword = 0 }
            Why      = 'Removes the feedback prompts and surveys.'
            Breaks   = 'The issue reporter and survey prompts.'
            Level    = 'verified'
            Source   = 'https://code.visualstudio.com/docs/enterprise/policies'
            Tested   = 'vs code 1.143, win11 pro 26300 vm: applied and restored'
            Reviewed = '2026-10-27'
        }
        @{
            Id       = 'visualstudio.ceip'
            App      = 'visualstudio'
            Name     = 'customer experience program'
            State    = 'off'
            Set      = @{ Key = 'HKLM\SOFTWARE\Policies\Microsoft\VisualStudio\SQM'; Value = 'OptIn'; Dword = 0 }
            Why      = 'Opts every installed Visual Studio version, including Build Tools which have no settings UI, out of the Customer Experience Improvement Program.'
            Breaks   = 'Nothing. Report a Problem still works.'
            Level    = 'verified'
            Source   = 'https://learn.microsoft.com/en-us/visualstudio/ide/visual-studio-experience-improvement-program'
            Tested   = 'not run: visual studio was not installed in the test vm'
            Reviewed = '2026-10-27'
        }
    )
}
