# Offline only: both prompts and HTTP requests are replaced with controlled mocks.
$ErrorActionPreference = 'Stop'
$helperPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'reset_app_password.ps1'
$parseTokens = $null
$parseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'Password helper has PowerShell syntax errors.' }
$script:testUserId = '11111111-1111-4111-8111-111111111111'
$script:testEmail = 'mock-owner@example.invalid'
$script:testKey = 'eyJmock.mock.signature'
$script:testPassword = 'Mock-only-Password-928!'
$script:testRequests = [Collections.Generic.List[object]]::new()
$testConfigPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'config\cloud.json'
$testConfig = Get-Content -LiteralPath $testConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$script:testProjectRef = ([uri]$testConfig.SUPABASE_URL).Host.Split('.')[0]

class MockPasswordHttpException : System.Exception {
    [object]$Response
    MockPasswordHttpException([int]$Status, [string]$PrivateMessage) : base($PrivateMessage) {
        $this.Response = [pscustomobject]@{StatusCode=$Status}
    }
}

function New-MockLegacyKey([string]$Role, [string]$ProjectRef, [long]$Expiration) {
    $claims = @{role=$Role;ref=$ProjectRef;exp=$Expiration} | ConvertTo-Json -Compress
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($claims)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    return "eyJmock.$encoded.signature"
}

function Read-Host {
    param([string]$Prompt, [switch]$AsSecureString)
    if ($script:testAnswers.Count -eq 0) { throw 'Unexpected input prompt.' }
    $answer = $script:testAnswers.Dequeue()
    if ($AsSecureString) { return ConvertTo-SecureString $answer -AsPlainText -Force }
    return $answer
}

function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $UserAgent, $TimeoutSec, $MaximumRedirection, $ErrorAction, $ContentType, $Body)
    if ($Uri -notmatch ('^https://[a-z0-9-]+\.supabase\.co/auth/v1/admin/users/' + $script:testUserId + '$')) {
        throw 'Unexpected request target.'
    }
    $expectedAuthorization = if ($script:testKey.StartsWith('sb_secret_')) { $null } else { "Bearer $script:testKey" }
    if ($Headers.apikey -cne $script:testKey -or $Headers.Authorization -cne $expectedAuthorization -or $MaximumRedirection -ne 0 -or $UserAgent -cne 'GM-Delivery-Local-Admin/1.0') {
        throw 'Incorrect admin headers, non-browser User-Agent or redirect behavior.'
    }
    $script:testRequests.Add($Method)
    if ($Method -eq 'Get' -and $script:mockGetStatus) {
        throw [MockPasswordHttpException]::new($script:mockGetStatus, "Private server error $($script:testKey) $($script:testPassword)")
    }
    if ($Method -eq 'Put') {
        $payload = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
        $fields = @($payload.PSObject.Properties.Name)
        if ($fields.Count -ne 1 -or $fields[0] -ne 'password' -or $payload.password -cne $script:testPassword) {
            throw 'Update must contain only the exact new password.'
        }
        if ($script:mockPutStatus) {
            throw [MockPasswordHttpException]::new($script:mockPutStatus, "Private server error $($script:testKey) $($script:testPassword)")
        }
        if ($script:rejectUpdate) { throw "Private server error $($script:testKey) $($script:testPassword)" }
    }
    return [pscustomobject]@{id=$script:testUserId;email=$script:testEmail;email_confirmed_at='2026-10-25T00:00:00Z'}
}

$scenarios = @('success', 'secret-key-success', 'password-mismatch', 'email-mismatch', 'invalid-user-id', 'server-rejection',
    'get-401', 'put-401', 'get-403', 'get-404', 'put-422', 'anon-key', 'wrong-project-key', 'expired-key', 'malformed-jwt', 'publishable-key')
foreach ($scenario in $scenarios) {
    $script:testKey = New-MockLegacyKey 'service_role' $script:testProjectRef ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600)
    switch ($scenario) {
        'secret-key-success' { $script:testKey = 'sb_secret_mock_test_key' }
        'anon-key' { $script:testKey = New-MockLegacyKey 'anon' $script:testProjectRef ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600) }
        'wrong-project-key' { $script:testKey = New-MockLegacyKey 'service_role' 'different-project' ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 3600) }
        'expired-key' { $script:testKey = New-MockLegacyKey 'service_role' $script:testProjectRef 1 }
        'malformed-jwt' { $script:testKey = 'eyJmock.not-json.signature' }
        'publishable-key' { $script:testKey = 'sb_publishable_mock_public_key' }
    }
    $script:testAnswers = [Collections.Generic.Queue[string]]::new()
    $script:testRequests.Clear()
    $script:rejectUpdate = $scenario -eq 'server-rejection'
    $script:mockGetStatus = switch ($scenario) { 'get-401' {401} 'get-403' {403} 'get-404' {404} default {0} }
    $script:mockPutStatus = switch ($scenario) { 'put-401' {401} 'put-422' {422} default {0} }
    $userInput = if ($scenario -eq 'invalid-user-id') { 'not-a-user-id' } else { $script:testUserId }
    $emailInput = if ($scenario -eq 'email-mismatch') { 'someone-else@example.invalid' } else { $script:testEmail }
    $passwordRepeat = if ($scenario -eq 'password-mismatch') { 'Different mock password' } else { $script:testPassword }
    foreach ($answer in @($userInput, $script:testKey, $emailInput, $script:testPassword, $passwordRepeat)) {
        $script:testAnswers.Enqueue($answer)
    }
    $capturedOutput = @()
    $caughtMessage = $null
    try { $capturedOutput = @(. $helperPath 6>&1) }
    catch { $caughtMessage = $_.Exception.Message }
    if ($scenario -in @('success', 'secret-key-success')) {
        if ($caughtMessage -or $script:testRequests.Count -ne 2 -or $script:testRequests[1] -ne 'Put') {
            throw "Successful reset workflow failed: $caughtMessage (requests: $($script:testRequests.Count))."
        }
    } else {
        if (-not $caughtMessage) { throw "Expected failure: $scenario" }
        $expectedRequests = if ($scenario -in @('invalid-user-id','anon-key','wrong-project-key','expired-key','malformed-jwt','publishable-key')) { 0 } elseif ($scenario -in @('server-rejection','put-401','put-422')) { 2 } else { 1 }
        if ($script:testRequests.Count -ne $expectedRequests) { throw "Unexpected mutation: $scenario" }
        $expectedError = switch ($scenario) {
            'get-401' {'Account lookup failed (HTTP 401). The admin key was rejected.'}
            'put-401' {'Password update failed (HTTP 401). The admin key was rejected.'}
            'get-403' {'Administrator access was denied.'}
            'get-404' {'The account was not found.'}
            'put-422' {'password policy'}
            'server-rejection' {'outcome may be uncertain'}
            'anon-key' {'not a service_role key'}
            'wrong-project-key' {'different project'}
            'expired-key' {'expired'}
            'malformed-jwt' {'JWT could not be read'}
            default {$null}
        }
        if ($expectedError -and -not $caughtMessage.Contains($expectedError)) { throw "Incorrect guidance: $scenario" }
    }
    $visibleText = ($capturedOutput -join "`n") + $caughtMessage
    if ($visibleText.Contains($script:testKey) -or $visibleText.Contains($script:testPassword)) {
        throw "Private input appeared in output: $scenario"
    }
    Write-Output "PASS: $scenario"
}
Write-Output "Password helper syntax and all $($scenarios.Count) offline workflows passed. No HTTP requests were sent."
