param(
  [Parameter(Mandatory = $true)]
  [string]$WrenRoot,

  [string[]]$Category = @("language", "core"),

  [string]$Executable,

  [int]$MaximumCases = 0,

  [ValidateRange(1000, 120000)]
  [int]$CaseTimeoutMilliseconds = 15000,

  [string]$ReportPath,

  [switch]$AllowFailures
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $WrenRoot "test"

if (-not (Test-Path -LiteralPath $testRoot -PathType Container)) {
  throw "Wren test directory was not found: $testRoot"
}

if (-not $Executable) {
  $extension = if ($IsWindows) { ".exe" } else { "" }
  $Executable = Join-Path $projectRoot "_build/native/debug/build/cmd/main/main$extension"
}

if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
  throw "MoonWren executable was not found: $Executable. Run 'moon build --target native' first."
}

function Get-TestExpectation {
  param([string]$Path)

  $source = [System.IO.File]::ReadAllText($Path)
  if ($source -match "//\s*(skip:|nontest)") {
    return $null
  }

  $outputs = [System.Collections.Generic.List[string]]::new()
  $compileLines = [System.Collections.Generic.HashSet[int]]::new()
  $runtimeMessage = $null
  $runtimeLine = 0
  $handledRuntimeError = $false
  $lineNumber = 0

  foreach ($line in [regex]::Split($source, "\r\n|\n|\r")) {
    $lineNumber++
    $match = [regex]::Match($line, "//\s*expect:\s?(.*)$")
    if ($match.Success) {
      $outputs.Add($match.Groups[1].Value)
    }

    $match = [regex]::Match($line, "//\s*expect error line (\d+)")
    if ($match.Success) {
      [void]$compileLines.Add([int]$match.Groups[1].Value)
    } elseif ($line -match "//\s*expect error(?! line)") {
      [void]$compileLines.Add($lineNumber)
    }

    $match = [regex]::Match(
      $line,
      "//\s*expect (handled )?runtime error:\s*(.+)$"
    )
    if ($match.Success) {
      $handledRuntimeError = $match.Groups[1].Success
      $runtimeMessage = $match.Groups[2].Value
      $runtimeLine = $lineNumber
    }
  }

  [pscustomobject]@{
    Output = $outputs.ToArray()
    CompileLines = @($compileLines | Sort-Object)
    RuntimeMessage = $runtimeMessage
    RuntimeLine = $runtimeLine
    HandledRuntimeError = $handledRuntimeError
  }
}

function Invoke-MoonWrenCase {
  param([string]$Path)

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $Executable
  $startInfo.ArgumentList.Add($Path)
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()

  $stdoutTask = $process.StandardOutput.ReadToEndAsync()
  $stderrTask = $process.StandardError.ReadToEndAsync()
  if (-not $process.WaitForExit($CaseTimeoutMilliseconds)) {
    $process.Kill($true)
    $process.WaitForExit()
    return [pscustomobject]@{
      ExitCode = -1
      Stdout = ""
      Stderr = ""
      TimedOut = $true
    }
  }

  [pscustomobject]@{
    ExitCode = $process.ExitCode
    Stdout = $stdoutTask.GetAwaiter().GetResult()
    Stderr = $stderrTask.GetAwaiter().GetResult()
    TimedOut = $false
  }
}

function Get-ObservedResult {
  param([string]$Stdout)

  $output = [System.Collections.Generic.List[string]]::new()
  $diagnosticLines = [System.Collections.Generic.List[int]]::new()
  $diagnosticMessages = [System.Collections.Generic.List[string]]::new()
  $normalized = $Stdout.Replace("`r`n", "`n").Replace("`r", "`n")
  $hasOutput = $normalized.Length -gt 0
  if ($normalized.EndsWith("`n")) {
    $normalized = $normalized.Substring(0, $normalized.Length - 1)
  }
  $lines = if ($hasOutput) { [regex]::Split($normalized, "\n") } else { @() }
  foreach ($line in $lines) {
    if ($line -match "^(.*):(\d+):(\d+): (.*)$") {
      $diagnosticLines.Add([int]$Matches[2])
      $diagnosticMessages.Add($Matches[4])
    } elseif ($line -notmatch "^\s+at .+\(.+:\d+:\d+\)$") {
      $output.Add($line)
    }
  }

  [pscustomobject]@{
    Output = $output.ToArray()
    DiagnosticLines = $diagnosticLines.ToArray()
    DiagnosticMessages = $diagnosticMessages.ToArray()
  }
}

$cases = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
foreach ($name in $Category) {
  $directory = Join-Path $testRoot $name
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    throw "Unknown Wren test category: $name"
  }
  foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -File -Filter "*.wren") {
    $cases.Add($file)
  }
}

$orderedCases = @($cases | Sort-Object FullName)
if ($MaximumCases -gt 0) {
  $orderedCases = @($orderedCases | Select-Object -First $MaximumCases)
}

$results = [System.Collections.Generic.List[object]]::new()
$passed = 0
$failed = 0
$skipped = 0

foreach ($case in $orderedCases) {
  $expectation = Get-TestExpectation -Path $case.FullName
  if ($null -eq $expectation) {
    $skipped++
    continue
  }

  $run = Invoke-MoonWrenCase -Path $case.FullName
  $observed = Get-ObservedResult -Stdout $run.Stdout
  $problems = [System.Collections.Generic.List[string]]::new()

  if ($run.TimedOut) {
    $problems.Add("timed out")
  } elseif ($expectation.CompileLines.Count -gt 0) {
    if ($run.ExitCode -ne 65) {
      $problems.Add("expected compile exit 65, got $($run.ExitCode)")
    }
    foreach ($line in $expectation.CompileLines) {
      if ($line -notin $observed.DiagnosticLines) {
        $problems.Add("missing compile diagnostic on line $line")
      }
    }
  } elseif ($null -ne $expectation.RuntimeMessage) {
    $expectedExit = if ($expectation.HandledRuntimeError) { 0 } else { 70 }
    if ($run.ExitCode -ne $expectedExit) {
      $problems.Add("expected runtime exit $expectedExit, got $($run.ExitCode)")
    }
    if (-not $expectation.HandledRuntimeError -and
        $expectation.RuntimeLine -notin $observed.DiagnosticLines) {
      $problems.Add("missing runtime diagnostic on line $($expectation.RuntimeLine)")
    }
  } elseif ($run.ExitCode -ne 0) {
    $problems.Add("expected success exit 0, got $($run.ExitCode)")
  }

  $expectedOutputText = ([string[]]$expectation.Output) -join "`n"
  $actualOutputText = ([string[]]$observed.Output) -join "`n"
  if ($expectedOutputText -cne $actualOutputText) {
    $problems.Add("output mismatch")
  }

  $relative = [System.IO.Path]::GetRelativePath($testRoot, $case.FullName).Replace("\", "/")
  $success = $problems.Count -eq 0
  if ($success) { $passed++ } else { $failed++ }
  $results.Add([pscustomobject]@{
    Path = $relative
    Passed = $success
    Problems = $problems.ToArray()
    ExitCode = $run.ExitCode
    ExpectedOutput = $expectation.Output
    ActualOutput = $observed.Output
    Diagnostics = $observed.DiagnosticMessages
  })
}

$report = [pscustomobject]@{
  Reference = "wren-lang/wren 0.4.0 (4a18fc489f9ea3d253b20dd40f4cdad0d6bb40eb)"
  Categories = $Category
  Passed = $passed
  Failed = $failed
  Skipped = $skipped
  Total = $passed + $failed
  Results = $results.ToArray()
}

Write-Host "Official Wren 0.4.0 audit: $passed passed, $failed failed, $skipped skipped."
foreach ($failure in @($results | Where-Object { -not $_.Passed } | Select-Object -First 25)) {
  Write-Host "FAIL $($failure.Path): $($failure.Problems -join '; ')"
}
if ($failed -gt 25) {
  Write-Host "... $($failed - 25) additional failures are available in the JSON report."
}

if ($ReportPath) {
  $parent = Split-Path -Parent $ReportPath
  if ($parent) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding utf8
}

if ($failed -gt 0 -and -not $AllowFailures) {
  exit 1
}
