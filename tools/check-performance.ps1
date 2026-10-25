param(
  [string]$Executable,
  [string]$BaselinePath,
  [ValidateRange(1.0, 10.0)]
  [double]$MaximumRegression = 1.35,
  [switch]$WriteBaseline,
  [switch]$SmokeOnly,
  [ValidateRange(1.0, 20.0)]
  [double]$MaximumBytecodeRatio = 10.0
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $Executable) {
  $Executable = Join-Path $projectRoot "_build/native/release/build/cmd/benchmark/benchmark.exe"
  if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
    $Executable = Join-Path $projectRoot "_build/native/release/build/cmd/benchmark/benchmark"
  }
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
foreach ($metric in @("parse_ms", "ast_ms", "bytecode_ms", "collections_ast_ms", "collections_bytecode_ms", "fiber_ms")) {
  if (-not $values.ContainsKey($metric) -or $values[$metric] -le 0 -or [double]::IsNaN($values[$metric]) -or [double]::IsInfinity($values[$metric])) {
    throw "Benchmark metric '$metric' was missing or invalid."
  }
}
if ($values.bytecode_ms / $values.ast_ms -gt $MaximumBytecodeRatio) {
  throw "Bytecode procedural runtime exceeded the allowed AST ratio $MaximumBytecodeRatio"
}
if ($values.collections_bytecode_ms / $values.collections_ast_ms -gt $MaximumBytecodeRatio) {
  throw "Bytecode collection runtime exceeded the allowed AST ratio $MaximumBytecodeRatio"
}
if ($SmokeOnly) {
  Write-Host "Performance smoke gate passed with six valid metrics."
  return
}
$current = [ordered]@{}
foreach ($metric in ($values.Keys | Sort-Object)) { $current[$metric] = $values[$metric] }

if ($WriteBaseline -or -not (Test-Path -LiteralPath $BaselinePath)) {
  $directory = Split-Path -Parent $BaselinePath
  [void](New-Item -ItemType Directory -Path $directory -Force)
  $current | ConvertTo-Json | Set-Content -LiteralPath $BaselinePath -Encoding utf8
  Write-Host "Performance baseline written to $BaselinePath"
  return
}

$baseline = Get-Content -LiteralPath $BaselinePath -Raw | ConvertFrom-Json
foreach ($metric in $current.Keys) {
  if (-not $baseline.PSObject.Properties.Name.Contains($metric)) {
    throw "Performance baseline is missing metric '$metric'. Recreate it with -WriteBaseline."
  }
  $ratio = $current[$metric] / [double]$baseline.$metric
  Write-Host ("{0}: {1:N3} ms ({2:P1} of baseline)" -f $metric, $current[$metric], $ratio)
  if ($ratio -gt $MaximumRegression) {
    throw "$metric exceeded the allowed regression ratio $MaximumRegression"
  }
}
