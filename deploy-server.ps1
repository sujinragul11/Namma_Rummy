# Puts the game server on a Linux machine of your own (a DigitalOcean droplet, for example)
# and keeps it up to date. Start it with deploy-server.bat:
#
#   deploy-server.bat root@203.0.113.10 rummy.example.com
#
# The first argument is how you reach the machine with ssh; the second is the public name the
# apps will connect to, whose DNS record must already point at the machine. The first run asks
# for the two names shown on the privacy policy and makes the secrets; they are kept in
# backend\.env.production on this PC and uploaded as the server's .env. Later runs only upload
# the code again and restart what changed.
param(
    [Parameter(Mandatory = $true)][string]$Server,
    [Parameter(Mandatory = $true)][string]$HostName
)

$ErrorActionPreference = "Stop"
$Backend = Join-Path $PSScriptRoot "backend"
$EnvFile = Join-Path $Backend ".env.production"
$Remote = "/opt/rummy"
$ssh = @("-o", "StrictHostKeyChecking=accept-new")

function Stop-Deploy([string]$Message) {
    Write-Host ""
    Write-Host $Message -ForegroundColor Red
    exit 1
}

# Random text for a secret: hexadecimal, or letters and digits only (the database password
# goes into a URL, where other characters would need escaping).
function New-Secret([int]$Bytes, [switch]$Alphanumeric) {
    $buffer = New-Object byte[] $Bytes
    [Security.Cryptography.RandomNumberGenerator]::Fill($buffer)
    if ($Alphanumeric) {
        $letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return -join ($buffer | ForEach-Object { $letters[$_ % $letters.Length] })
    }
    return -join ($buffer | ForEach-Object { $_.ToString("x2") })
}

if ($HostName -notmatch '^[a-z0-9.-]+$') { Stop-Deploy "The host name should look like rummy.example.com (no https://, no slash)." }
foreach ($tool in "ssh", "scp") {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Stop-Deploy "$tool was not found. Install the Windows OpenSSH client (Settings > Apps > Optional features)." }
}

# ---------- the server's settings, made once ----------

if (-not (Test-Path $EnvFile)) {
    Write-Host "First deployment: a few details for the privacy policy and the terms."
    $owner = Read-Host "Who publishes the app (a person or company name, shown as the legal owner)"
    $support = Read-Host "Support email address players can write to"
    if (-not $owner -or -not $support) { Stop-Deploy "Both are needed; nothing was changed." }
    $lines = @(
        "# Settings of the live game server, uploaded by deploy-server.bat. Keep this file private."
        "NODE_ENV=production"
        "PORT=3001"
        "JWT_SECRET=$(New-Secret 48)"
        "APP_NAME=Namma Rummy"
        "LEGAL_OWNER=$owner"
        "SUPPORT_EMAIL=$support"
        "DB_PASSWORD=$(New-Secret 24 -Alphanumeric)"
        "TRUST_PROXY=1"
    )
    [IO.File]::WriteAllText($EnvFile, ($lines -join "`n") + "`n")
    Write-Host "Written to $EnvFile. Keep a copy: JWT_SECRET signs every login and DB_PASSWORD opens the database." -ForegroundColor Yellow
}

# ---------- upload ----------

Write-Host ""
Write-Host "Uploading the backend to ${Server}:$Remote ..."
& ssh @ssh $Server "mkdir -p $Remote/deploy"
if ($LASTEXITCODE -ne 0) { Stop-Deploy "Could not reach $Server with ssh." }

$files = @("Dockerfile", ".dockerignore", "docker-compose.yml", "package.json", "package-lock.json", ".env.example") |
    ForEach-Object { Join-Path $Backend $_ }
& scp @ssh -q @files "${Server}:$Remote/"
& scp @ssh -q -r (Join-Path $Backend "src") "${Server}:$Remote/"
& scp @ssh -q (Join-Path $Backend "deploy\setup.sh") "${Server}:$Remote/deploy/setup.sh"
& scp @ssh -q $EnvFile "${Server}:$Remote/.env"
if ($LASTEXITCODE -ne 0) { Stop-Deploy "The upload failed." }

# ---------- set up and start ----------

Write-Host "Setting up the server (the first run installs Docker and Caddy and takes a few minutes) ..."
# The script is written on Windows; the server needs Unix line endings
& ssh @ssh $Server "sed -i 's/\r$//' $Remote/deploy/setup.sh $Remote/.env && chmod 600 $Remote/.env && bash $Remote/deploy/setup.sh $HostName"
if ($LASTEXITCODE -ne 0) { Stop-Deploy "The setup on the server failed; the lines above say where." }

# ---------- check from here ----------

Write-Host ""
Write-Host "Checking https://$HostName from this PC ..."
try {
    $health = Invoke-RestMethod -Uri "https://$HostName/health" -TimeoutSec 20
    Write-Host "The game server answers: $($health.status)" -ForegroundColor Green
} catch {
    Write-Host "No answer yet at https://$HostName/health : $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "If the DNS record was made just now, give it a few minutes and open the address in a browser."
}
Write-Host ""
Write-Host "Next: put `"https://$HostName`" into RELEASE_SERVER_URL in godot\autoload\config.gd and run build-android.bat."
Write-Host "To try it before that, type $HostName into the Server field of the test app on the phone."
