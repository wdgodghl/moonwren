param(
  [string]$ApplicationRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) "moonwren-json-pipeline")
)

$ErrorActionPreference = "Stop"
$applicationRoot = [IO.Path]::GetFullPath($ApplicationRoot)
$modulePath = Join-Path $applicationRoot "moon.mod"
$checkPath = Join-Path $applicationRoot "tools/check.ps1"
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
  throw "Independent application moon.mod not found: $modulePath"
}
if (-not (Test-Path -LiteralPath $checkPath -PathType Leaf)) {
  throw "Independent application gate not found: $checkPath"
}
$module = [IO.File]::ReadAllText($modulePath)
if ($module -notmatch '"wdgodghl/moonwren@0\.9\.3"') {
  throw "Independent application does not pin the published MoonWren 0.9.3 package."
}
if ($module -match '(?im)^\s*(path|source)\s*=') {
  throw "Independent application contains a local source/path dependency."
}
& $checkPath
if ($LASTEXITCODE -ne 0) { throw "Independent application acceptance failed." }
Write-Host "Independent application boundary passed: registry-only MoonWren dependency."
