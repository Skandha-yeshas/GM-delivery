param([switch]$Preview, [switch]$Template, [switch]$FixStyle, [string]$TestFile)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Join-Path $PSScriptRoot '..')
$flutterSdkPath = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
# Flutter 3.44 invokes native hooks without quoting its Dart executable on Windows.
# The Windows short path avoids spaces without modifying the user's SDK.
$fileSystemObject = New-Object -ComObject Scripting.FileSystemObject
$shortFlutterSdkPath = $fileSystemObject.GetFolder($flutterSdkPath).ShortPath
$flutterTool = Join-Path $shortFlutterSdkPath 'bin\flutter.bat'
$dartTool = Join-Path $shortFlutterSdkPath 'bin\dart.bat'
if ($TestFile) {
    & $flutterTool test $TestFile
    if ($LASTEXITCODE -ne 0) { throw 'Focused tests failed.' }
    exit 0
}
if ($Template) {
    & $dartTool format tool\create_shop_template_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Template tool formatting failed.' }
    & $flutterTool test tool\create_shop_template_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Template generation failed.' }
    Write-Output 'Excel template: docs/templates/GM_Shops_Template.xlsx'
    exit 0
}
if ($Preview) {
    $env:GM_PREVIEW_FLUTTER_ROOT = $shortFlutterSdkPath
    & $dartTool format tool\capture_preview_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Preview formatting failed.' }
    & $flutterTool test tool\capture_preview_test.dart
    if ($LASTEXITCODE -ne 0) { throw 'Preview capture failed.' }
    Write-Output 'Open preview/index.html to view the app at a phone aspect ratio.'
    exit 0
}
& $flutterTool pub get
if ($LASTEXITCODE -ne 0) { throw 'Dependency resolution failed.' }
if ($FixStyle) {
    & $dartTool format lib test
    if ($LASTEXITCODE -ne 0) { throw 'Formatting failed.' }
    & $dartTool fix --apply --code=curly_braces_in_flow_control_structures
    if ($LASTEXITCODE -ne 0) { throw 'Style fixes failed.' }
}
& $dartTool format lib test
if ($LASTEXITCODE -ne 0) { throw 'Formatting failed.' }
& $flutterTool analyze
if ($LASTEXITCODE -ne 0) { throw 'Static analysis failed.' }
& $flutterTool test
if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
