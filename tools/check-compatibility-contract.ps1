$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$contractPath = Join-Path $projectRoot "docs/compatibility-contract.json"
$contract = [IO.File]::ReadAllText($contractPath) | ConvertFrom-Json

if ($contract.schema -ne 1) { throw "Unsupported compatibility contract schema." }
if ($contract.target.version -cne "0.4.0") { throw "Compatibility target must remain Wren 0.4.0." }
if ($contract.target.commit -cne "4a18fc489f9ea3d253b20dd40f4cdad0d6bb40eb") {
  throw "Compatibility reference commit changed without an explicit scope review."
}
if ($contract.areas.Count -lt 20) { throw "Compatibility contract is missing required areas." }

$allowedLevels = @("supported", "optional", "experimental", "excluded")
$seen = @{}
$counts = @{}
foreach ($area in $contract.areas) {
  if (-not $area.id -or $area.id -notmatch '^[a-z0-9-]+$') {
    throw "Compatibility area has an invalid id: $($area.id)"
  }
  if ($seen.ContainsKey($area.id)) { throw "Duplicate compatibility area: $($area.id)" }
  $seen[$area.id] = $true
  if ($allowedLevels -notcontains $area.level) {
    throw "Area $($area.id) has invalid level $($area.level)."
  }
  if (-not $counts.ContainsKey($area.level)) { $counts[$area.level] = 0 }
  $counts[$area.level]++
  if (-not $area.evidence -or $area.evidence.Count -eq 0) {
    throw "Area $($area.id) has no evidence."
  }
  foreach ($relative in $area.evidence) {
    $candidate = Join-Path $projectRoot $relative
    if (-not (Test-Path -LiteralPath $candidate)) {
      throw "Area $($area.id) references missing evidence: $relative"
    }
  }
}
foreach ($level in $allowedLevels) {
  if (-not $counts.ContainsKey($level)) { throw "Compatibility level $level has no entries." }
}
Write-Host ("Compatibility contract passed: {0} areas ({1} supported, {2} optional, {3} experimental, {4} excluded)." -f $contract.areas.Count, $counts.supported, $counts.optional, $counts.experimental, $counts.excluded)
