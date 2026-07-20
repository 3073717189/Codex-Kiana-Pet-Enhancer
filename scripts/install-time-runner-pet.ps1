[CmdletBinding()]
param(
  [string]$CodexHome = $env:CODEX_HOME
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($CodexHome)) {
  $CodexHome = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
}

$source = [System.IO.Path]::GetFullPath(
  (Join-Path $PSScriptRoot '..\assets\pets\time-runner-kiana')
)
$manifestPath = Join-Path $source 'pet.json'
$spritesheetPath = Join-Path $source 'spritesheet.webp'
$readmePath = Join-Path $source 'README.md'
$licensePath = Join-Path $source 'LICENSE'

foreach ($path in @($manifestPath, $spritesheetPath, $readmePath, $licensePath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing native pet file: $path"
  }
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$manifestText = [System.IO.File]::ReadAllText($manifestPath, $strictUtf8)
$manifest = $manifestText | ConvertFrom-Json -ErrorAction Stop
if ($manifest.id -ne 'time-runner-kiana' -or [int]$manifest.spriteVersionNumber -ne 2) {
  throw 'The packaged pet manifest is not the expected v2 time-runner-kiana package.'
}

$destination = Join-Path (Join-Path $CodexHome 'pets') $manifest.id
New-Item -ItemType Directory -Force -Path $destination | Out-Null
Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $destination 'pet.json') -Force
Copy-Item -LiteralPath $spritesheetPath -Destination (Join-Path $destination 'spritesheet.webp') -Force
Copy-Item -LiteralPath $readmePath -Destination (Join-Path $destination 'README.md') -Force
Copy-Item -LiteralPath $licensePath -Destination (Join-Path $destination 'LICENSE') -Force

Write-Host "Installed $($manifest.displayName) to $destination"
Write-Host 'Open Codex Settings > Pets and refresh custom pets if it is not listed immediately.'
