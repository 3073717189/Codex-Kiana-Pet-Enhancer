[CmdletBinding()]
param(
  [switch]$PromptRestart,
  [switch]$ForceRestart,
  [switch]$KeepPet
)

$ErrorActionPreference = 'Stop'
$utilityModule = Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1'
Import-Module $utilityModule -Force -ErrorAction Stop
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexKianaPet'
$installationPath = Join-Path $stateRoot 'installation.json'

function Read-Utf8JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
  try {
    $text = [System.IO.File]::ReadAllText($Path, $strictUtf8)
    return ($text | ConvertFrom-Json -ErrorAction Stop)
  } catch {
    throw "UTF-8 JSON 文件无效：$Path`r`n$($_.Exception.Message)"
  }
}

function Test-PathInside {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
  return $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)
}

function Remove-DirectorySafe {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$AllowedRoot)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if (-not (Test-PathInside -Path $Path -Root $AllowedRoot)) {
    throw "Refusing to remove a directory outside the allowed root: $Path"
  }
  [System.IO.Directory]::Delete([System.IO.Path]::GetFullPath($Path), $true)
}

function Enter-PetReleaseOperationLock {
  $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex = [System.Threading.Mutex]::new($false, "Local\CodexDreamSkin.$sid.Operation")
  $acquired = $false
  try {
    $acquired = $mutex.WaitOne(0)
  } catch [System.Threading.AbandonedMutexException] {
    $acquired = $true
  }
  if (-not $acquired) {
    $mutex.Dispose()
    throw '另一个 Codex 桌宠安装、启动或卸载操作正在运行，请稍后重试。'
  }
  return $mutex
}

function Exit-PetReleaseOperationLock {
  param([Parameter(Mandatory = $true)][System.Threading.Mutex]$Mutex)
  try { $Mutex.ReleaseMutex() } finally { $Mutex.Dispose() }
}

function Stop-InstalledPetLauncher {
  $launcherPath = [System.IO.Path]::GetFullPath((Join-Path $stateRoot 'launcher\Codex 琪亚娜桌宠.exe'))
  $deadline = [DateTime]::UtcNow.AddSeconds(3)
  do {
    $launchers = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
      try {
        $_.Path -and ([System.IO.Path]::GetFullPath($_.Path) -ieq $launcherPath)
      } catch { $false }
    })
    if ($launchers.Count -eq 0) { return }
    if ([DateTime]::UtcNow -ge $deadline) {
      $launchers | Stop-Process -Force -ErrorAction SilentlyContinue
      $forceDeadline = [DateTime]::UtcNow.AddSeconds(2)
      do {
        Start-Sleep -Milliseconds 100
        $remaining = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
          try {
            $_.Path -and ([System.IO.Path]::GetFullPath($_.Path) -ieq $launcherPath)
          } catch { $false }
        })
        if ($remaining.Count -eq 0) { return }
      } while ([DateTime]::UtcNow -lt $forceDeadline)
      throw '桌宠启动器仍在退出，已停止删除程序文件；请稍后重新运行卸载。'
    }
    Start-Sleep -Milliseconds 100
  } while ($true)
}

$operationLock = Enter-PetReleaseOperationLock
try {

if (-not (Test-Path -LiteralPath $installationPath -PathType Leaf)) {
  throw '未找到安装记录。桌宠增强可能尚未安装，或安装目录已被手动删除。'
}
$installation = Read-Utf8JsonFile -Path $installationPath
$installRoot = [System.IO.Path]::GetFullPath("$($installation.installRoot)")
if (-not (Test-PathInside -Path $installRoot -Root $stateRoot)) {
  throw '安装记录中的程序目录不安全，已拒绝卸载。'
}
$scripts = Join-Path $installRoot 'scripts'
$common = Join-Path $scripts 'pet-common.ps1'
$restore = Join-Path $scripts 'restore-pet-enhancer.ps1'
if (-not (Test-Path -LiteralPath $common -PathType Leaf) -or
  -not (Test-Path -LiteralPath $restore -PathType Leaf)) {
  throw '桌宠运行文件不完整，无法安全卸载。'
}

. $common
$codex = Get-DreamSkinCodexInstall
$wasRunning = (Get-DreamSkinCodexProcesses -Codex $codex).Count -gt 0
if ($wasRunning -and -not $ForceRestart) {
  if ($PromptRestart) {
    $shell = New-Object -ComObject WScript.Shell
    [void]$shell.Popup('请先完全退出所有 Codex 窗口，然后重新运行卸载器。卸载器不会自动关闭 Codex。', 0,
      'Codex 琪亚娜增强桌宠', 48)
  }
  Write-Warning 'Codex 正在运行。请先完全退出所有 Codex 窗口，再重新运行卸载器。'
  exit 2
}

& $restore -Uninstall -NoRelaunch -ForceRestart:$ForceRestart
Stop-InstalledPetLauncher

if (-not $KeepPet -and $installation.pet) {
  $petDestination = [System.IO.Path]::GetFullPath("$($installation.pet.destination)")
  $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
  } else { $env:CODEX_HOME }
  $petRoot = [System.IO.Path]::GetFullPath((Join-Path $codexHome 'pets'))
  $expected = [System.IO.Path]::GetFullPath((Join-Path $petRoot 'time-runner-kiana'))
  if ($petDestination -ine $expected -or -not (Test-PathInside -Path $petDestination -Root $petRoot)) {
    throw '安装记录中的桌宠目录不安全，已保留当前桌宠。'
  }
  $manifestPath = Join-Path $petDestination 'pet.json'
  $spritePath = Join-Path $petDestination 'spritesheet.webp'
  $matchesInstalled = (Test-Path -LiteralPath $manifestPath -PathType Leaf) -and
    (Test-Path -LiteralPath $spritePath -PathType Leaf) -and
    ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash -ieq "$($installation.pet.manifestSha256)") -and
    ((Get-FileHash -LiteralPath $spritePath -Algorithm SHA256).Hash -ieq "$($installation.pet.spritesheetSha256)")
  if ($matchesInstalled) {
    Remove-DirectorySafe -Path $petDestination -AllowedRoot $petRoot
    $backup = "$($installation.pet.backupPath)"
    if ([bool]$installation.pet.existedBefore -and $backup -and (Test-Path -LiteralPath $backup -PathType Container)) {
      if (-not (Test-PathInside -Path $backup -Root $stateRoot)) { throw '桌宠备份路径不安全，已停止恢复。' }
      Copy-Item -LiteralPath $backup -Destination $petDestination -Recurse -Force
      Remove-DirectorySafe -Path $backup -AllowedRoot $stateRoot
    }
  } elseif (Test-Path -LiteralPath $petDestination) {
    Write-Warning '桌宠文件在安装后被修改过，为避免丢失，卸载时予以保留。'
  }
}

$desktop = [Environment]::GetFolderPath('Desktop')
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
foreach ($folder in @($desktop, $startMenu)) {
  foreach ($name in @('Codex 琪亚娜桌宠.lnk', '卸载 Codex 琪亚娜桌宠.lnk')) {
    Remove-Item -LiteralPath (Join-Path $folder $name) -Force -ErrorAction SilentlyContinue
  }
}
Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexKianaPet' -Recurse -Force -ErrorAction SilentlyContinue

Set-Location $env:TEMP
Remove-DirectorySafe -Path $installRoot -AllowedRoot $stateRoot
$launcherRoot = Join-Path $stateRoot 'launcher'
if (Test-Path -LiteralPath $launcherRoot) { Remove-DirectorySafe -Path $launcherRoot -AllowedRoot $stateRoot }
Remove-Item -LiteralPath $installationPath -Force -ErrorAction SilentlyContinue
if ($wasRunning) { Start-DreamSkinCodex -Codex $codex }

Write-Host ''
Write-Host '卸载完成：Codex 界面未被改动，增强桌宠已移除。' -ForegroundColor Green
} finally {
  Exit-PetReleaseOperationLock -Mutex $operationLock
}
