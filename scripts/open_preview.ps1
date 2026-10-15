$ErrorActionPreference = 'Stop'
$previewPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\preview\index.html'))
if (-not (Test-Path -LiteralPath $previewPath)) { throw 'The phone preview has not been created yet.' }
$previewUri = ([Uri]$previewPath).AbsoluteUri
$browserPaths = @(
    'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe',
    'C:\Program Files\Microsoft\Edge\Application\msedge.exe'
)
$browserPath = $browserPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($browserPath) {
    # Visible window: this is the interactive preview the user requested.
    Start-Process -FilePath $browserPath -ArgumentList @('--new-window', $previewUri) -WindowStyle Normal
} else {
    Invoke-Item -LiteralPath $previewPath
}
