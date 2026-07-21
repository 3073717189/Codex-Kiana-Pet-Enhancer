[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Scripts = Join-Path $Root 'scripts'
$PowerShell51 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$TemporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) `
  ("codex-kiana-pet-tests-$PID-" + [guid]::NewGuid().ToString('N'))
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-StrictUtf8 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, $strictUtf8)
}

function Assert-LastExitCode {
  param([Parameter(Mandatory = $true)][string]$Message)
  if ($LASTEXITCODE -ne 0) { throw "$Message (exit code $LASTEXITCODE)" }
}

try {
  New-Item -ItemType Directory -Force -Path $TemporaryRoot | Out-Null

  $requiredFiles = @(
    'assets\pet-enhancer.js',
    'assets\pets\time-runner-kiana\pet.json',
    'assets\pets\time-runner-kiana\spritesheet.webp',
    'assets\pets\time-runner-kiana\README.md',
    'assets\pets\time-runner-kiana\LICENSE',
    'scripts\pet-common.ps1',
    'scripts\pet-injector.mjs',
    'scripts\build-native-pet-package.ps1',
    'scripts\start-pet-enhancer.ps1',
    'scripts\restore-pet-enhancer.ps1',
    'scripts\verify-pet-enhancer.ps1'
  )
  foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
      throw "Required pure-pet file is missing: $relativePath"
    }
  }

  foreach ($relativePath in @(
      'scripts\common-windows.ps1',
      'scripts\config-utf8.ps1',
      'scripts\injector.mjs',
      'scripts\start-dream-skin.ps1',
      'scripts\restore-dream-skin.ps1',
      'scripts\verify-dream-skin.ps1'
    )) {
    if (Test-Path -LiteralPath (Join-Path $Root $relativePath)) {
      throw "Legacy full-theme lifecycle file is still present: $relativePath"
    }
  }

  $parseErrors = @()
  foreach ($scriptPath in @(Get-ChildItem -LiteralPath $Scripts -Filter '*.ps1' -File)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
      $scriptPath.FullName,
      [ref]$tokens,
      [ref]$errors
    )
    foreach ($error in @($errors)) {
      $parseErrors += "$($scriptPath.Name): $($error.Message)"
    }
  }
  if ($parseErrors.Count -gt 0) {
    throw "PowerShell parse errors:`r`n$($parseErrors -join "`r`n")"
  }

  $commonSource = Read-StrictUtf8 -Path (Join-Path $Scripts 'pet-common.ps1')
  if ($commonSource.Contains('config-utf8.ps1') -or
    $commonSource.Contains('Install-DreamSkinBaseTheme') -or
    $commonSource.Contains('Restore-DreamSkinBaseTheme') -or
    $commonSource.Contains('appearanceTheme')) {
    throw 'pet-common.ps1 still contains theme/TOML configuration logic.'
  }

  $injectorSource = Read-StrictUtf8 -Path (Join-Path $Scripts 'pet-injector.mjs')
  foreach ($forbidden in @(
      '--pet-only',
      'dream-skin.css',
      'renderer-inject.js',
      'time-runner-background',
      'time-runner-character',
      'time-runner-icons',
      '__CODEX_DREAM_SKIN_STATE__'
    )) {
    if ($injectorSource.Contains($forbidden)) {
      throw "pet-injector.mjs still contains a full-theme branch marker: $forbidden"
    }
  }

  foreach ($fileName in @(
      'start-pet-enhancer.ps1',
      'restore-pet-enhancer.ps1',
      'verify-pet-enhancer.ps1'
    )) {
    $source = Read-StrictUtf8 -Path (Join-Path $Scripts $fileName)
    if (-not $source.Contains('pet-common.ps1') -or
      $source.Contains('common-windows.ps1') -or
      $source.Contains('config.toml') -or
      $source.Contains('$PetOnly')) {
      throw "$fileName is not an independent pure-pet lifecycle script."
    }
  }

  . (Join-Path $Scripts 'pet-common.ps1')
  $statePath = Join-Path $TemporaryRoot 'state\state.json'
  $state = [pscustomobject]@{
    schemaVersion = 3
    platform = 'windows'
    product = 'pet-enhancer'
    port = 9345
    injectorPid = 1234
    injectorStartedAt = '2026-01-01T00:00:00.0000000Z'
    injectorPath = 'C:\Pet\pet-injector.mjs'
    nodePath = 'C:\Pet\node.exe'
    codexExe = 'C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe'
    codexPackageRoot = 'C:\Program Files\WindowsApps\OpenAI.Codex'
    codexPackageFullName = 'OpenAI.Codex_1.0.0.0_x64__test'
    codexPackageFamilyName = 'OpenAI.Codex_test'
    browserId = 'browser-test'
  }
  Write-DreamSkinState -Path $statePath -State $state
  $readState = Read-DreamSkinState -Path $statePath
  if ($null -eq $readState -or $readState.product -ne 'pet-enhancer' -or [int]$readState.port -ne 9345) {
    throw 'Pure-pet state round-trip failed.'
  }
  $state.port = 9346
  Write-DreamSkinState -Path $statePath -State $state
  $readState = Read-DreamSkinState -Path $statePath
  if ([int]$readState.port -ne 9346) { throw 'Atomic state replacement failed.' }
  if (@(Get-ChildItem -LiteralPath (Split-Path -Parent $statePath) -Filter '.state.json.*' -File).Count -ne 0) {
    throw 'Atomic state replacement left temporary or backup files behind.'
  }

  $preferredPort = $null
  foreach ($candidate in 45000..64000) {
    if ((Test-DreamSkinPortAvailable -Port $candidate) -and
      (Test-DreamSkinPortAvailable -Port ($candidate + 1))) {
      $preferredPort = $candidate
      break
    }
  }
  if ($null -eq $preferredPort) { throw 'Could not find consecutive ports for fallback testing.' }
  $occupiedPort = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $preferredPort)
  $occupiedPort.Start()
  try {
    if (Test-DreamSkinPortAvailable -Port $preferredPort) {
      throw 'Occupied loopback port was incorrectly reported as available.'
    }
    $selectedPort = Select-DreamSkinPort -PreferredPort $preferredPort
    if ($selectedPort -ne ($preferredPort + 1)) {
      throw "Port fallback selected $selectedPort instead of $($preferredPort + 1)."
    }
  } finally {
    $occupiedPort.Stop()
  }

  $node = Get-DreamSkinNodeRuntime
  & $node.Path --check (Join-Path $Scripts 'pet-injector.mjs')
  Assert-LastExitCode -Message 'pet-injector.mjs syntax validation failed.'
  & $node.Path --check (Join-Path $Root 'assets\pet-enhancer.js')
  Assert-LastExitCode -Message 'pet-enhancer.js syntax validation failed.'
  & $node.Path (Join-Path $Scripts 'pet-injector.mjs') --self-test
  Assert-LastExitCode -Message 'Loopback CDP validation self-test failed.'
  & $node.Path (Join-Path $Scripts 'pet-injector.mjs') --check-payload
  Assert-LastExitCode -Message 'Pure-pet payload validation failed.'
  $savedErrorActionPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $node.Path (Join-Path $Scripts 'pet-injector.mjs') --check-payload --pet-only *> $null
    $legacyModeExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $savedErrorActionPreference
  }
  if ($legacyModeExitCode -eq 0) { throw 'Legacy --pet-only mode was unexpectedly accepted.' }
  & $node.Path (Join-Path $PSScriptRoot 'pet-enhancer.test.mjs')
  Assert-LastExitCode -Message 'Pet renderer regression test failed.'

  $unicodePathSegment = -join @([char]0x4E2D, [char]0x6587, [char]0x7528, [char]0x6237)
  $petHome = Join-Path $TemporaryRoot "$unicodePathSegment\.codex"
  & $PowerShell51 -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $Scripts 'install-time-runner-pet.ps1') -CodexHome $petHome *> $null
  Assert-LastExitCode -Message 'Windows PowerShell 5.1 pet installation failed.'
  $installedPet = [System.IO.File]::ReadAllText(
    (Join-Path $petHome 'pets\time-runner-kiana\pet.json'),
    $strictUtf8
  ) | ConvertFrom-Json -ErrorAction Stop
  $expectedDisplayName = -join @([char]0x65F6, [char]0x783E, [char]0x9010, [char]0x5149)
  if ($installedPet.displayName -cne $expectedDisplayName -or [int]$installedPet.spriteVersionNumber -ne 2) {
    throw 'Installed pet manifest was corrupted or is not v2.'
  }
  foreach ($installedDocument in @('README.md', 'LICENSE')) {
    if (-not (Test-Path -LiteralPath (Join-Path $petHome "pets\time-runner-kiana\$installedDocument") -PathType Leaf)) {
      throw "Installed native pet is missing $installedDocument."
    }
  }

  $nativeRelease = Join-Path $TemporaryRoot 'native-release'
  $nativeArchive = @(
    & $PowerShell51 -NoLogo -NoProfile -ExecutionPolicy Bypass `
      -File (Join-Path $Scripts 'build-native-pet-package.ps1') `
      -OutputDirectory $nativeRelease
  ) | Select-Object -Last 1
  Assert-LastExitCode -Message 'Native CodexPet package build failed.'
  if (-not (Test-Path -LiteralPath $nativeArchive -PathType Leaf)) {
    throw 'Native CodexPet package was not created.'
  }

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $nativeZip = [System.IO.Compression.ZipFile]::OpenRead($nativeArchive)
  try {
    $nativeEntries = @($nativeZip.Entries | ForEach-Object { $_.FullName })
  } finally {
    $nativeZip.Dispose()
  }
  if ($nativeEntries.Count -ne 4 -or
    $nativeEntries -notcontains 'pet.json' -or
    $nativeEntries -notcontains 'spritesheet.webp' -or
    $nativeEntries -notcontains 'README.md' -or
    $nativeEntries -notcontains 'LICENSE') {
    throw "Native CodexPet package contains unexpected entries: $($nativeEntries -join ', ')"
  }

  & $PowerShell51 -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $Scripts 'start-pet-enhancer.ps1') -SelfTest *> $null
  Assert-LastExitCode -Message 'Windows PowerShell 5.1 lifecycle self-test failed.'

  $launcherRoot = Join-Path $TemporaryRoot 'launcher'
  $desktop = Join-Path $TemporaryRoot 'desktop'
  $startMenu = Join-Path $TemporaryRoot 'start-menu'
  for ($attempt = 1; $attempt -le 2; $attempt++) {
    & $PowerShell51 -NoLogo -NoProfile -ExecutionPolicy Bypass `
      -File (Join-Path $Scripts 'new-pet-enhancer-shortcuts.ps1') `
      -OutputRoot $launcherRoot -DesktopFolder $desktop -StartMenuFolder $startMenu `
      -IconSourcePath $PowerShell51 *> $null
    Assert-LastExitCode -Message "Launcher/shortcut smoke test attempt $attempt failed."
  }
  $launcherBaseName = 'Codex ' + (-join @(
      [char]0x742A, [char]0x4E9A, [char]0x5A1C, [char]0x684C, [char]0x5BA0
    ))
  $launcherPath = Join-Path $launcherRoot "$launcherBaseName.exe"
  $shortcutPath = Join-Path $desktop "$launcherBaseName.lnk"
  if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
    throw 'Launcher/shortcut smoke test did not create the expected files.'
  }
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  if ([System.IO.Path]::GetFullPath($shortcut.TargetPath) -ine
    [System.IO.Path]::GetFullPath($launcherPath)) {
    throw 'Generated shortcut points to the wrong launcher.'
  }
  if ($shortcut.Arguments -match '(?i)(?:^|\s)--port(?:=|\s)') {
    throw 'Default launcher shortcut unexpectedly pins a CDP port.'
  }
  $uninstallShortcutPath = @(
    Get-ChildItem -LiteralPath $desktop -Filter '*.lnk' -File |
      Where-Object { $_.FullName -ine $shortcutPath } |
      Select-Object -ExpandProperty FullName
  )
  if ($uninstallShortcutPath.Count -ne 1) {
    throw 'Default shortcut set did not contain exactly one uninstall shortcut.'
  }
  $uninstallShortcut = $shell.CreateShortcut([string]$uninstallShortcutPath)
  if ($uninstallShortcut.Arguments -match '(?i)(?:^|\s)-Port(?:=|\s)') {
    throw 'Default uninstall shortcut unexpectedly pins a CDP port.'
  }

  $pinnedDesktop = Join-Path $TemporaryRoot 'desktop-pinned-port'
  $pinnedStartMenu = Join-Path $TemporaryRoot 'start-menu-pinned-port'
  & $PowerShell51 -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $Scripts 'new-pet-enhancer-shortcuts.ps1') `
    -Port 9456 -OutputRoot $launcherRoot -DesktopFolder $pinnedDesktop `
    -StartMenuFolder $pinnedStartMenu -IconSourcePath $PowerShell51 *> $null
  Assert-LastExitCode -Message 'Explicit-port shortcut smoke test failed.'
  $pinnedShortcutPath = Join-Path $pinnedDesktop ($launcherBaseName + '.lnk')
  $pinnedShortcut = $shell.CreateShortcut([string]$pinnedShortcutPath)
  if ($pinnedShortcut.Arguments -notmatch '(?i)(?:^|\s)--port\s+9456(?:$|\s)') {
    throw 'Explicit launcher port was not preserved.'
  }
  $pinnedUninstallPath = @(
    Get-ChildItem -LiteralPath $pinnedDesktop -Filter '*.lnk' -File |
      Where-Object { $_.FullName -ine $pinnedShortcutPath } |
      Select-Object -ExpandProperty FullName
  )
  if ($pinnedUninstallPath.Count -ne 1) {
    throw 'Explicit-port shortcut set did not contain exactly one uninstall shortcut.'
  }
  $pinnedUninstall = $shell.CreateShortcut([string]$pinnedUninstallPath)
  if ($pinnedUninstall.Arguments -notmatch '(?i)(?:^|\s)-Port\s+9456(?:$|\s)') {
    throw 'Explicit uninstall port was not preserved.'
  }

  Write-Host 'PASS: pure-pet lifecycle, state safety, payload, animation, UTF-8 install, and launcher tests.'
} finally {
  if (Test-Path -LiteralPath $TemporaryRoot) {
    [System.IO.Directory]::Delete($TemporaryRoot, $true)
  }
}
