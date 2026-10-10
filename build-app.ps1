# Builds the store files of the Godot game. Start it with build-android.bat or build-ios.bat:
#
#   build-android.bat          The store build: build\namma-rummy-<version>-<code>.aab to upload
#                              to Google Play, and the same game as an .apk to try on a phone.
#   build-android.bat bump     The same, after raising the version code by one. Google Play
#                              refuses an upload whose version code it has seen before.
#   build-android.bat debug    A test .apk that keeps the Server field, for playing against the
#                              backend on your PC before the public server exists.
#   build-ios.bat              The Xcode project in build\ios. A Mac turns it into the app
#                              and uploads it; Windows cannot do that part.
param([string]$Platform = "android", [string]$Mode = "release")

$ErrorActionPreference = "Stop"

# If one of these is somewhere else on your PC, correct the line.
$Godot = "$env:USERPROFILE\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$JavaHome = "$env:LOCALAPPDATA\Android\jdk-17"
$AndroidSdk = "$env:LOCALAPPDATA\Android\Sdk"
# The upload key is kept outside the project so it can never be shared along with the code.
$KeyFolder = "$env:USERPROFILE\namma-rummy-keys"

$Project = Join-Path $PSScriptRoot "godot"
$Out = Join-Path $PSScriptRoot "build"
$Presets = Join-Path $Project "export_presets.cfg"
$Keytool = Join-Path $JavaHome "bin\keytool.exe"
$UploadKey = Join-Path $KeyFolder "upload-key.jks"
$DebugKey = Join-Path $KeyFolder "debug.keystore"

function Stop-Build([string]$Message) {
    Write-Host ""
    Write-Host $Message -ForegroundColor Red
    exit 1
}

function Read-Password([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

# Runs keytool with the password handed over in the environment, never on the command line.
function Invoke-Keytool([string]$Password, [string[]]$Arguments) {
    $ErrorActionPreference = "Continue"  # keytool reports progress on the error stream
    $env:RUMMY_KEY_PASSWORD = $Password
    try {
        & $Keytool @Arguments 2>&1 | Out-Null
        return $LASTEXITCODE -eq 0
    } finally {
        Remove-Item Env:RUMMY_KEY_PASSWORD
    }
}

# Godot takes the Java and Android SDK folders from its own settings
# (Editor > Editor Settings > Export > Android), so they are written there.
function Set-GodotAndroidPaths {
    $ErrorActionPreference = "Continue"
    $release = (& $Godot --version 2>$null | Select-Object -First 1) -replace '^(\d+\.\d+).*$', '$1'
    $file = "$env:APPDATA\Godot\editor_settings-$release.tres"
    if (-not (Test-Path $file)) { return }  # a fresh Godot reads JAVA_HOME and ANDROID_HOME, set below

    $text = [IO.File]::ReadAllText($file)
    $wanted = @{
        "export/android/java_sdk_path" = $JavaHome.Replace("\", "/")
        "export/android/android_sdk_path" = $AndroidSdk.Replace("\", "/")
    }
    $changed = $text
    foreach ($key in $wanted.Keys) {
        $line = $key + ' = "' + $wanted[$key] + '"'
        $changed = [regex]::Replace($changed, "(?m)^" + [regex]::Escape($key) + " = [^\r\n]*", $line.Replace('$', '$$'))
    }
    if ($changed -cne $text) { [IO.File]::WriteAllText($file, $changed) }
}

# Runs one Godot export and stops the build unless `$Result` exists afterwards.
function Export-Game([string]$Kind, [string]$Preset, [string]$File, [string]$Result, [string[]]$Extra = @()) {
    $ErrorActionPreference = "Continue"  # Godot and Gradle write warnings to the error stream
    Write-Host ""
    Write-Host "Building $Result ..."
    # A folder (the Xcode project) is built from nothing. A file from the last build stays
    # where it is until the new one replaces it, so a failed build leaves it usable.
    $isFolder = Test-Path $Result -PathType Container
    if ($isFolder) { Remove-Item $Result -Recurse }
    $started = Get-Date
    $log = Join-Path $Out "build.log"
    & $Godot --headless --path $Project @Extra "--export-$Kind" $Preset $File *> $log
    $made = (Test-Path $Result) -and ((Test-Path $Result -PathType Container) -or (Get-Item $Result).LastWriteTime -ge $started)
    if (-not $made) {
        Get-Content $log | Select-Object -Last 25
        Stop-Build "The build failed. The full output is in $log"
    }
}

function Read-Setting([string]$File, [string]$Pattern) {
    return [regex]::Match((Get-Content $File -Raw), $Pattern).Groups[1].Value
}

# A store build plays on one fixed server; without its address the game could not connect.
function Get-ReleaseServer {
    $server = Read-Setting (Join-Path $Project "autoload\config.gd") 'const RELEASE_SERVER_URL := "([^"]*)"'
    if (-not $server.StartsWith("https://")) {
        Stop-Build ("The store build needs the address of your public game server.`n" +
            "Open godot\autoload\config.gd and set RELEASE_SERVER_URL, for example `"https://rummy.yourdomain.com`".`n" +
            "It must start with https://")
    }
    return $server
}

if ($Platform -notin "android", "ios" -or $Mode -notin "release", "bump", "debug") {
    Stop-Build "Use: build-android.bat [bump | debug]   or   build-ios.bat"
}
if (-not (Test-Path $Godot)) { Stop-Build "Godot was not found at $Godot`nCorrect the Godot line at the top of build-app.ps1." }

New-Item -ItemType Directory -Force $Out | Out-Null
$version = Read-Setting (Join-Path $Project "project.godot") 'config/version="([^"]+)"'

# ---------- iPhone and iPad ----------

if ($Platform -eq "ios") {
    $server = Get-ReleaseServer
    $iosPreset = (Get-Content $Presets -Raw) -split '(?m)^\[preset\.' | Where-Object { $_ -match 'platform="iOS"' }
    if ($iosPreset -notmatch 'application/app_store_team_id="[A-Z0-9]{10}"') {
        Stop-Build ("The iOS build needs your Apple Team ID (10 letters and digits, shown under Membership`n" +
            "details on developer.apple.com). Put it into godot\export_presets.cfg:`n" +
            "  application/app_store_team_id=`"XXXXXXXXXX`"")
    }

    $folder = Join-Path $Out "ios"
    New-Item -ItemType Directory -Force $folder | Out-Null
    Export-Game "release" "iOS" (Join-Path $folder "namma-rummy.ipa") (Join-Path $folder "namma-rummy.xcodeproj")
    Write-Host ""
    Write-Host "Done. Version $version, server $server" -ForegroundColor Green
    Write-Host "Copy the whole folder $folder to a Mac, open namma-rummy.xcodeproj in Xcode,"
    Write-Host "then Product > Archive and Distribute App > App Store Connect."
    exit 0
}

# ---------- Android ----------

if (-not (Test-Path $Keytool)) { Stop-Build "JDK 17 was not found at $JavaHome`nCorrect the JavaHome line at the top of build-app.ps1." }
if (-not (Test-Path (Join-Path $AndroidSdk "platform-tools"))) { Stop-Build "The Android SDK was not found at $AndroidSdk`nCorrect the AndroidSdk line at the top of build-app.ps1." }

New-Item -ItemType Directory -Force $KeyFolder | Out-Null
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
# Otherwise Gradle leaves a helper process running for hours and the build never returns
$env:GRADLE_OPTS = "-Dorg.gradle.daemon=false"
Set-GodotAndroidPaths
$template = @("--install-android-build-template")
Write-Host "The first Android build downloads build files and takes several minutes; later ones are quicker."

if ($Mode -eq "bump") {
    $text = Get-Content $Presets -Raw
    $next = [int]([regex]::Match($text, 'version/code=(\d+)').Groups[1].Value) + 1
    [IO.File]::WriteAllText($Presets, [regex]::Replace($text, 'version/code=\d+', "version/code=$next"))
    Write-Host "Version code raised to $next."
}
$code = Read-Setting $Presets 'version/code=(\d+)'
$name = "namma-rummy-$version-$code"

if ($Mode -eq "debug") {
    if (-not (Test-Path $DebugKey)) {
        $made = Invoke-Keytool "android" @("-genkeypair", "-keystore", $DebugKey, "-alias", "androiddebugkey",
            "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000", "-dname", "CN=Android Debug,O=Android,C=US",
            "-storepass:env", "RUMMY_KEY_PASSWORD", "-keypass:env", "RUMMY_KEY_PASSWORD")
        if (-not $made) { Stop-Build "Could not create the debug key in $KeyFolder" }
    }
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $DebugKey
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = "androiddebugkey"
    $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = "android"

    $apk = Join-Path $Out "$name-debug.apk"
    Export-Game "debug" "Android APK" $apk $apk $template
    Write-Host ""
    Write-Host "Done: $apk" -ForegroundColor Green
    Write-Host "Copy it to the phone and open it to install. Type your PC's address into the Server field."
    exit 0
}

$server = Get-ReleaseServer

if (Test-Path $UploadKey) {
    $password = Read-Password "Password of your upload key"
    $opens = Invoke-Keytool $password @("-list", "-keystore", $UploadKey, "-storepass:env", "RUMMY_KEY_PASSWORD")
    if (-not $opens) { Stop-Build "That password does not open $UploadKey" }
} else {
    Write-Host ""
    Write-Host "No upload key yet. Google Play recognises your uploads by this key, so one is created now:"
    Write-Host "  $UploadKey"
    Write-Host "Choose a password of at least 6 characters. Nothing shows while you type."
    $password = Read-Password "New password"
    if ($password.Length -lt 6) { Stop-Build "The password needs at least 6 characters." }
    if ((Read-Password "The same password again") -cne $password) { Stop-Build "The two passwords differ. Nothing was created." }
    $made = Invoke-Keytool $password @("-genkeypair", "-keystore", $UploadKey, "-alias", "upload",
        "-keyalg", "RSA", "-keysize", "2048", "-validity", "10000", "-dname", "CN=Namma Rummy",
        "-storepass:env", "RUMMY_KEY_PASSWORD", "-keypass:env", "RUMMY_KEY_PASSWORD")
    if (-not $made) { Stop-Build "Could not create the upload key." }
    Write-Host "Created. Keep a copy of that file and its password somewhere safe:" -ForegroundColor Yellow
    Write-Host "without them you cannot upload an update until Google resets your key." -ForegroundColor Yellow
}

$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $UploadKey
$env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = "upload"
$env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $password

$aab = Join-Path $Out "$name.aab"
$apk = Join-Path $Out "$name.apk"
Export-Game "release" "Android" $aab $aab $template
Export-Game "release" "Android APK" $apk $apk $template

Write-Host ""
Write-Host "Done. Version $version, version code $code, server $server" -ForegroundColor Green
Write-Host "  Upload to Google Play:  $aab"
Write-Host "  Try on a phone first:   $apk"
