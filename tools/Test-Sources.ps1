<#
.SYNOPSIS
Maintainer tool: fetches every Source URL in the rules and checks it still resolves.

.DESCRIPTION
This is the only script in the repository that touches the network, and
schizo.ps1 never calls it. It downloads each documentation page once and
checks that:
  - the page answers with HTTP 200
  - the #fragment, if any, appears in the page as an id or name
  - the policy or value name the rule sets is mentioned on the page

A page that mentions the value is not proof the value works. It catches
dead links, renamed anchors and copy-paste mistakes, which is what goes
stale first.

.EXAMPLE
.\tools\Test-Sources.ps1
#>
[CmdletBinding()]
param([string]$Rules)

$ErrorActionPreference = 'Stop'
# 5.1 leaves $PSScriptRoot empty inside param() defaults.
if (-not $Rules) { $Rules = Join-Path $PSScriptRoot '..\rules' }
Import-Module (Join-Path $PSScriptRoot '..\lib\schizo.psm1') -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$rulebase = Import-Rules $Rules
$pages = @{}
$bad = 0

foreach ($rule in $rulebase.Rules) {
    $names = @(@($rule.Set) | Where-Object { $_ -is [hashtable] } | ForEach-Object { $_.Value } | Where-Object { $_ })
    $mentioned = @{}
    foreach ($url in @($rule.Source)) {
        $page, $fragment = $url -split '#', 2
        # the chrome policy list is rendered by javascript; the same data is
        # published as json.
        $fetch = $page
        if ($page -match '^https://chromeenterprise\.google/policies/?$') { $fetch = 'https://chromeenterprise.google/static/json/policy_templates_en-US.json' }
        if (-not $pages.ContainsKey($page)) {
            try {
                $r = Invoke-WebRequest -Uri $fetch -UseBasicParsing -MaximumRedirection 5 -TimeoutSec 60
                $pages[$page] = @{ Ok = ($r.StatusCode -eq 200); Text = [string]$r.Content; Why = "http $($r.StatusCode)" }
            }
            catch {
                $pages[$page] = @{ Ok = $false; Text = ''; Why = $_.Exception.Message }
            }
        }
        $p = $pages[$page]
        if (-not $p.Ok -and $p.Why -match '\((403|429)\)') {
            # some vendors block scripted requests. that is not a dead link.
            Write-Host "$($rule.Id)  $url" ; Write-Host "  $($p.Why) - check it in a browser" -ForegroundColor Yellow
            continue
        }
        if (-not $p.Ok) {
            Write-Host "$($rule.Id)  $url" ; Write-Host "  $($p.Why)" -ForegroundColor Red
            $bad++
            continue
        }
        # chromeenterprise.google and mozilla.github.io build their pages in
        # javascript, so fragments there can't be checked from the html.
        if ($fragment -and $page -notmatch 'chromeenterprise\.google|mozilla\.github\.io' -and
            $p.Text -notmatch ('(id|name)\s*=\s*["'']' + [regex]::Escape($fragment) + '["'']')) {
            Write-Host "$($rule.Id)  $url" ; Write-Host '  anchor not found' -ForegroundColor Yellow
            $bad++
        }
        foreach ($n in $names) { if ($p.Text -match [regex]::Escape($n)) { $mentioned[$n] = $true } }
    }
    foreach ($n in $names) {
        if (-not $mentioned[$n]) {
            Write-Host "$($rule.Id)" ; Write-Host "  no source mentions $n" -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host "$($pages.Count) pages, $bad problems"
if ($bad) { exit 1 }
