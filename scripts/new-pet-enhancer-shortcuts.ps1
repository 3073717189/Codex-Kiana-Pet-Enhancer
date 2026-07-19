[CmdletBinding()]
param(
  [int]$Port = 9345,
  [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'CodexKianaPet\launcher'),
  [string]$DesktopFolder = [Environment]::GetFolderPath('Desktop'),
  [string]$StartMenuFolder = (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'),
  [string]$IconSourcePath
)

$ErrorActionPreference = 'Stop'
$skillRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'build-pet-enhancer-launcher.ps1'
$startScript = Join-Path $PSScriptRoot 'start-pet-enhancer.ps1'
$restoreScript = Join-Path $PSScriptRoot 'restore-pet-enhancer.ps1'
$buildArguments = @{ OutputRoot = $OutputRoot }
if (-not [string]::IsNullOrWhiteSpace($IconSourcePath)) {
  $buildArguments.IconSourcePath = $IconSourcePath
}
$launcherPath = @(& $buildScript @buildArguments) | Select-Object -Last 1
if (-not $launcherPath -or -not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
  throw 'Kiana Pet Enhancer launcher was not built successfully.'
}

$shell = New-Object -ComObject WScript.Shell
$launcherArguments = "--script `"$startScript`" --port $Port"
foreach ($folder in @($DesktopFolder, $StartMenuFolder)) {
  New-Item -ItemType Directory -Force -Path $folder | Out-Null
  $shortcut = $shell.CreateShortcut((Join-Path $folder 'Codex 琪亚娜桌宠.lnk'))
  $shortcut.TargetPath = $launcherPath
  $shortcut.Arguments = $launcherArguments
  $shortcut.WorkingDirectory = $skillRoot
  $shortcut.Description = '启动带琪亚娜增强桌宠的官方 Codex'
  $shortcut.IconLocation = "$launcherPath,0"
  $shortcut.Save()
}

$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$restore = $shell.CreateShortcut((Join-Path $DesktopFolder '卸载 Codex 琪亚娜桌宠.lnk'))
$restore.TargetPath = $powershell
$restore.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$restoreScript`" -Port $Port -Uninstall"
$restore.WorkingDirectory = $skillRoot
$restore.Description = '请先退出 Codex，再移除增强桌宠并恢复普通启动方式'
$restore.IconLocation = "$launcherPath,0"
$restore.Save()

Write-Output $launcherPath
