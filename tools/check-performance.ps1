param(
  [string]$Executable,
  [string]$BaselinePath,
  [ValidateRange(1.0, 10.0)]
  [double]$MaximumRegression = 1.35,
  [switch]$WriteBaseline
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Executable) {
  $Executable = Join-Path $projectRoot "_build/native/release/build/cmd/benchmark/benchmark.exe"
}
if (-not $BaselinePath) {
  $BaselinePath = Join-Path $projectRoot ".tmp/performance-baseline.json"
}
if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
  throw "Benchmark executable not found: $Executable"
}

$values = @{}
& $Executable | ForEach-Object {
  if ($_ -match "^([^=]+)=(.+)$") {
    $values[$Matches[1]] = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
  }
}
if (-not $values.ContainsKey("ast_ms") -or -not $values.ContainsKey("bytecode_ms")) {
  throw "Benchmark output was incomplete."
}
$current = [ordered]@{ ast_ms = $values.ast_ms; bytecode_ms = $values.bytecode_ms }

if ($WriteBaseline -or -not (Test-Path -LiteralPath $BaselinePath)) {
  $directory = Split-Path -Parent $BaselinePath
  [void](New-Item -ItemType Directory -Path $directory -Force)
  $current | ConvertTo-Json | Set-Content -LiteralPath $BaselinePath -Encoding utf8
  Write-Host "Performance baseline written to $BaselinePath"
  return
}

$baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
foreach ($metric in @("ast_ms", "bytecode_ms")) {
  $ratio = $current[$metric] / [double]$baseline.$metric
  Write-Host ("{0}: {1:N3} ms ({2:P1} of baseline)" -f $metric, $current[$metric], $ratio)
  if ($ratio -gt $MaximumRegression) {
    throw "$metric exceeded the allowed regression ratio $MaximumRegression"
  }
}
