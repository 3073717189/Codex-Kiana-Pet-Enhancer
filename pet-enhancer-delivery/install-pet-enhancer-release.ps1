[CmdletBinding()]
param(
  [switch]$ForceRestart,
  [switch]$LaunchAfterInstall,
  [switch]$VerifyOnly,
  [switch]$SmokeTest
)

$ErrorActionPreference = 'Stop'
$utilityModule = Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1'
Import-Module $utilityModule -Force -ErrorAction Stop
$packageRoot = $PSScriptRoot
$payloadRoot = Join-Path $packageRoot 'payload'
$manifestPath = Join-Path $packageRoot 'release-manifest.json'
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexKianaPet'
$installRoot = Join-Path $stateRoot 'app'
$installationPath = Join-Path $stateRoot 'installation.json'
$uninstallerPath = Join-Path $stateRoot 'uninstall-pet-enhancer-release.ps1'
$launcherRoot = Join-Path $stateRoot 'launcher'
$stagingRoot = $null
$previousApp = $null
$installedScripts = $null
$petDestination = $null
$petRollbackBackup = $null
$petExistedBeforeTransaction = $false
$installedPet = $false
$codexWasRunning = $false
$commonLoaded = $false
$previousInstallationBytes = $null
$previousUninstallerBytes = $null
$oldInstallation = $null
$launcherRollbackBackup = $null
$shortcutSnapshots = @()
$uninstallRegistrationSnapshot = $null
$publicArtifactsCaptured = $false
$publicArtifactsTouched = $false
$operationLock = $null

function Write-Utf8NoBom {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

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

function Assert-PackageIntegrity {
  if (-not (Test-Path -LiteralPath $payloadRoot -PathType Container) -or
    -not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw '安装包不完整。请重新下载并完整解压 ZIP。'
  }
  $manifest = Read-Utf8JsonFile -Path $manifestPath
  if ([int]$manifest.schemaVersion -ne 1 -or $manifest.product -ne 'Codex Kiana Pet Enhancer' -or
    -not $manifest.version -or -not $manifest.files) {
    throw '安装包清单格式无效。'
  }
  $expected = @{}
  foreach ($file in @($manifest.files)) {
    $relative = "$($file.path)".Replace('/', '\')
    if ([string]::IsNullOrWhiteSpace($relative) -or [System.IO.Path]::IsPathRooted($relative) -or
      $relative.Contains('..')) {
      throw "安装包清单包含不安全路径：$relative"
    }
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $payloadRoot $relative))
    if (-not (Test-PathInside -Path $candidate -Root $payloadRoot) -or
      -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      throw "安装包文件缺失：$relative"
    }
    $hash = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash
    if ($hash -ine "$($file.sha256)" -or (Get-Item -LiteralPath $candidate).Length -ne [long]$file.size) {
      throw "安装包文件校验失败：$relative"
    }
    $expected[$relative.ToLowerInvariant()] = $true
  }
  $actual = @(Get-ChildItem -LiteralPath $payloadRoot -File -Recurse -Force)
  foreach ($file in $actual) {
    $relative = $file.FullName.Substring($payloadRoot.Length).TrimStart('\').ToLowerInvariant()
    if (-not $expected.ContainsKey($relative)) { throw "安装包包含未登记文件：$relative" }
  }
  if ($actual.Count -ne $expected.Count) { throw '安装包文件数量与清单不一致。' }
  foreach ($required in @(
      'licenses\license',
      'licenses\third_party_notices.md',
      'licenses\assets.md',
      'licenses\security.md',
      'licenses\codex-dream-skin-mit.txt',
      'runtime\node.exe',
      'runtime\license.txt',
      'scripts\pet-common.ps1',
      'scripts\pet-injector.mjs'
    )) {
    if (-not $expected.ContainsKey($required)) {
      throw "安装包缺少必须登记的文件：$required"
    }
  }
  $petDefinition = Read-Utf8JsonFile -Path (Join-Path $payloadRoot 'assets\pets\time-runner-kiana\pet.json')
  if ($petDefinition.id -ne 'time-runner-kiana' -or
    [int]$petDefinition.spriteVersionNumber -ne 2 -or
    [string]::IsNullOrWhiteSpace("$($petDefinition.displayName)")) {
    throw '安装包中的桌宠清单格式无效。'
  }
  return $manifest
}

function Set-UninstallRegistration {
  param([Parameter(Mandatory = $true)][string]$LauncherPath)
  $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexKianaPet'
  New-Item -Path $key -Force | Out-Null
  $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  New-ItemProperty -Path $key -Name DisplayName -PropertyType String -Value 'Codex 琪亚娜增强桌宠' -Force | Out-Null
  New-ItemProperty -Path $key -Name DisplayVersion -PropertyType String -Value "$($manifest.version)" -Force | Out-Null
  New-ItemProperty -Path $key -Name Publisher -PropertyType String -Value 'Community fan project' -Force | Out-Null
  New-ItemProperty -Path $key -Name DisplayIcon -PropertyType String -Value $LauncherPath -Force | Out-Null
  New-ItemProperty -Path $key -Name UninstallString -PropertyType String `
    -Value "`"$powershell`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$uninstallerPath`" -PromptRestart" -Force | Out-Null
  New-ItemProperty -Path $key -Name NoModify -PropertyType DWord -Value 1 -Force | Out-Null
  New-ItemProperty -Path $key -Name NoRepair -PropertyType DWord -Value 1 -Force | Out-Null
}

function New-UninstallShortcuts {
  $shell = New-Object -ComObject WScript.Shell
  $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
  foreach ($folder in @([Environment]::GetFolderPath('Desktop'),
      (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))) {
    $shortcut = $shell.CreateShortcut((Join-Path $folder '卸载 Codex 琪亚娜桌宠.lnk'))
    $shortcut.TargetPath = $powershell
    $shortcut.Arguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$uninstallerPath`" -PromptRestart"
    $shortcut.WorkingDirectory = $stateRoot
    $shortcut.Description = '卸载琪亚娜增强桌宠并恢复普通 Codex 启动方式'
    $shortcut.Save()
  }
}

function Get-UninstallRegistrationSnapshot {
  $subKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexKianaPet'
  $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey, $false)
  if ($null -eq $key) {
    return [pscustomobject]@{ Existed = $false; Values = @() }
  }
  try {
    $values = @(
      foreach ($name in $key.GetValueNames()) {
        [pscustomobject]@{
          Name = $name
          Value = $key.GetValue($name, $null,
            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
          Kind = $key.GetValueKind($name)
        }
      }
    )
    return [pscustomobject]@{ Existed = $true; Values = $values }
  } finally {
    $key.Dispose()
  }
}

function Restore-UninstallRegistrationSnapshot {
  param([Parameter(Mandatory = $true)]$Snapshot)
  $providerPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexKianaPet'
  Remove-Item -Path $providerPath -Recurse -Force -ErrorAction SilentlyContinue
  if (-not [bool]$Snapshot.Existed) { return }

  $subKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\CodexKianaPet'
  $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($subKey)
  if ($null -eq $key) { throw '无法恢复旧版卸载注册。' }
  try {
    foreach ($entry in @($Snapshot.Values)) {
      $key.SetValue("$($entry.Name)", $entry.Value, $entry.Kind)
    }
  } finally {
    $key.Dispose()
  }
}

function Invoke-IsolatedPackageSmokeTest {
  param([Parameter(Mandatory = $true)][string]$SourceScripts)

  $smokeRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
    ('codex-kiana-pet-smoke-' + [guid]::NewGuid().ToString('N'))
  $smokeCodexHome = Join-Path $smokeRoot '中文用户\.codex'
  $smokeLauncher = Join-Path $smokeRoot 'launcher'
  $smokeDesktop = Join-Path $smokeRoot 'desktop'
  $smokeStartMenu = Join-Path $smokeRoot 'start-menu'
  $iconSource = Join-Path $PSHOME 'powershell.exe'
  try {
    New-Item -ItemType Directory -Force -Path $smokeRoot | Out-Null
    & (Join-Path $SourceScripts 'install-time-runner-pet.ps1') -CodexHome $smokeCodexHome *> $null
    $installedManifest = Join-Path $smokeCodexHome 'pets\time-runner-kiana\pet.json'
    $installedDefinition = Read-Utf8JsonFile -Path $installedManifest
    if ($installedDefinition.displayName -cne '时砾逐光') {
      throw '隔离安装后的桌宠清单发生了编码损坏。'
    }

    & (Join-Path $SourceScripts 'start-pet-enhancer.ps1') -SelfTest *> $null

    $shortcutScript = Join-Path $SourceScripts 'new-pet-enhancer-shortcuts.ps1'
    for ($attempt = 1; $attempt -le 2; $attempt++) {
      $launcher = @(& $shortcutScript -OutputRoot $smokeLauncher `
          -DesktopFolder $smokeDesktop -StartMenuFolder $smokeStartMenu `
          -IconSourcePath $iconSource) | Select-Object -Last 1
      if (-not $launcher -or -not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw "第 $attempt 次启动器构建失败。"
      }
    }

    $desktopShortcut = Join-Path $smokeDesktop 'Codex 琪亚娜桌宠.lnk'
    $startMenuShortcut = Join-Path $smokeStartMenu 'Codex 琪亚娜桌宠.lnk'
    if (-not (Test-Path -LiteralPath $desktopShortcut -PathType Leaf) -or
      -not (Test-Path -LiteralPath $startMenuShortcut -PathType Leaf)) {
      throw '隔离测试未生成桌面和开始菜单快捷方式。'
    }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($shortcutPath in @($desktopShortcut, $startMenuShortcut)) {
      $resolvedShortcut = $shell.CreateShortcut($shortcutPath)
      if ([System.IO.Path]::GetFullPath($resolvedShortcut.TargetPath) -ine
        [System.IO.Path]::GetFullPath($launcher)) {
        throw '隔离测试生成的快捷方式没有指向增强桌宠启动器。'
      }
      if ($resolvedShortcut.Arguments -match '(?i)(?:^|\s)--port(?:=|\s)') {
        throw '隔离测试生成的默认启动快捷方式不应固定 CDP 端口。'
      }
    }
    $uninstallShortcut = $shell.CreateShortcut(
      (Join-Path $smokeDesktop '卸载 Codex 琪亚娜桌宠.lnk')
    )
    if ($uninstallShortcut.Arguments -match '(?i)(?:^|\s)-Port(?:=|\s)') {
      throw '隔离测试生成的默认卸载快捷方式不应固定 CDP 端口。'
    }
  } finally {
    if (Test-Path -LiteralPath $smokeRoot) {
      [System.IO.Directory]::Delete($smokeRoot, $true)
    }
  }
}

try {
  Write-Host '正在校验安装包……'
  $manifest = Assert-PackageIntegrity
  $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
  if ($manifest.architecture -eq 'x64' -and
    (-not [Environment]::Is64BitOperatingSystem -or $architecture -ne 'AMD64')) {
    throw "此安装包仅支持 Windows x64；当前系统架构为 $architecture。"
  }
  if ($VerifyOnly -and -not $SmokeTest) {
    Write-Host "安装包校验通过：v$($manifest.version)，$(@($manifest.files).Count) 个文件。" -ForegroundColor Green
    return
  }

  $sourceScripts = Join-Path $payloadRoot 'scripts'
  . (Join-Path $sourceScripts 'pet-common.ps1')
  $commonLoaded = $true
  $node = Get-DreamSkinNodeRuntime
  if (-not (Test-PathInside -Path $node.Path -Root $payloadRoot)) {
    throw '安装包没有使用其内置运行环境，已停止安装。'
  }
  if ($SmokeTest) {
    Invoke-IsolatedPackageSmokeTest -SourceScripts $sourceScripts
    Write-Host "安装包隔离烟测通过：v$($manifest.version)，UTF-8、内置 Node、桌宠安装、启动器覆盖和快捷方式均正常。" `
      -ForegroundColor Green
    return
  }
  $operationLock = Enter-DreamSkinOperationLock
  $registered = @(Get-DreamSkinRegisteredCodexInstalls)
  if ($registered.Count -eq 0) {
    throw '未找到微软商店安装的官方 Codex。请先安装并至少启动一次 Codex。'
  }
  if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin\state.json')) {
    throw '检测到“时砾逐光完整主题版”仍在运行。请先用它的恢复/卸载入口关闭主题，再安装纯桌宠版。'
  }
  $running = @($registered | ForEach-Object { Get-DreamSkinCodexProcesses -Codex $_ })
  $codexWasRunning = $running.Count -gt 0
  if ($codexWasRunning -and -not $ForceRestart) {
    throw 'Codex 正在运行。请先完全退出所有 Codex 窗口，再重新运行安装器；安装器不会自动关闭应用。'
  }

  $existingRestore = Join-Path $installRoot 'scripts\restore-pet-enhancer.ps1'
  $existingStatePath = Join-Path $stateRoot 'state.json'
  if (Test-Path -LiteralPath $existingStatePath) {
    if (Test-Path -LiteralPath $existingRestore -PathType Leaf) {
      & $existingRestore -NoRelaunch -ForceRestart
    } else {
      $archivedState = Archive-DreamSkinInactiveRuntimeState -Path $existingStatePath
      Write-Warning "已归档失效的旧桌宠运行状态：$archivedState"
    }
  }
  if ($codexWasRunning) {
    foreach ($codex in $registered) {
      if ((Get-DreamSkinCodexProcesses -Codex $codex).Count -gt 0) {
        Stop-DreamSkinCodex -Codex $codex -AllowForce
      }
    }
  }

  New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
  if (Test-Path -LiteralPath $installationPath -PathType Leaf) {
    try {
      $candidateInstallation = Read-Utf8JsonFile -Path $installationPath
      $candidateInstallRoot = [System.IO.Path]::GetFullPath("$($candidateInstallation.installRoot)")
      if ([int]$candidateInstallation.schemaVersion -eq 1 -and
        (Test-PathInside -Path $candidateInstallRoot -Root $stateRoot) -and
        $candidateInstallRoot -ieq [System.IO.Path]::GetFullPath($installRoot) -and
        (Test-Path -LiteralPath $installRoot -PathType Container)) {
        $oldInstallation = $candidateInstallation
        $previousInstallationBytes = [System.IO.File]::ReadAllBytes($installationPath)
        if (Test-Path -LiteralPath $uninstallerPath -PathType Leaf) {
          $previousUninstallerBytes = [System.IO.File]::ReadAllBytes($uninstallerPath)
        }
      } else {
        throw 'stale installation record'
      }
    } catch {
      $staleInstallationPath = Join-Path $stateRoot "installation.stale-$stamp.json"
      Move-Item -LiteralPath $installationPath -Destination $staleInstallationPath
      $oldInstallation = $null
      Write-Warning "已归档无效的旧安装记录：$staleInstallationPath"
    }
  }

  $publicShortcutPaths = @(
    foreach ($folder in @([Environment]::GetFolderPath('Desktop'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'))) {
      foreach ($name in @('Codex 琪亚娜桌宠.lnk', '卸载 Codex 琪亚娜桌宠.lnk')) {
        Join-Path $folder $name
      }
    }
  )
  $shortcutSnapshots = @(
    foreach ($path in $publicShortcutPaths) {
      $existed = Test-Path -LiteralPath $path -PathType Leaf
      [pscustomobject]@{
        Path = $path
        Existed = $existed
        Bytes = if ($existed) { [System.IO.File]::ReadAllBytes($path) } else { $null }
      }
    }
  )
  $uninstallRegistrationSnapshot = Get-UninstallRegistrationSnapshot
  if (Test-Path -LiteralPath $launcherRoot -PathType Container) {
    $launcherRollbackBackup = Join-Path $stateRoot "launcher.transaction-$stamp"
    Copy-Item -LiteralPath $launcherRoot -Destination $launcherRollbackBackup -Recurse -Force
  }
  $publicArtifactsCaptured = $true

  $stagingRoot = Join-Path $stateRoot "app.staging-$stamp"
  New-Item -ItemType Directory -Path $stagingRoot | Out-Null
  Get-ChildItem -LiteralPath $payloadRoot -Force | Copy-Item -Destination $stagingRoot -Recurse -Force
  Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $stagingRoot 'release-manifest.json') -Force
  if (Test-Path -LiteralPath $installRoot) {
    $previousApp = Join-Path $stateRoot "app.previous-$stamp"
    Move-Item -LiteralPath $installRoot -Destination $previousApp
  }
  Move-Item -LiteralPath $stagingRoot -Destination $installRoot

  $installedScripts = Join-Path $installRoot 'scripts'
  $petManifest = Join-Path $installRoot 'assets\pets\time-runner-kiana\pet.json'
  $petSprite = Join-Path $installRoot 'assets\pets\time-runner-kiana\spritesheet.webp'
  $petDefinition = Read-Utf8JsonFile -Path $petManifest
  $codexHome = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
    Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
  } else { $env:CODEX_HOME }
  $petRoot = Join-Path $codexHome 'pets'
  $petDestination = Join-Path $petRoot "$($petDefinition.id)"
  $petExistedBeforeTransaction = Test-Path -LiteralPath $petDestination -PathType Container
  if ($petExistedBeforeTransaction) {
    $petRollbackBackup = Join-Path $stateRoot "pet-transaction-$stamp"
    Copy-Item -LiteralPath $petDestination -Destination $petRollbackBackup -Recurse -Force
  }

  $oldOriginalBackup = if ($null -ne $oldInstallation -and $null -ne $oldInstallation.pet) {
    "$($oldInstallation.pet.backupPath)"
  } else { '' }
  $hasOriginalBackup = $null -ne $oldInstallation -and [bool]$oldInstallation.pet.existedBefore -and
    -not [string]::IsNullOrWhiteSpace($oldOriginalBackup) -and
    (Test-Path -LiteralPath $oldOriginalBackup -PathType Container) -and
    (Test-PathInside -Path $oldOriginalBackup -Root $stateRoot)
  if ($null -ne $oldInstallation -and [bool]$oldInstallation.pet.existedBefore -and -not $hasOriginalBackup) {
    $oldInstallation = $null
  }
  $originalBackup = if ($hasOriginalBackup) { $oldOriginalBackup } elseif ($null -ne $oldInstallation) { $null } else { $petRollbackBackup }
  $originalExisted = if ($null -ne $oldInstallation) { [bool]$oldInstallation.pet.existedBefore } else { $petExistedBeforeTransaction }

  $installedPet = $true
  & (Join-Path $installedScripts 'install-time-runner-pet.ps1') -CodexHome $codexHome

  $installation = [ordered]@{
    schemaVersion = 1
    version = "$($manifest.version)"
    installedAt = [DateTimeOffset]::Now.ToString('O')
    installRoot = $installRoot
    pet = [ordered]@{
      destination = $petDestination
      existedBefore = $originalExisted
      backupPath = $originalBackup
      manifestSha256 = (Get-FileHash -LiteralPath $petManifest -Algorithm SHA256).Hash
      spritesheetSha256 = (Get-FileHash -LiteralPath $petSprite -Algorithm SHA256).Hash
    }
  }
  Write-Utf8NoBom -Path $installationPath -Text ($installation | ConvertTo-Json -Depth 6)

  if ($LaunchAfterInstall) {
    Write-Host '正在启动 Codex 并验证桌宠增强……'
    & (Join-Path $installedScripts 'start-pet-enhancer.ps1')
  }

  $publicArtifactsTouched = $true
  & (Join-Path $installedScripts 'new-pet-enhancer-shortcuts.ps1') | Out-Null
  Copy-Item -LiteralPath (Join-Path $packageRoot 'uninstall-pet-enhancer-release.ps1') -Destination $uninstallerPath -Force
  New-UninstallShortcuts
  $launcherPath = Join-Path $launcherRoot 'Codex 琪亚娜桌宠.exe'
  Set-UninstallRegistration -LauncherPath $launcherPath

  if ($previousApp -and (Test-Path -LiteralPath $previousApp)) {
    Remove-DirectorySafe -Path $previousApp -AllowedRoot $stateRoot
  }
  if ($petRollbackBackup -and $null -ne $oldInstallation -and (Test-Path -LiteralPath $petRollbackBackup)) {
    Remove-DirectorySafe -Path $petRollbackBackup -AllowedRoot $stateRoot
  }
  if ($launcherRollbackBackup -and (Test-Path -LiteralPath $launcherRollbackBackup)) {
    Remove-DirectorySafe -Path $launcherRollbackBackup -AllowedRoot $stateRoot
  }
  Write-Host ''
  if (-not $LaunchAfterInstall) {
    Write-Host '安装文件已写入，但未自动修改 Codex 的桌宠选择。' -ForegroundColor Green
    Write-Host '1. 先正常打开官方 Codex，在“设置 > Pets”中刷新自定义桌宠并选择“时砾逐光”。'
    Write-Host '2. 完全退出 Codex。'
    Write-Host '3. 以后使用桌面或开始菜单中的“Codex 琪亚娜桌宠”启动。'
  } else {
    Write-Host '安装完成：以后使用“Codex 琪亚娜桌宠”启动。' -ForegroundColor Green
  }
} catch {
  $failure = $_
  Write-Warning '安装失败，正在回滚……'

  if ($installedScripts -and
    (Test-Path -LiteralPath (Join-Path $stateRoot 'state.json') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $installedScripts 'restore-pet-enhancer.ps1') -PathType Leaf)) {
    try {
      & (Join-Path $installedScripts 'restore-pet-enhancer.ps1') -NoRelaunch -ForceRestart
    } catch { Write-Warning "运行状态回滚失败：$($_.Exception.Message)" }
  }

  if ($publicArtifactsCaptured) {
    if ($publicArtifactsTouched) {
      try {
        Restore-UninstallRegistrationSnapshot -Snapshot $uninstallRegistrationSnapshot
      } catch { Write-Warning "卸载注册回滚失败：$($_.Exception.Message)" }
      foreach ($snapshot in $shortcutSnapshots) {
        try {
          if ([bool]$snapshot.Existed) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent "$($snapshot.Path)") | Out-Null
            [System.IO.File]::WriteAllBytes("$($snapshot.Path)", [byte[]]$snapshot.Bytes)
          } else {
            Remove-Item -LiteralPath "$($snapshot.Path)" -Force -ErrorAction SilentlyContinue
          }
        } catch { Write-Warning "快捷方式回滚失败（$($snapshot.Path)）：$($_.Exception.Message)" }
      }
      try {
        if (Test-Path -LiteralPath $launcherRoot) {
          Remove-DirectorySafe -Path $launcherRoot -AllowedRoot $stateRoot
        }
        if ($launcherRollbackBackup -and (Test-Path -LiteralPath $launcherRollbackBackup)) {
          Move-Item -LiteralPath $launcherRollbackBackup -Destination $launcherRoot
        }
      } catch { Write-Warning "启动器回滚失败：$($_.Exception.Message)" }
    } elseif ($launcherRollbackBackup -and (Test-Path -LiteralPath $launcherRollbackBackup)) {
      try {
        Remove-DirectorySafe -Path $launcherRollbackBackup -AllowedRoot $stateRoot
      } catch { Write-Warning "启动器事务备份清理失败：$($_.Exception.Message)" }
    }
  }
  try {
    if ($installedPet -and $petDestination) {
      if (Test-Path -LiteralPath $petDestination) { Remove-DirectorySafe -Path $petDestination -AllowedRoot (Split-Path -Parent $petDestination) }
      if ($petRollbackBackup -and (Test-Path -LiteralPath $petRollbackBackup)) {
        Copy-Item -LiteralPath $petRollbackBackup -Destination $petDestination -Recurse -Force
        Remove-DirectorySafe -Path $petRollbackBackup -AllowedRoot $stateRoot
      }
    }
  } catch { Write-Warning "桌宠回滚失败：$($_.Exception.Message)" }
  try {
    if (Test-Path -LiteralPath $installRoot) { Remove-DirectorySafe -Path $installRoot -AllowedRoot $stateRoot }
    if ($previousApp -and (Test-Path -LiteralPath $previousApp)) { Move-Item -LiteralPath $previousApp -Destination $installRoot }
    if ($stagingRoot -and (Test-Path -LiteralPath $stagingRoot)) { Remove-DirectorySafe -Path $stagingRoot -AllowedRoot $stateRoot }
  } catch { Write-Warning "程序文件回滚失败：$($_.Exception.Message)" }
  try {
    if ($null -ne $previousInstallationBytes) {
      [System.IO.File]::WriteAllBytes($installationPath, $previousInstallationBytes)
    } else {
      Remove-Item -LiteralPath $installationPath -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $previousUninstallerBytes) {
      [System.IO.File]::WriteAllBytes($uninstallerPath, $previousUninstallerBytes)
    } else {
      Remove-Item -LiteralPath $uninstallerPath -Force -ErrorAction SilentlyContinue
    }
  } catch { Write-Warning "安装记录回滚失败：$($_.Exception.Message)" }
  if ($commonLoaded -and $codexWasRunning) {
    try {
      $reopen = Get-DreamSkinCodexInstall
      if ((Get-DreamSkinCodexProcesses -Codex $reopen).Count -eq 0) { Start-DreamSkinCodex -Codex $reopen }
    } catch { Write-Warning '安装失败后无法自动重新打开 Codex。' }
  }
  throw $failure
} finally {
  if ($null -ne $operationLock) { Exit-DreamSkinOperationLock -Mutex $operationLock }
}
