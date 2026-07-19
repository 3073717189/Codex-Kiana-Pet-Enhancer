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

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "Missing pet manifest: $manifestPath"
}
if (-not (Test-Path -LiteralPath $spritesheetPath -PathType Leaf)) {
  throw "Missing pet spritesheet: $spritesheetPath"
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

Write-Host "Installed $($manifest.displayName) to $destination"
Write-Host 'Open Codex Settings > Pets and refresh custom pets if it is not listed immediately.'
