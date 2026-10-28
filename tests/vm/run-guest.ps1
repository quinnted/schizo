# guest side of Invoke-VmTest.ps1. unpacks the payload and runs the tests.
$ErrorActionPreference = 'Stop'
$root = 'C:\schizo-test'
$out = Join-Path $root 'out'
Remove-Item -LiteralPath (Join-Path $root 'payload'), $out -Recurse -Force -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath (Join-Path $root 'payload.zip') -DestinationPath (Join-Path $root 'payload')
$null = New-Item -ItemType Directory -Path $out

$env:SCHIZO_DISPOSABLE_VM = '1'
Import-Module (Get-ChildItem (Join-Path $root 'payload\Pester') -Filter Pester.psd1 -Recurse | Select-Object -First 1).FullName

$config = New-PesterConfiguration
$config.Run.Path = Join-Path $root 'payload\repo\tests\vm\guest.ps1'
$config.Run.PassThru = $true
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $out 'results.xml'
$config.Output.Verbosity = 'Detailed'
$null = Start-Transcript -Path (Join-Path $out 'pester.log')
try { $result = Invoke-Pester -Configuration $config }
finally { $null = Stop-Transcript }

$lines = @("passed $($result.PassedCount)", "failed $($result.FailedCount)", "skipped $($result.SkippedCount)")
foreach ($t in $result.Failed) { $lines += "FAIL $($t.ExpandedPath)"; $lines += "  $($t.ErrorRecord.Exception.Message)" }
$lines += "windows $([Environment]::OSVersion.Version) $((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID)"
$lines | Out-File (Join-Path $out 'summary.txt') -Encoding ascii
foreach ($name in 'schizo-run1.txt', 'schizo-restore1.txt') {
    $f = Join-Path $env:TEMP $name
    if (Test-Path $f) { Copy-Item $f (Join-Path $out $name) }
}
exit $result.FailedCount
