[CmdletBinding()]
param(
  [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'CodexKianaPet\launcher'),
  [string]$IconSourcePath
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'pet-common.ps1')
$sourcePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'launcher\PetEnhancerLauncher.cs'
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
  throw "Pet Enhancer launcher source is missing: $sourcePath"
}
$compiler = @(
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
  (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $compiler) { throw 'The .NET Framework C# compiler is unavailable.' }

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$iconPath = Join-Path $OutputRoot 'codex.ico'
$launcherPath = Join-Path $OutputRoot 'Codex 琪亚娜桌宠.exe'
$temporaryLauncherPath = Join-Path $OutputRoot 'Codex 琪亚娜桌宠.new.exe'
$resolvedIconSource = if ([string]::IsNullOrWhiteSpace($IconSourcePath)) {
  (Get-DreamSkinCodexInstall).Executable
} else {
  [System.IO.Path]::GetFullPath($IconSourcePath)
}
if (-not (Test-Path -LiteralPath $resolvedIconSource -PathType Leaf)) {
  throw "Launcher icon source is missing: $resolvedIconSource"
}
Add-Type -AssemblyName System.Drawing
$icon = [System.Drawing.Icon]::ExtractAssociatedIcon($resolvedIconSource)
if ($null -eq $icon) { throw 'The official Codex icon could not be extracted.' }
try {
  $stream = [System.IO.File]::Create($iconPath)
  try { $icon.Save($stream) } finally { $stream.Dispose() }
} finally {
  $icon.Dispose()
}

Remove-Item -LiteralPath $temporaryLauncherPath -Force -ErrorAction SilentlyContinue
& $compiler @(
  '/nologo', '/target:winexe', '/optimize+', '/platform:anycpu',
  "/win32icon:$iconPath", "/out:$temporaryLauncherPath",
  '/reference:System.dll', '/reference:System.Core.dll', '/reference:System.Windows.Forms.dll',
  $sourcePath
)
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporaryLauncherPath -PathType Leaf)) {
  throw "Pet Enhancer launcher compilation failed with exit code $LASTEXITCODE."
}
if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
  $replacementBackupPath = Join-Path $OutputRoot `
    ("Codex 琪亚娜桌宠.previous-" + [guid]::NewGuid().ToString('N') + '.exe')
  try {
    [System.IO.File]::Replace($temporaryLauncherPath, $launcherPath, $replacementBackupPath)
  } catch {
    $replacementFailure = $_
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf) -and
      (Test-Path -LiteralPath $replacementBackupPath -PathType Leaf)) {
      try {
        Move-Item -LiteralPath $replacementBackupPath -Destination $launcherPath
      } catch {
        throw "Launcher replacement and rollback both failed. The previous launcher is preserved at: $replacementBackupPath`r`n$($replacementFailure.Exception.Message)`r`n$($_.Exception.Message)"
      }
    }
    throw $replacementFailure
  } finally {
    Remove-Item -LiteralPath $temporaryLauncherPath -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $launcherPath -PathType Leaf) {
      Remove-Item -LiteralPath $replacementBackupPath -Force -ErrorAction SilentlyContinue
    }
  }
} else {
  Move-Item -LiteralPath $temporaryLauncherPath -Destination $launcherPath
}
Write-Output $launcherPath
