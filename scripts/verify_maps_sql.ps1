param([string]$TestFile = 'supabase\tests\maps_link_delivery.sql')
$ErrorActionPreference = 'Stop'
$workspacePath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$clusterPath = Join-Path $workspacePath ('.tooling\pg-test-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$initTool = (Get-Command initdb -ErrorAction Stop).Source
$serverTool = (Get-Command postgres -ErrorAction Stop).Source
$controlTool = (Get-Command pg_ctl -ErrorAction Stop).Source
$sqlTool = (Get-Command psql -ErrorAction Stop).Source
$readyTool = (Get-Command pg_isready -ErrorAction Stop).Source
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$testPort = $listener.LocalEndpoint.Port
$listener.Stop()
& $initTool -D $clusterPath -U gm_test -A trust --no-locale -E UTF8 --no-sync
if ($LASTEXITCODE -ne 0) { throw 'Disposable PostgreSQL initialization failed.' }
$serverProcess = $null
try {
    $serverProcess = Start-Process -FilePath $serverTool -ArgumentList @('-D', ('"{0}"' -f $clusterPath), '-h', '127.0.0.1', '-p', "$testPort") -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $clusterPath 'server.log') -RedirectStandardError (Join-Path $clusterPath 'server-errors.log')
    $ready = $false
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        & $readyTool -h 127.0.0.1 -p $testPort -U gm_test -d postgres | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Milliseconds 100
    }
    if (-not $ready) { throw "Disposable PostgreSQL did not start. Check $clusterPath\server-errors.log" }
    & $sqlTool -X -h 127.0.0.1 -p $testPort -U gm_test -d postgres -v ON_ERROR_STOP=1 -f (Join-Path $workspacePath $TestFile)
    if ($LASTEXITCODE -ne 0) { throw 'SQL checks failed.' }
} finally {
    if ($serverProcess) {
        # This cluster contains disposable test data only. Immediate shutdown
        # also avoids waiting for background workers in restricted Windows jobs.
        & $controlTool -D $clusterPath -m immediate -t 15 -w stop
        if ($LASTEXITCODE -ne 0 -and -not $serverProcess.HasExited) { throw 'Could not stop disposable PostgreSQL.' }
    }
}
