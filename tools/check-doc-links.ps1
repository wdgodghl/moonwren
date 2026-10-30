$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$files = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$files.Add((Get-Item -LiteralPath (Join-Path $root "README.md")))
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $root "docs") -Recurse -File -Filter "*.md") {
  $files.Add($file)
}
$files.Add((Get-Item -LiteralPath (Join-Path $root "conformance/wren-0.4.0/manifest.md")))

$problems = [System.Collections.Generic.List[string]]::new()
$checked = 0
$pattern = [regex]'!?(?:\[[^\]]*\])\((?<target>[^)]+)\)'

foreach ($file in $files) {
  $content = [System.IO.File]::ReadAllText($file.FullName)
  foreach ($match in $pattern.Matches($content)) {
    $target = $match.Groups["target"].Value.Trim()
    if ($target.StartsWith("<") -and $target.EndsWith(">")) {
      $target = $target.Substring(1, $target.Length - 2)
    } elseif ($target -match '^(?<path>\S+)(?:\s+["''][^"'']*["''])?$') {
      $target = $Matches["path"]
    }

    if ($target -match '^(?:https?://|mailto:|#)') {
      continue
    }
    $pathPart = ($target -split '#', 2)[0]
    if ([string]::IsNullOrWhiteSpace($pathPart)) {
      continue
    }
    $pathPart = [System.Uri]::UnescapeDataString($pathPart)
    $resolved = [System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $pathPart))
    $checked++
    if (-not (Test-Path -LiteralPath $resolved)) {
      $relativeFile = [System.IO.Path]::GetRelativePath($root, $file.FullName).Replace("\", "/")
      $problems.Add("$relativeFile -> $target")
    }
  }
}

if ($problems.Count -gt 0) {
  throw "Broken local documentation links:`n$($problems -join "`n")"
}
Write-Host "Documentation link gate passed: $checked local targets resolved across $($files.Count) files."

