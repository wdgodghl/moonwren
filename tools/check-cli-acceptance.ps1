param(
  [string]$Executable
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (-not $Executable) {
  $candidates = @(
    (Join-Path $root "_build/native/debug/build/cmd/main/main"),
    (Join-Path $root "_build/native/debug/build/cmd/main/main.exe")
  )
  $Executable = $candidates |
    Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
    Select-Object -First 1
}

if (-not $Executable -or -not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
  throw "MoonWren native CLI was not found. Run 'moon build --target native' first."
}

function Invoke-CliCase {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [string[]]$Arguments = @(),
    [Parameter(Mandatory = $true)]
    [int]$ExpectedExitCode,
    [AllowNull()]
    [string]$ExpectedStdout = $null,
    [AllowNull()]
    [string]$StdoutContains = $null
  )

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $Executable
  $startInfo.WorkingDirectory = $root
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.CreateNoWindow = $true
  foreach ($argument in $Arguments) {
    $startInfo.ArgumentList.Add($argument)
  }

  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  $stdout = $stdout.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n")
  $stderr = $stderr.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n")
  if ($process.ExitCode -ne $ExpectedExitCode) {
    throw "$Name expected exit $ExpectedExitCode, received $($process.ExitCode).`nSTDOUT:`n$stdout`nSTDERR:`n$stderr"
  }
  if ($PSBoundParameters.ContainsKey("ExpectedStdout") -and
      $stdout -cne $ExpectedStdout) {
    throw "$Name output mismatch.`nEXPECTED:`n$ExpectedStdout`nACTUAL:`n$stdout"
  }
  if ($PSBoundParameters.ContainsKey("StdoutContains") -and
      -not $stdout.Contains($StdoutContains)) {
    throw "$Name output did not contain '$StdoutContains'.`nACTUAL:`n$stdout"
  }
  if ($stderr.Length -ne 0) {
    throw "$Name wrote unexpected stderr:`n$stderr"
  }
  Write-Host "PASS $Name"
}

Invoke-CliCase -Name "bundled default" -ExpectedExitCode 0 -ExpectedStdout "55"
Invoke-CliCase -Name "eval" -Arguments @("--eval", "System.print(40 + 2)") `
  -ExpectedExitCode 0 -ExpectedStdout "42"
Invoke-CliCase -Name "relative module imports" `
  -Arguments @((Join-Path $root "examples/modules/main.wren")) `
  -ExpectedExitCode 0 -ExpectedStdout "hello from an imported module`n42"
Invoke-CliCase -Name "compile diagnostic" -Arguments @("--eval", "var =") `
  -ExpectedExitCode 65 -StdoutContains "expected variable name"
Invoke-CliCase -Name "runtime diagnostic" `
  -Arguments @("--eval", 'Fiber.abort("boom")') `
  -ExpectedExitCode 70 -StdoutContains "boom"

$missing = Join-Path $root ".tmp/acceptance-file-must-not-exist.wren"
if (Test-Path -LiteralPath $missing) {
  throw "Acceptance fixture unexpectedly exists: $missing"
}
Invoke-CliCase -Name "missing entry file" -Arguments @($missing) `
  -ExpectedExitCode 66 -StdoutContains "cannot read source file:"

Write-Host "CLI acceptance gate passed with six real process cases."

