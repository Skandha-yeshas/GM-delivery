# Run interactively in your own terminal. Do not pass secrets as arguments.
# Uses the supported Auth admin API; changes only the selected user's password.
$ErrorActionPreference = 'Stop'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'

function Read-PrivateText([string]$Prompt) {
    $secureInput = Read-Host $Prompt -AsSecureString
    $privatePointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureInput)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($privatePointer) }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($privatePointer)
        $secureInput.Dispose()
    }
}

function Invoke-AdminRequest([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$Body) {
    try {
        $requestOptions = @{
            Method = $Method
            Uri = $Uri
            Headers = $Headers
            # PowerShell's default Mozilla User-Agent can trigger Supabase's
            # browser restriction for secret keys. This is a local admin tool.
            UserAgent = 'GM-Delivery-Local-Admin/1.0'
            TimeoutSec = 30
            MaximumRedirection = 0
            ErrorAction = 'Stop'
        }
        if ($Body) {
            $requestOptions.ContentType = 'application/json; charset=utf-8'
            $requestOptions.Body = [Text.Encoding]::UTF8.GetBytes($Body)
        }
        Invoke-RestMethod @requestOptions
    } catch {
        # Do not echo HTTP request bodies, headers, passwords or tokens.
        $httpStatus = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 0 }
        $stage = if ($Method -eq 'Get') { 'Account lookup' } else { 'Password update' }
        $guidance = switch ($httpStatus) {
            401 { 'The admin key was rejected. Copy an active secret key (sb_secret_...) or legacy service_role key from Settings > API Keys in the project printed above. Public publishable/anon keys cannot reset passwords.' }
            403 { 'Administrator access was denied. Check that this is the project''s secret/service_role key and that it is still active.' }
            404 { 'The account was not found. Copy its current User UID from Authentication > Users in this project.' }
            400 { 'The request was rejected. If updating the password, check the project''s password policy and choose a different password.' }
            422 { 'The request was rejected. If updating the password, check the project''s password policy and choose a different password.' }
            429 { 'Supabase rate-limited this request. Wait before trying again.' }
            default { 'Check connectivity and the project status. If this happened during a password update, its outcome may be uncertain; try the new password before repeating.' }
        }
        $statusLabel = if ($httpStatus) { $httpStatus } else { 'unavailable' }
        throw "$stage failed (HTTP $statusLabel). $guidance No private request or response details were printed."
    }
}

$adminHeaders = @{}
$adminToken = $null
$newPassword = $null
$repeatPassword = $null
$requestJson = $null
try {
    $projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
    $config = Get-Content -LiteralPath (Join-Path $projectRoot 'config\cloud.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $projectUrl = ([string]$config.SUPABASE_URL).TrimEnd('/')
    if ($projectUrl -notmatch '^https://[a-z0-9-]+\.supabase\.co$') {
        throw 'Expected a hosted HTTPS Supabase project URL in config/cloud.json.'
    }
    Write-Host "Project: $projectUrl"
    $accountInput = Read-Host 'Paste the existing owner User UID from Authentication > Users'
    $accountGuid = [guid]::Empty
    if (-not [guid]::TryParse($accountInput.Trim(), [ref]$accountGuid)) {
        throw 'The User UID must be a UUID, not an email address.'
    }
    $accountUrl = "$projectUrl/auth/v1/admin/users/$($accountGuid.ToString())"
    $adminToken = (Read-PrivateText 'Paste this project''s secret API key (sb_secret_...) or legacy service_role JWT (hidden)').Trim()
    if ($adminToken -match '^sb_secret_[A-Za-z0-9_-]+$') {
        # Secret API keys are not JWTs. Let the hosted gateway resolve the role.
        $adminHeaders = @{ apikey = $adminToken }
    } elseif ($adminToken -match '^eyJ[^.]+\.[^.]+\.[^.]+$') {
        # Inspect metadata only; the server still verifies the JWT signature.
        # Reject accidental anon keys and keys from the deleted project locally.
        $jwtSegment = $adminToken.Split('.')[1].Replace('-', '+').Replace('_', '/')
        $jwtSegment = $jwtSegment.PadRight($jwtSegment.Length + ((4 - $jwtSegment.Length % 4) % 4), '=')
        try { $jwtClaims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($jwtSegment)) | ConvertFrom-Json }
        catch { throw 'The legacy JWT could not be read. Copy the complete service_role key from Settings > API Keys.' }
        if ($jwtClaims.role -cne 'service_role') {
            throw 'This JWT is not a service_role key. An anon key or app user token cannot reset passwords. Copy a secret/service_role key from Settings > API Keys.'
        }
        $expectedProjectRef = ([uri]$projectUrl).Host.Split('.')[0]
        if ($jwtClaims.ref -cne $expectedProjectRef) {
            throw 'This legacy service_role key belongs to a different project. Copy the key from the project printed above.'
        }
        if ($jwtClaims.exp -and [double]$jwtClaims.exp -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
            throw 'This legacy service_role key has expired. Copy an active secret/service_role key from this project.'
        }
        $adminHeaders = @{ apikey = $adminToken; Authorization = "Bearer $adminToken" }
    } else {
        throw 'Use a secret API key or legacy service_role JWT from this project''s API Keys settings, not the publishable key.'
    }
    $account = Invoke-AdminRequest 'Get' $accountUrl $adminHeaders
    if ($account.id -ne $accountGuid.ToString() -or -not $account.email) {
        throw 'The selected authentication account could not be verified.'
    }
    Write-Host "Existing account: $($account.email)"
    $selectedEmail = Read-Host 'Type that exact email to select this account (leave blank to cancel)'
    if (-not [string]::Equals($selectedEmail.Trim(), [string]$account.email, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Account selection did not match. Nothing was changed.'
    }
    $newPassword = Read-PrivateText 'Enter the new app password (hidden)'
    $repeatPassword = Read-PrivateText 'Repeat the new app password (hidden)'
    if ([string]::IsNullOrEmpty($newPassword) -or $newPassword -cne $repeatPassword) {
        throw 'Passwords were empty or did not match. Nothing was changed.'
    }
    $requestJson = @{ password = $newPassword } | ConvertTo-Json -Compress
    $updatedAccount = Invoke-AdminRequest 'Put' $accountUrl $adminHeaders $requestJson
    if ($updatedAccount.id -ne $accountGuid.ToString()) {
        throw 'Could not verify the password-update acknowledgement. Check the account before retrying.'
    }
    Write-Host 'Password updated. Sign in to the app using this account email and your new password.'
    Write-Host 'The user ID, owner profile and delivery records were not changed.'
    if (-not $updatedAccount.email_confirmed_at) {
        Write-Host 'This email is not confirmed yet. Complete email confirmation before signing in.'
    }
} finally {
    $adminHeaders.Clear()
    $adminToken = $null
    $newPassword = $null
    $repeatPassword = $null
    $requestJson = $null
}
