param([switch]$Shared, [switch]$PreloadGradle)
$ErrorActionPreference = 'Stop'
$env:DEBUG = ''
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $workspacePath
$sdkPath = Join-Path $workspacePath '.tooling\android-sdk'
if (Test-Path -LiteralPath $sdkPath) {
    $env:ANDROID_HOME = $sdkPath
    $env:ANDROID_SDK_ROOT = $sdkPath
    $env:ANDROID_USER_HOME = Join-Path $workspacePath '.tooling\android-user'
}
$flutterSdkPath = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
$fileSystemObject = New-Object -ComObject Scripting.FileSystemObject
$flutterTool = Join-Path $fileSystemObject.GetFolder($flutterSdkPath).ShortPath 'bin\flutter.bat'
$buildArguments = @('build', 'apk', '--debug')
if ($Shared) {
    $cloudPath = Join-Path $workspacePath 'config\cloud.json'
    if (-not (Test-Path -LiteralPath $cloudPath)) { throw 'Fill config/cloud.json before building a shared APK.' }
    $cloudConfiguration = Get-Content -LiteralPath $cloudPath -Raw | ConvertFrom-Json
    if ($cloudConfiguration.SUPABASE_URL -match 'YOUR_PROJECT' -or
        -not $cloudConfiguration.SUPABASE_URL -or
        -not $cloudConfiguration.SUPABASE_PUBLISHABLE_KEY) {
        throw 'Replace the example cloud values before building a shared APK.'
    }
    $buildArguments += '--dart-define-from-file=config/cloud.json'
}
$wrapperPath = Join-Path $workspacePath 'android\gradle\wrapper\gradle-wrapper.properties'
$originalWrapper = [IO.File]::ReadAllBytes($wrapperPath)
try {
    if ($PreloadGradle) {
        # Fallback when Java's downloader times out: fetch the SAME official,
        # checksum-verified distribution with PowerShell and use it for this build.
        $downloadsPath = Join-Path $workspacePath '.tooling\downloads'
        New-Item -ItemType Directory -Path $downloadsPath -Force | Out-Null
        $archivePath = Join-Path $downloadsPath 'gradle-9.1.0-bin.zip'
        $distributionUrl = 'https://downloads.gradle.org/distributions/gradle-9.1.0-bin.zip'
        $ProgressPreference = 'SilentlyContinue'
        Write-Output 'Downloading the official Gradle distribution and checksum...'
        $checksumResponse = Invoke-WebRequest -Uri "$distributionUrl.sha256" -UseBasicParsing -TimeoutSec 90
        if ($checksumResponse.Content -is [byte[]]) {
            $checksum = [Text.Encoding]::ASCII.GetString($checksumResponse.Content).Trim()
        } else {
            $checksum = ([string]$checksumResponse.Content).Trim()
        }
        if ($checksum -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid official Gradle checksum response.' }
        if (-not (Test-Path -LiteralPath $archivePath)) {
            Invoke-WebRequest -Uri $distributionUrl -OutFile $archivePath -UseBasicParsing -TimeoutSec 90
        }
        if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $checksum.ToLowerInvariant()) {
            throw 'The Gradle distribution checksum did not match.'
        }
        $archiveUri = ([Uri]$archivePath).AbsoluteUri
        $wrapperText = [Text.Encoding]::UTF8.GetString($originalWrapper)
        $wrapperText = [regex]::Replace($wrapperText, '(?m)^distributionUrl=.*$', "distributionUrl=$archiveUri")
        [IO.File]::WriteAllText($wrapperPath, $wrapperText, [Text.UTF8Encoding]::new($false))
    }
    & $flutterTool @buildArguments
    if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
} finally {
    if ($PreloadGradle) { [IO.File]::WriteAllBytes($wrapperPath, $originalWrapper) }
}
Write-Output 'Test APK: build/app/outputs/flutter-apk/app-debug.apk'
