$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

Push-Location $projectRoot
try {
  $repositoryFiles = @(git ls-files --cached --others --exclude-standard)
  if ($LASTEXITCODE -ne 0) { throw "git ls-files failed." }
  $forbiddenFiles = $repositoryFiles | Where-Object {
    $_ -match '(^|/)(\.env($|\.)|id_rsa|credentials\.json)$' -or
    $_ -match '\.(pfx|p12|key)$'
  }
  if ($forbiddenFiles) {
    throw "Sensitive file names are tracked:`n$($forbiddenFiles -join "`n")"
  }

  $patterns = @(
    '(?i)gh[pousr]_[A-Za-z0-9]{20,}',
    '(?i)github_pat_[A-Za-z0-9_]{20,}',
    '(?i)-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----',
    '(?i)[A-Za-z]:\\Users\\[^\\\s]+',
    '(?i)/home/[^/\s]+/',
    ('codex-' + 'clipboard-'),
    ('聊天' + '记录')
  )
  $violations = [Collections.Generic.List[String]]::new()
  foreach ($path in $repositoryFiles) {
    if ($path -eq "tools/check-repository-hygiene.ps1") { continue }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    # Get-Item treats dotfiles inconsistently on some PowerShell/Linux builds.
    # FileInfo gives the same byte-level view on Windows, macOS, and Linux.
    $item = [IO.FileInfo]::new((Join-Path $projectRoot $path))
    if ($item.Length -gt 2MB) { continue }
    $text = [IO.File]::ReadAllText($item.FullName)
    foreach ($pattern in $patterns) {
      if ($text -match $pattern) {
        $violations.Add("$path matches forbidden repository pattern $pattern")
      }
    }
  }
  if ($violations.Count -gt 0) { throw ($violations -join "`n") }
  Write-Host "Repository hygiene gate passed for $($repositoryFiles.Count) tracked and pending files."
} finally {
  Pop-Location
}
