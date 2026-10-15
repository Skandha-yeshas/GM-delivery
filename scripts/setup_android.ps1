param([switch]$AcceptLicenses)
$ErrorActionPreference = 'Stop'
$env:DEBUG = ''
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sdkPath = [IO.Path]::GetFullPath((Join-Path $workspacePath '.tooling\android-sdk'))
$downloadsPath = [IO.Path]::GetFullPath((Join-Path $workspacePath '.tooling\downloads'))
$workspacePrefix = $workspacePath.TrimEnd('\') + '\'
foreach ($targetPath in @($sdkPath, $downloadsPath)) {
    if (-not $targetPath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Android setup target must stay inside this workspace.'
    }
}
New-Item -ItemType Directory -Path $sdkPath, $downloadsPath -Force | Out-Null
$managerPath = Join-Path $sdkPath 'cmdline-tools\latest\bin\sdkmanager.bat'
if (-not (Test-Path -LiteralPath $managerPath)) {
    $archivePath = Join-Path $downloadsPath 'commandlinetools-win-15859902_latest.zip'
    $expectedHash = '90ae805d20434428bffcb699c290860f19bb5f66a67e6b330067e3de801fb04a'
    if (-not (Test-Path -LiteralPath $archivePath)) {
        Write-Output 'Downloading official Android command-line tools...'
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri 'https://dl.google.com/android/repository/commandlinetools-win-15859902_latest.zip' -OutFile $archivePath -UseBasicParsing
    }
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
        throw 'Android command-line tools checksum did not match the official download.'
    }
    $commandToolsPath = Join-Path $sdkPath 'cmdline-tools'
    New-Item -ItemType Directory -Path $commandToolsPath -Force | Out-Null
    Expand-Archive -LiteralPath $archivePath -DestinationPath $commandToolsPath -Force
    $extractedPath = [IO.Path]::GetFullPath((Join-Path $commandToolsPath 'cmdline-tools'))
    $latestPath = [IO.Path]::GetFullPath((Join-Path $commandToolsPath 'latest'))
    foreach ($movePath in @($extractedPath, $latestPath)) {
        if (-not $movePath.StartsWith($workspacePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Android tool move escaped the workspace.'
        }
    }
    if (Test-Path -LiteralPath $latestPath) { throw 'Unexpected partial installation at cmdline-tools/latest. Review it before continuing.' }
    Move-Item -LiteralPath $extractedPath -Destination $latestPath
}
$env:ANDROID_HOME = $sdkPath
$env:ANDROID_SDK_ROOT = $sdkPath
# SDK manager creates its settings in ANDROID_USER_HOME; keep that inside the workspace.
$env:ANDROID_USER_HOME = Join-Path $workspacePath '.tooling\android-user'
New-Item -ItemType Directory -Path $env:ANDROID_USER_HOME -Force | Out-Null
if ($AcceptLicenses) {
    Write-Output 'Accepting Android SDK licenses for this installation...'
    (1..30 | ForEach-Object { 'y' }) | & $managerPath "--sdk_root=$sdkPath" --licenses
    if ($LASTEXITCODE -ne 0) { throw 'SDK license setup failed.' }
}
Write-Output 'Installing Android 36 build tools...'
& $managerPath "--sdk_root=$sdkPath" 'platform-tools' 'platforms;android-36' 'build-tools;36.0.0'
if ($LASTEXITCODE -ne 0) { throw 'Android SDK package installation failed.' }
$localPropertiesPath = Join-Path $workspacePath 'android\local.properties'
$existingLines = @()
if (Test-Path -LiteralPath $localPropertiesPath) {
    $existingLines = Get-Content -LiteralPath $localPropertiesPath | Where-Object { $_ -notmatch '^sdk\.dir=' }
}
$escapedSdkPath = $sdkPath.Replace('\', '\\').Replace(':', '\:')
Set-Content -LiteralPath $localPropertiesPath -Value (@($existingLines) + "sdk.dir=$escapedSdkPath") -Encoding ASCII
Write-Output "Android SDK installed inside $sdkPath"
