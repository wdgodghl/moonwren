param(
  [Parameter(Mandatory = $true)] [string]$OfficialWren,
  [string]$MoonWren,
  [ValidateRange(1, 10000)] [int]$Cases = 200,
  [int]$Seed = 20261025,
  [ValidateRange(1, 3600)] [int]$MaxSeconds = 900,
  [string]$CorpusDirectory,
  [string]$FailureDirectory
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $MoonWren) {
  $MoonWren = @(
    (Join-Path $projectRoot "_build/native/debug/build/cmd/main/main"),
    (Join-Path $projectRoot "_build/native/debug/build/cmd/main/main.exe")
  ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
}
if (-not $FailureDirectory) { $FailureDirectory = Join-Path $projectRoot ".tmp/fuzz-failures" }
$resultDirectory = Join-Path $projectRoot ".tmp/fuzz-results"
New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null
foreach ($executable in @($OfficialWren, $MoonWren)) {
  if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Executable not found: $executable" }
}

$random = [System.Random]::new($Seed)
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("moonwren-fuzz-" + [guid]::NewGuid().ToString("N"))
[void](New-Item -ItemType Directory -Path $temporaryRoot)

function Invoke-WrenProgram {
  param([string]$Executable, [string]$Path)
  $output = & $Executable $Path 2>&1
  [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = (($output | ForEach-Object { $_.ToString() }) -join "`n").TrimEnd() }
}

function Test-DifferentialMismatch {
  param([string]$Source, [string]$CasePath)
  [System.IO.File]::WriteAllText($CasePath, $Source)
  $official = Invoke-WrenProgram -Executable $OfficialWren -Path $CasePath
  $candidate = Invoke-WrenProgram -Executable $MoonWren -Path $CasePath
  [pscustomobject]@{ Mismatch = $official.ExitCode -ne $candidate.ExitCode -or $official.Output -ne $candidate.Output; Official = $official; Candidate = $candidate }
}

function Reduce-FailingProgram {
  param([string]$Source, [string]$CasePath)
  $lines = [Collections.Generic.List[string]]::new()
  foreach ($line in ($Source -split "`r?`n")) { $lines.Add($line) }
  $changed = $true
  while ($changed -and $lines.Count -gt 1) {
    $changed = $false
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
      $candidateLines = [Collections.Generic.List[string]]::new($lines)
      $candidateLines.RemoveAt($index)
      $candidateSource = ($candidateLines -join "`n") + "`n"
      if ((Test-DifferentialMismatch -Source $candidateSource -CasePath $CasePath).Mismatch) {
        $lines = $candidateLines
        $changed = $true
      }
    }
  }
  (($lines -join "`n") + "`n")
}

function New-GeneratedProgram {
  param([int]$Index)
  $a = $random.Next(-1000, 1001)
  $b = $random.Next(-1000, 1001)
  $limit = $random.Next(1, 30)
  switch ($Index % 10) {
    0 { return "var a = $a`nvar b = $b`nvar total = 0`nfor (index in 0...$limit) total = total + (a * 3 - b * 2 + index)`nSystem.print(total)`nSystem.print((a < b) || (total == 0))`n" }
    1 { return "var values = [$a, $b, $limit]`nvalues.add($($a + $b))`nSystem.print(values.count)`nSystem.print(values[1])`nSystem.print(values[-1])`n" }
    2 { return "var values = {`"a`": $a, `"b`": $b}`nvalues[`"sum`"] = values[`"a`"] + values[`"b`"]`nSystem.print(values.count)`nSystem.print(values[`"sum`"] )`n" }
    3 { return "var worker = Fiber.new {`n  Fiber.yield($a)`n  return $b`n}`nSystem.print(worker.call())`nSystem.print(worker.call())`n" }
    4 { return "var text = `"你好-MoonWren-$limit`"`nSystem.print(text.count)`nSystem.print(text.bytes.count)`nSystem.print(text.contains(`"Moon`"))`n" }
    5 { return "var base = $a`nvar make = Fn.new { |offset| Fn.new { |value| base + offset + value } }`nvar add = make.call($b)`nSystem.print(add.call($limit))`n" }
    6 { return "class Base { construct new(value) { _value = value } value { _value } }`nclass Child is Base { construct new(value) { super(value) } doubled { super.value * 2 } }`nvar item = Child.new($limit)`nSystem.print(item.value)`nSystem.print(item.doubled)`n" }
    7 { return "var values = (1..$limit).map { |value| value * 2 }.where { |value| value % 3 == 0 }.toList`nSystem.print(values.count)`nSystem.print(values.reduce(0) { |sum, value| sum + value })`n" }
    8 { return "var text = String.fromByte($($limit + 127)) + `"abc`"`nSystem.print(text.bytes.count)`nSystem.print(text.bytes[0])`nSystem.print(text[1..-1])`n" }
    default { return "var values = {`"a`": $a, `"b`": $b, `"limit`": $limit}`nvar total = 0`nfor (entry in values) total = total + entry.value`nSystem.print(total)`nSystem.print(values.keys.toList.join(`",`"))`n" }
  }
}

$programs = [Collections.Generic.List[object]]::new()
for ($index = 0; $index -lt $Cases; $index++) {
  $programs.Add([pscustomobject]@{ Name = "generated-{0:D5}" -f $index; Source = New-GeneratedProgram -Index $index })
}
if ($CorpusDirectory) {
  if (-not (Test-Path -LiteralPath $CorpusDirectory -PathType Container)) { throw "Corpus directory not found: $CorpusDirectory" }
  foreach ($file in Get-ChildItem -LiteralPath $CorpusDirectory -File -Filter "*.wren" | Sort-Object Name) {
    $programs.Add([pscustomobject]@{ Name = "corpus-$($file.BaseName)"; Source = Get-Content -LiteralPath $file.FullName -Raw })
  }
}

try {
  $stopwatch = [Diagnostics.Stopwatch]::StartNew()
  $executed = 0
  $matchedSuccess = 0
  $matchedFailure = 0
  foreach ($program in $programs) {
    if ($stopwatch.Elapsed.TotalSeconds -ge $MaxSeconds) { break }
    $path = Join-Path $temporaryRoot ($program.Name + ".wren")
    $comparison = Test-DifferentialMismatch -Source $program.Source -CasePath $path
    $executed++
    if ($comparison.Mismatch) {
      $minimized = Reduce-FailingProgram -Source $program.Source -CasePath $path
      $final = Test-DifferentialMismatch -Source $minimized -CasePath $path
      [void](New-Item -ItemType Directory -Path $FailureDirectory -Force)
      $prefix = Join-Path $FailureDirectory ("seed-{0}-{1}" -f $Seed, $program.Name)
      [System.IO.File]::WriteAllText($prefix + ".wren", $minimized)
      [System.IO.File]::WriteAllText($prefix + ".official.txt", $final.Official.Output)
      [System.IO.File]::WriteAllText($prefix + ".moonwren.txt", $final.Candidate.Output)
      $metadata = [ordered]@{
        seed = $Seed
        case = $program.Name
        official_exit_code = $final.Official.ExitCode
        moonwren_exit_code = $final.Candidate.ExitCode
        minimized_sha256 = (Get-FileHash -LiteralPath ($prefix + ".wren") -Algorithm SHA256).Hash.ToLowerInvariant()
      } | ConvertTo-Json
      [System.IO.File]::WriteAllText($prefix + ".json", $metadata, [Text.UTF8Encoding]::new($false))
      throw "Differential mismatch in $($program.Name) (seed $Seed). Minimized reproducer saved to $prefix.wren"
    }
    if ($comparison.Official.ExitCode -eq 0) { $matchedSuccess++ } else { $matchedFailure++ }
  }
  $summary = [ordered]@{
    seed = $Seed
    requested_generated_cases = $Cases
    available_cases = $programs.Count
    executed_cases = $executed
    matched_successes = $matchedSuccess
    matched_failures = $matchedFailure
    elapsed_seconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
    max_seconds = $MaxSeconds
    timed_out = $executed -lt $programs.Count
  }
  $summaryPath = Join-Path $resultDirectory ("seed-{0}.json" -f $Seed)
  [System.IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  Write-Host ("Differential fuzzing passed: {0}/{1} cases (seed {2}, {3}s budget)." -f $executed, $programs.Count, $Seed, $MaxSeconds)
}
catch {
  $failureSummary = [ordered]@{
    seed = $Seed
    status = "failed"
    message = $_.Exception.Message
  }
  $summaryPath = Join-Path $resultDirectory ("seed-{0}.json" -f $Seed)
  [System.IO.File]::WriteAllText($summaryPath, ($failureSummary | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
  throw
}
finally {
  if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}
