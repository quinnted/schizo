# checks on the code itself: it parses, stays ascii, and doesn't reach for the
# network or run strings as code.

BeforeDiscovery {
    $root = Join-Path $PSScriptRoot '..'
    $script:SourceFiles = @(Get-ChildItem $root -Recurse -Include *.ps1, *.psm1, *.psd1 |
            Where-Object { $_.FullName -notmatch '\\\.git\\' } |
            ForEach-Object { @{ Path = $_.FullName; Name = $_.FullName.Substring((Resolve-Path $root).Path.Length + 1) } })
    # tools\ is for maintainers (Test-Sources.ps1 fetches the rule sources on purpose).
    $script:ShippedFiles = @($SourceFiles | Where-Object { $_.Name -notmatch '^(tests|tools)\\' })
}

BeforeAll {
    $root = Join-Path $PSScriptRoot '..'
    # whichever powershell is running the tests: 5.1 or 7.
    $shell = (Get-Process -Id $PID).Path
}

Describe '<Name>' -ForEach $SourceFiles {
    It 'parses' {
        $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$errors)
        $errors | Should -BeNullOrEmpty
    }

    It 'is plain ascii' {
        $bytes = [IO.File]::ReadAllBytes($Path)
        @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}

Describe 'shipped code: <Name>' -ForEach $ShippedFiles {
    It 'never runs strings as code or touches the network' {
        $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $commands = $ast.FindAll({ $args[0] -is [Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
        $banned = 'Invoke-Expression', 'iex', 'Invoke-WebRequest', 'iwr', 'Invoke-RestMethod', 'irm', 'curl', 'wget',
            'Start-BitsTransfer', 'Add-Type', 'New-PSSession', 'Invoke-Command', 'Enter-PSSession'
        @($commands | Where-Object { $_ -in $banned }) | Should -BeNullOrEmpty

        $text = [IO.File]::ReadAllText($Path)
        $text | Should -Not -Match 'Net\.WebClient|HttpClient|DownloadString|DownloadFile|FromBase64String\(\s*[''"]|EncodedCommand|ScriptBlock\]::Create'
    }
}

Describe 'maintainer tools' {
    It 'are never called by schizo or restore' {
        foreach ($f in @('schizo.ps1', 'restore.ps1') + @(Get-ChildItem (Join-Path $root 'lib') | ForEach-Object { "lib\$($_.Name)" })) {
            [IO.File]::ReadAllText((Join-Path $root $f)) | Should -Not -Match 'tools\\|Test-Sources' -Because $f
        }
    }
}

Describe 'entry points' {
    It 'schizo.ps1 refuses to change anything without admin' {
        if ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
            Set-ItResult -Skipped -Because 'this shell is elevated'
            return
        }
        $out = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'schizo.ps1') 2>&1
        $LASTEXITCODE | Should -Be 2
        $out | Should -Be 'run this from an Administrator PowerShell.'
    }

    It 'restore.ps1 refuses without admin' {
        if ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole('Administrators')) {
            Set-ItResult -Skipped -Because 'this shell is elevated'
            return
        }
        $out = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'restore.ps1') 2>&1
        $LASTEXITCODE | Should -Be 2
        $out | Should -Be 'run this from an Administrator PowerShell.'
    }

    It 'schizo.ps1 -Audit runs anywhere and changes nothing' {
        $out = & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'schizo.ps1') -Audit 2>&1
        $LASTEXITCODE | Should -Be 0
        ($out -join "`n") | Should -Match '\d+ would change'
        ($out -join "`n") | Should -Not -Match 'backup:'
    }
}
