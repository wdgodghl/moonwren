param(
  [string]$WrenRoot,
  [switch]$SkipOfficialSuite,
  [switch]$SkipBrowserE2E,
  [switch]$SkipCoverage
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Invoke-Gate {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [Parameter(Mandatory = $true)]
    [scriptblock]$Action
  )
  Write-Host "`n== $Name =="
  $global:LASTEXITCODE = 0
  & $Action
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
}

Push-Location $root
try {
  Invoke-Gate "Release metadata" { & "$PSScriptRoot/check-release-metadata.ps1" }
  Invoke-Gate "Documentation links" { & "$PSScriptRoot/check-doc-links.ps1" }
  Invoke-Gate "Repository hygiene" { & "$PSScriptRoot/check-repository-hygiene.ps1" }
  Invoke-Gate "Public API snapshot" { & "$PSScriptRoot/check-public-api.ps1" }
  Invoke-Gate "Formatting" { moon fmt --check }
  Invoke-Gate "Static checks" { moon check --target all --deny-warn }
  Invoke-Gate "Default build" { moon build }
  Invoke-Gate "Native build" { moon build --target native }
  Invoke-Gate "Browser build" { moon build --target js cmd/web_demo }
  Invoke-Gate "MoonBit tests" { moon test --target all --deny-warn }
  Invoke-Gate "Native CLI acceptance" { & "$PSScriptRoot/check-cli-acceptance.ps1" }
  Invoke-Gate "Browser and Node SDK" {
    & "$PSScriptRoot/build-web-demo.ps1"
    if ($LASTEXITCODE -eq 0) { node web/sdk.test.mjs }
  }
  if (-not $SkipBrowserE2E) {
    Invoke-Gate "Real browser acceptance" {
      if ($IsWindows -and (Test-Path "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")) {
        Write-Warning "Using installed Edge for local Chromium acceptance; CI gates Chromium, Firefox, and WebKit."
        & "$PSScriptRoot/check-browser-e2e.ps1" -Project chromium -ChromiumChannel msedge
      } else {
        & "$PSScriptRoot/check-browser-e2e.ps1"
      }
    }
  } else {
    Write-Warning "Real browser acceptance skipped for this local edit cycle."
  }
  if (-not $SkipCoverage) {
    Invoke-Gate "Coverage baseline" { & "$PSScriptRoot/check-coverage.ps1" }
  } else {
    Write-Warning "Coverage baseline skipped for this local edit cycle."
  }
  Invoke-Gate "Performance benchmark build" {
    moon build --target native --release cmd/benchmark
  }
  Invoke-Gate "Performance smoke" { & "$PSScriptRoot/check-performance.ps1" -SmokeOnly }
  Invoke-Gate "Checked-in Wren comparison" { & "$PSScriptRoot/check-conformance.ps1" }

  if ($WrenRoot) {
    Invoke-Gate "Official Wren 0.4.0 suite" {
      & "$PSScriptRoot/check-official-suite.ps1" -WrenRoot $WrenRoot `
        -ReportPath ".tmp/official-wren-report.json"
    }
  } elseif (-not $SkipOfficialSuite) {
    throw "Provide -WrenRoot <wren-0.4.0 checkout> or explicitly use -SkipOfficialSuite for an offline edit cycle."
  } else {
    Write-Warning "Official Wren suite skipped for this local edit cycle."
  }

  Write-Host "`nMoonWren quality gate passed."
} finally {
  Pop-Location
}

