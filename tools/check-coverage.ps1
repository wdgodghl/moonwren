param(
  [double]$MinimumPercent = 70.0,
  [double]$MinimumCorePercent = 74.0
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$report = Join-Path $projectRoot ".tmp/coverage-summary.txt"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $report) | Out-Null

Push-Location $projectRoot
try {
  moon coverage clean
  if ($LASTEXITCODE -ne 0) { throw "moon coverage clean failed." }
  $summary = (& moon coverage analyze -- -f summary 2>&1 | Out-String).Replace("`r`n", "`n")
  if ($LASTEXITCODE -ne 0) { throw "moon coverage analyze failed:`n$summary" }
  [IO.File]::WriteAllText($report, $summary, [Text.UTF8Encoding]::new($false))
  $match = [regex]::Match($summary, '(?m)^Total:\s+(\d+)/(\d+)\s*$')
  if (-not $match.Success) { throw "Coverage output did not contain a Total line.`n$summary" }
  $covered = [double]$match.Groups[1].Value
  $total = [double]$match.Groups[2].Value
  $percent = if ($total -eq 0) { 0.0 } else { 100.0 * $covered / $total }
  Write-Host $summary.TrimEnd()
  if ($percent -lt $MinimumPercent) {
    throw ("Coverage {0:N2}% is below the supported-path baseline {1:N2}%." -f $percent, $MinimumPercent)
  }
  Write-Host ("Coverage gate passed: {0}/{1} ({2:N2}%), minimum {3:N2}%." -f $covered, $total, $percent, $MinimumPercent)

  $coreFiles = @(
    "lexer.mbt", "parser.mbt", "resolver.mbt", "evaluator.mbt",
    "interpreter.mbt", "foreign.mbt", "async_task.mbt",
    "hot_reload.mbt", "embedding_api.mbt"
  )
  $coreCovered = 0.0
  $coreTotal = 0.0
  foreach ($file in $coreFiles) {
    $line = [regex]::Match($summary, "(?m)^$([regex]::Escape($file)):\s+(?<covered>\d+)/(?<total>\d+)\s*$")
    if (-not $line.Success) { throw "Coverage output is missing core file $file." }
    $coreCovered += [double]$line.Groups["covered"].Value
    $coreTotal += [double]$line.Groups["total"].Value
  }
  $corePercent = if ($coreTotal -eq 0) { 0.0 } else { 100.0 * $coreCovered / $coreTotal }
  $coreReport = "Core execution paths: {0}/{1} ({2:N2}%), minimum {3:N2}%." -f $coreCovered, $coreTotal, $corePercent, $MinimumCorePercent
  [IO.File]::AppendAllText($report, "`n$coreReport`n", [Text.UTF8Encoding]::new($false))
  if ($corePercent -lt $MinimumCorePercent) {
    throw "Core execution-path coverage is below its independent baseline. $coreReport"
  }
  Write-Host "Core coverage gate passed. $coreReport"
} finally {
  Pop-Location
}
