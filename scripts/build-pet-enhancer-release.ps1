[CmdletBinding()]
param(
  [string]$NodeVersion = '22.23.1',
  [ValidateSet('x64')][string]$Architecture = 'x64',
  [string]$OutputDirectory,
  [switch]$SkipTests,
  [string]$NodeArchivePath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$windowsRoot = Split-Path -Parent $PSScriptRoot
$OutputDirectory = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  Join-Path $windowsRoot 'release'
} else { [System.IO.Path]::GetFullPath($OutputDirectory) }
$version = (Get-Content -LiteralPath (Join-Path $windowsRoot 'PET_ENHANCER_VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid Pet Enhancer version: $version" }
if ($NodeVersion -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid Node.js version: $NodeVersion" }

$runtimeVersionSources = [ordered]@{
  'assets\pet-enhancer.js' = 'const VERSION = "(?<version>\d+\.\d+\.\d+)";'
  'scripts\pet-injector.mjs' = 'const PET_ENHANCER_VERSION = "(?<version>\d+\.\d+\.\d+)";'
}
foreach ($relativePath in $runtimeVersionSources.Keys) {
  $sourcePath = Join-Path $windowsRoot $relativePath
  $sourceText = Get-Content -LiteralPath $sourcePath -Raw
  if ($sourceText -notmatch $runtimeVersionSources[$relativePath]) {
    throw "Runtime version declaration was not found: $relativePath"
  }
  if ($matches.version -ne $version) {
    throw "Runtime version mismatch in ${relativePath}: $($matches.version) != $version"
  }
}

if (-not $SkipTests) {
  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $windowsRoot 'tests\run-tests.ps1')
  if ($LASTEXITCODE -ne 0) { throw 'Windows PowerShell 5.1 regression tests failed.' }
  & node --check (Join-Path $windowsRoot 'scripts\pet-injector.mjs')
  if ($LASTEXITCODE -ne 0) { throw 'pet-injector.mjs syntax validation failed.' }
  & node --check (Join-Path $windowsRoot 'assets\pet-enhancer.js')
  if ($LASTEXITCODE -ne 0) { throw 'pet-enhancer.js syntax validation failed.' }
  & node (Join-Path $windowsRoot 'tests\pet-enhancer.test.mjs')
  if ($LASTEXITCODE -ne 0) { throw 'Pet Enhancer regression tests failed.' }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-kiana-pet-release-" + [guid]::NewGuid().ToString('N'))
$packageName = "Codex-Kiana-Pet-Enhancer-v$version-win-$Architecture"
$clientRoot = Join-Path $tempRoot $packageName
$payloadRoot = Join-Path $clientRoot 'payload'
$downloadRoot = Join-Path $tempRoot 'node-download'
New-Item -ItemType Directory -Force -Path $payloadRoot, $downloadRoot, $OutputDirectory | Out-Null

function Write-Utf8NoBom {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
  [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Copy-PayloadFile {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [string]$DestinationRelativePath
  )
  if ([string]::IsNullOrWhiteSpace($DestinationRelativePath)) {
    $DestinationRelativePath = $RelativePath
  }
  $source = Join-Path $windowsRoot $RelativePath
  if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "Release source is missing: $RelativePath" }
  $destination = Join-Path $payloadRoot $DestinationRelativePath
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
  Copy-Item -LiteralPath $source -Destination $destination -Force
}

try {
  $payloadFiles = @(
    'assets\pet-enhancer.js',
    'assets\pets\time-runner-kiana\pet.json',
    'assets\pets\time-runner-kiana\spritesheet.webp',
    'launcher\PetEnhancerLauncher.cs',
    'scripts\build-pet-enhancer-launcher.ps1',
    'scripts\install-time-runner-pet.ps1',
    'scripts\new-pet-enhancer-shortcuts.ps1',
    'scripts\pet-common.ps1',
    'scripts\pet-injector.mjs',
    'scripts\restore-pet-enhancer.ps1',
    'scripts\start-pet-enhancer.ps1',
    'scripts\verify-pet-enhancer.ps1'
  )
  foreach ($file in $payloadFiles) { Copy-PayloadFile -RelativePath $file }

  $payloadLicenseFiles = [ordered]@{
    'LICENSE' = 'licenses\LICENSE'
    'THIRD_PARTY_NOTICES.md' = 'licenses\THIRD_PARTY_NOTICES.md'
    'ASSETS.md' = 'licenses\ASSETS.md'
    'SECURITY.md' = 'licenses\SECURITY.md'
    'licenses\Codex-Dream-Skin-MIT.txt' = 'licenses\Codex-Dream-Skin-MIT.txt'
  }
  foreach ($source in $payloadLicenseFiles.Keys) {
    Copy-PayloadFile -RelativePath $source -DestinationRelativePath $payloadLicenseFiles[$source]
  }

  $archiveName = "node-v$NodeVersion-win-$Architecture.zip"
  $archive = if ([string]::IsNullOrWhiteSpace($NodeArchivePath)) {
    Join-Path $downloadRoot $archiveName
  } else { [System.IO.Path]::GetFullPath($NodeArchivePath) }
  $baseUrl = "https://nodejs.org/download/release/v$NodeVersion"
  $checksumsPath = Join-Path $downloadRoot 'SHASUMS256.txt'
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  if ([string]::IsNullOrWhiteSpace($NodeArchivePath)) {
    Write-Host "Downloading official Node.js v$NodeVersion $Architecture runtime..."
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$archiveName" -OutFile $archive
  } elseif (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    throw "Node archive not found: $archive"
  }
  Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/SHASUMS256.txt" -OutFile $checksumsPath
  $checksumLine = Get-Content -LiteralPath $checksumsPath | Where-Object {
    $_ -match "\s+$([regex]::Escape($archiveName))$"
  } | Select-Object -First 1
  if (-not $checksumLine -or $checksumLine -notmatch '^([0-9a-fA-F]{64})\s+') {
    throw "The official checksum for $archiveName was not found."
  }
  $expectedHash = $matches[1]
  $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
  if ($actualHash -ine $expectedHash) { throw "Node.js archive checksum mismatch for $archiveName." }

  $expandedNode = Join-Path $downloadRoot 'expanded'
  Expand-Archive -LiteralPath $archive -DestinationPath $expandedNode -Force
  $nodeRoot = Join-Path $expandedNode "node-v$NodeVersion-win-$Architecture"
  $runtimeRoot = Join-Path $payloadRoot 'runtime'
  New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
  Copy-Item -LiteralPath (Join-Path $nodeRoot 'node.exe') -Destination (Join-Path $runtimeRoot 'node.exe') -Force
  Copy-Item -LiteralPath (Join-Path $nodeRoot 'LICENSE') -Destination (Join-Path $runtimeRoot 'LICENSE.txt') -Force

  foreach ($clientFile in @(
      'install-pet-enhancer-release.ps1',
      'uninstall-pet-enhancer-release.ps1',
      '安装 Codex 琪亚娜增强桌宠.cmd',
      '卸载 Codex 琪亚娜增强桌宠.cmd',
      '使用说明.txt'
    )) {
    Copy-Item -LiteralPath (Join-Path $windowsRoot "pet-enhancer-delivery\$clientFile") `
      -Destination (Join-Path $clientRoot $clientFile) -Force
  }
  foreach ($noticeFile in @('LICENSE', 'THIRD_PARTY_NOTICES.md', 'ASSETS.md', 'SECURITY.md')) {
    Copy-Item -LiteralPath (Join-Path $windowsRoot $noticeFile) -Destination (Join-Path $clientRoot $noticeFile) -Force
  }
  $clientLicensesRoot = Join-Path $clientRoot 'licenses'
  New-Item -ItemType Directory -Force -Path $clientLicensesRoot | Out-Null
  Copy-Item -LiteralPath (Join-Path $windowsRoot 'licenses\Codex-Dream-Skin-MIT.txt') `
    -Destination (Join-Path $clientLicensesRoot 'Codex-Dream-Skin-MIT.txt') -Force
  Write-Utf8NoBom -Path (Join-Path $clientRoot '第三方组件说明.txt') -Text @"
本包内置官方 Node.js v$NodeVersion Windows $Architecture 运行时，仅用于本机桌宠增强注入器。
Node.js 完整许可文本位于 payload\runtime\LICENSE.txt。
本项目、上游代码和桌宠素材声明位于 ZIP 根目录，并在 payload\licenses 中随安装文件保留。
下载来源：$baseUrl/$archiveName
下载包 SHA-256：$actualHash
"@

  $manifestFiles = @(Get-ChildItem -LiteralPath $payloadRoot -File -Recurse -Force | Sort-Object FullName | ForEach-Object {
      [ordered]@{
        path = $_.FullName.Substring($payloadRoot.Length).TrimStart('\').Replace('\', '/')
        size = [long]$_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
      }
    })
  $manifest = [ordered]@{
    schemaVersion = 1
    product = 'Codex Kiana Pet Enhancer'
    version = $version
    architecture = $Architecture
    nodeVersion = $NodeVersion
    createdAt = [DateTimeOffset]::UtcNow.ToString('O')
    files = $manifestFiles
  }
  Write-Utf8NoBom -Path (Join-Path $clientRoot 'release-manifest.json') -Text ($manifest | ConvertTo-Json -Depth 6)

  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path $clientRoot 'install-pet-enhancer-release.ps1') -SmokeTest
  if ($LASTEXITCODE -ne 0) {
    throw 'The packaged Windows PowerShell 5.1 isolated installation smoke test failed.'
  }

  $archivePath = Join-Path $OutputDirectory "$packageName.zip"
  if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
  Compress-Archive -LiteralPath $clientRoot -DestinationPath $archivePath -CompressionLevel Optimal

  $zipSmokeRoot = Join-Path $tempRoot '中文解包验证'
  Expand-Archive -LiteralPath $archivePath -DestinationPath $zipSmokeRoot -Force
  $zipSmokeInstaller = Join-Path (Join-Path $zipSmokeRoot $packageName) `
    'install-pet-enhancer-release.ps1'
  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $zipSmokeInstaller -VerifyOnly
  if ($LASTEXITCODE -ne 0) {
    throw 'The extracted public ZIP failed its Windows PowerShell 5.1 integrity verification.'
  }
  & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $zipSmokeInstaller -SmokeTest
  if ($LASTEXITCODE -ne 0) {
    throw 'The extracted public ZIP failed its Windows PowerShell 5.1 isolated installation smoke test.'
  }

  $releaseHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
  Write-Utf8NoBom -Path "$archivePath.sha256.txt" -Text "$releaseHash  $([System.IO.Path]::GetFileName($archivePath))`r`n"

  [pscustomobject]@{
    Archive = $archivePath
    Sha256 = $releaseHash
    SizeMiB = [math]::Round((Get-Item -LiteralPath $archivePath).Length / 1MB, 2)
    NodeVersion = $NodeVersion
    PayloadFiles = $manifestFiles.Count
  } | Format-List
} finally {
  if (Test-Path -LiteralPath $tempRoot) { [System.IO.Directory]::Delete($tempRoot, $true) }
}
