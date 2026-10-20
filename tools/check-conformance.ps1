$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$suite = Join-Path $root "conformance/wren-0.4.0"
$cases = Get-ChildItem -LiteralPath $suite -Filter "*.wren" | Sort-Object Name

foreach ($case in $cases) {
  $expectedPath = [System.IO.Path]::ChangeExtension($case.FullName, ".out")
  $expected = (Get-Content -LiteralPath $expectedPath -Raw).TrimEnd("`r", "`n")
  $actualLines = & moon run cmd/main -- $case.FullName
  if ($LASTEXITCODE -ne 0) {
    throw "MoonWren failed while running $($case.Name)"
  }
  $actual = ($actualLines -join "`n").TrimEnd("`r", "`n")
  if ($actual -ne $expected) {
    throw "Conformance mismatch in $($case.Name)`nEXPECTED:`n$expected`nACTUAL:`n$actual"
  }
  Write-Host "PASS $($case.Name)"
}
