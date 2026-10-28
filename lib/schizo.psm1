Set-StrictMode -Version 1.0
# module functions don't see the caller's preference. errors stop things here;
# the few places that expect a miss say SilentlyContinue.
$ErrorActionPreference = 'Stop'

# the windows modules schizo uses, loaded by full path. autoloading takes the
# first module of that name on PSModulePath, and the first entry is in the
# user's own Documents folder.
$system = [Environment]::GetFolderPath([Environment+SpecialFolder]::System)
foreach ($m in 'NetSecurity', 'Appx') {
    Import-Module (Join-Path $system "WindowsPowerShell\v1.0\Modules\$m\$m.psd1") -Global -ErrorAction Stop -WarningAction SilentlyContinue
}

. (Join-Path $PSScriptRoot 'rules.ps1')
. (Join-Path $PSScriptRoot 'targets.ps1')
. (Join-Path $PSScriptRoot 'machine.ps1')
. (Join-Path $PSScriptRoot 'extensions.ps1')
. (Join-Path $PSScriptRoot 'journal.ps1')
. (Join-Path $PSScriptRoot 'run.ps1')

Export-ModuleMember -Function *
