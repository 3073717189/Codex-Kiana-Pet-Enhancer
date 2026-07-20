[CmdletBinding()]
param(
  [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$OutputDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  Join-Path $root 'release\native'
} else {
  [System.IO.Path]::GetFullPath($OutputDirectory)
}

$petRoot = Join-Path $root 'assets\pets\time-runner-kiana'
$manifestPath = Join-Path $petRoot 'pet.json'
$spritesheetPath = Join-Path $petRoot 'spritesheet.webp'
$readmePath = Join-Path $petRoot 'README.md'
$licensePath = Join-Path $petRoot 'LICENSE'
$archivePath = Join-Path $OutputDirectory 'time-runner-kiana-codexpet-v2.zip'
$checksumPath = "$archivePath.sha256.txt"
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Get-WebPDimensions {
  param([Parameter(Mandatory = $true)][string]$Path)

  $stream = [System.IO.File]::OpenRead($Path)
  $reader = [System.IO.BinaryReader]::new($stream)
  try {
    if ([System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -cne 'RIFF') {
      throw 'The spritesheet is not a RIFF file.'
    }
    [void]$reader.ReadUInt32()
    if ([System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4)) -cne 'WEBP') {
      throw 'The spritesheet is not a WebP file.'
    }

    while ($stream.Position + 8 -le $stream.Length) {
      $chunkType = [System.Text.Encoding]::ASCII.GetString($reader.ReadBytes(4))
      $chunkSize = $reader.ReadUInt32()
      switch -CaseSensitive ($chunkType) {
        'VP8X' {
          if ($chunkSize -lt 10) { throw 'The WebP VP8X header is invalid.' }
          $header = $reader.ReadBytes(10)
          return [pscustomobject]@{
            Width = 1 + $header[4] + ($header[5] -shl 8) + ($header[6] -shl 16)
            Height = 1 + $header[7] + ($header[8] -shl 8) + ($header[9] -shl 16)
          }
        }
        'VP8L' {
          if ($chunkSize -lt 5) { throw 'The WebP VP8L header is invalid.' }
          $header = $reader.ReadBytes(5)
          if ($header[0] -ne 0x2F) { throw 'The WebP VP8L signature is invalid.' }
          $bits = [uint64]$header[1] +
            ([uint64]$header[2] -shl 8) +
            ([uint64]$header[3] -shl 16) +
            ([uint64]$header[4] -shl 24)
          return [pscustomobject]@{
            Width = 1 + [int]($bits -band 0x3FFF)
            Height = 1 + [int](($bits -shr 14) -band 0x3FFF)
          }
        }
        'VP8 ' {
          if ($chunkSize -lt 10) { throw 'The WebP VP8 header is invalid.' }
          $header = $reader.ReadBytes(10)
          if ($header[3] -ne 0x9D -or $header[4] -ne 0x01 -or $header[5] -ne 0x2A) {
            throw 'The WebP VP8 key-frame signature is invalid.'
          }
          return [pscustomobject]@{
            Width = ($header[6] + ($header[7] -shl 8)) -band 0x3FFF
            Height = ($header[8] + ($header[9] -shl 8)) -band 0x3FFF
          }
        }
      }

      $next = $stream.Position + $chunkSize + ($chunkSize % 2)
      if ($next -gt $stream.Length) { throw 'The WebP chunk table is invalid.' }
      $stream.Position = $next
    }
  } finally {
    $reader.Dispose()
    $stream.Dispose()
  }

  throw 'No supported WebP canvas header was found.'
}

foreach ($path in @($manifestPath, $spritesheetPath, $readmePath, $licensePath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Native pet source file is missing: $path"
  }
}

$manifestText = [System.IO.File]::ReadAllText($manifestPath, $strictUtf8)
$manifest = $manifestText | ConvertFrom-Json -ErrorAction Stop
if ($manifest.id -cne 'time-runner-kiana') {
  throw 'Unexpected native pet id.'
}
if ([int]$manifest.spriteVersionNumber -ne 2) {
  throw 'The native pet manifest must declare spriteVersionNumber 2.'
}
if ($manifest.spritesheetPath -cne 'spritesheet.webp') {
  throw 'The native pet manifest must point to spritesheet.webp.'
}

$dimensions = Get-WebPDimensions -Path $spritesheetPath
if ($dimensions.Width -ne 1536 -or $dimensions.Height -ne 2288) {
  throw "Unexpected v2 atlas dimensions: $($dimensions.Width)x$($dimensions.Height)"
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
foreach ($path in @($archivePath, $checksumPath)) {
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::Open(
  $archivePath,
  [System.IO.Compression.ZipArchiveMode]::Create
)
try {
  [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $archive,
    $manifestPath,
    'pet.json',
    [System.IO.Compression.CompressionLevel]::Optimal
  )
  [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $archive,
    $spritesheetPath,
    'spritesheet.webp',
    [System.IO.Compression.CompressionLevel]::Optimal
  )
  [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $archive,
    $readmePath,
    'README.md',
    [System.IO.Compression.CompressionLevel]::Optimal
  )
  [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
    $archive,
    $licensePath,
    'LICENSE',
    [System.IO.Compression.CompressionLevel]::Optimal
  )
} finally {
  $archive.Dispose()
}

$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
[System.IO.File]::WriteAllText(
  $checksumPath,
  "$hash  $([System.IO.Path]::GetFileName($archivePath))`r`n",
  [System.Text.UTF8Encoding]::new($false)
)

Write-Host "Built native CodexPet package: $archivePath"
Write-Host "SHA-256: $hash"
Write-Output $archivePath
