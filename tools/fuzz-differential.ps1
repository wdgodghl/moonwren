param(
  [Parameter(Mandatory = $true)] [string]$OfficialWren,
  [string]$MoonWren,
  [ValidateRange(1, 10000)] [int]$Cases = 200,
  [int]$Seed = 20261025,
  [string]$CorpusDirectory,
  [string]$FailureDirectory
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $MoonWren) { $MoonWren = Join-Path $projectRoot "_build/native/debug/build/cmd/main/main.exe" }
if (-not $FailureDirectory) { $FailureDirectory = Join-Path $projectRoot ".tmp/fuzz-failures" }
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
  switch ($Index % 5) {
    0 { return "var a = $a`nvar b = $b`nvar total = 0`nfor (index in 0...$limit) total = total + (a * 3 - b * 2 + index)`nSystem.print(total)`nSystem.print((a < b) || (total == 0))`n" }
    1 { return "var values = [$a, $b, $limit]`nvalues.add($($a + $b))`nSystem.print(values.count)`nSystem.print(values[1])`nSystem.print(values[-1])`n" }
    2 { return "var values = {`"a`": $a, `"b`": $b}`nvalues[`"sum`"] = values[`"a`"] + values[`"b`"]`nSystem.print(values.count)`nSystem.print(values[`"sum`"] )`n" }
    3 { return "var worker = Fiber.new {`n  Fiber.yield($a)`n  return $b`n}`nSystem.print(worker.call())`nSystem.print(worker.call())`n" }
    default { return "var text = `"你好-MoonWren-$limit`"`nSystem.print(text.count)`nSystem.print(text.bytes.count)`nSystem.print(text.contains(`"Moon`"))`n" }
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
  foreach ($program in $programs) {
    $path = Join-Path $temporaryRoot ($program.Name + ".wren")
    $comparison = Test-DifferentialMismatch -Source $program.Source -CasePath $path
    if ($comparison.Mismatch) {
      $minimized = Reduce-FailingProgram -Source $program.Source -CasePath $path
      $final = Test-DifferentialMismatch -Source $minimized -CasePath $path
      [void](New-Item -ItemType Directory -Path $FailureDirectory -Force)
      $prefix = Join-Path $FailureDirectory ("seed-{0}-{1}" -f $Seed, $program.Name)
      [System.IO.File]::WriteAllText($prefix + ".wren", $minimized)
      [System.IO.File]::WriteAllText($prefix + ".official.txt", $final.Official.Output)
      [System.IO.File]::WriteAllText($prefix + ".moonwren.txt", $final.Candidate.Output)
      throw "Differential mismatch in $($program.Name) (seed $Seed). Minimized reproducer saved to $prefix.wren"
    }
  }
  Write-Host "Differential fuzzing passed: $($programs.Count) cases (seed $Seed)."
}
finally {
  if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
}
