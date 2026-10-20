param(
  [Parameter(Mandatory = $true)]
  [string]$WrenExecutable
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$suite = Join-Path $root "conformance/wren-0.4.0"
$version = (& $WrenExecutable --version 2>&1 | Out-String).Trim()

if ($LASTEXITCODE -ne 0 -or $version -notmatch "0\.4\.0") {
  throw "Expected the official Wren 0.4.0 CLI, received: $version"
}

foreach ($case in Get-ChildItem -LiteralPath $suite -Filter "*.wren" | Sort-Object Name) {
  $expectedPath = [System.IO.Path]::ChangeExtension($case.FullName, ".out")
  $expected = (Get-Content -LiteralPath $expectedPath -Raw).TrimEnd("`r", "`n")
  $actualLines = & $WrenExecutable $case.FullName
  if ($LASTEXITCODE -ne 0) {
    throw "Official Wren failed while running $($case.Name)"
  }
  $actual = ($actualLines -join "`n").TrimEnd("`r", "`n")
  if ($actual -ne $expected) {
    throw "Reference mismatch in $($case.Name)`nEXPECTED:`n$expected`nACTUAL:`n$actual"
  }
  Write-Host "REFERENCE PASS $($case.Name)"
}
