# AI Gauge - Windows installer / updater (run from PowerShell)
#
#   irm https://raw.githubusercontent.com/vh2c/ai-gauge/main/windows/get-ai-gauge.ps1 | iex
#
# What it does, in order:
#   1. downloads the latest AI-Gauge-Setup.exe and SHA256SUMS.txt from GitHub
#   2. verifies the SHA-256 checksum (aborts, running nothing, if it does not match)
#   3. starts the installer (no administrator rights needed; it replaces a previous version and keeps your settings)
#
# Why use it: a file downloaded with PowerShell is not flagged as "downloaded from the internet", so Windows
# normally does not show the blue "Windows protected your PC" screen for it (the installer is not code-signed yet).
# The script never changes system security settings.
#
# Optional environment variables:
#   AIGAUGE_VERSION   a release tag such as v1.1.1 (default: the latest release)
#   AIGAUGE_BASE_URL  download base URL (for testing)
#   AIGAUGE_SILENT    set to 1 to install without the wizard and reopen AI Gauge (used by the app's "Update now" button)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
$ProgressPreference = "SilentlyContinue"   # much faster downloads on Windows PowerShell 5.1

$exeName = "AI-Gauge-Setup.exe"
$silent = ($env:AIGAUGE_SILENT -eq "1")
$logFile = Join-Path $env:USERPROFILE ".config\UniversalAIQuota\update.log"

if ($env:AIGAUGE_BASE_URL) {
    $baseUrl = $env:AIGAUGE_BASE_URL.TrimEnd('/')
} elseif ($env:AIGAUGE_VERSION) {
    $baseUrl = "https://github.com/vh2c/ai-gauge/releases/download/$($env:AIGAUGE_VERSION)"
} else {
    $baseUrl = "https://github.com/vh2c/ai-gauge/releases/latest/download"
}

Write-Host ""
Write-Host "AI Gauge installer for Windows" -ForegroundColor Cyan
Write-Host ""

if ($env:OS -ne "Windows_NT") {
    Write-Host "This installer is for Windows. See https://github.com/vh2c/ai-gauge/blob/main/INSTALL.md for macOS and Linux." -ForegroundColor Red
    return
}

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("aigauge-install-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
$exePath = Join-Path $tmp $exeName
$sumsPath = Join-Path $tmp "SHA256SUMS.txt"

try {
    Write-Host "Downloading $exeName (about 27 MB) ..."
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$exeName" -OutFile $exePath
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/SHA256SUMS.txt" -OutFile $sumsPath

    $expected = $null
    foreach ($line in (Get-Content $sumsPath)) {
        $parts = $line.Trim() -split '\s+', 2
        if ($parts.Count -eq 2 -and ($parts[1].TrimStart('*') -eq $exeName)) { $expected = $parts[0].ToLower(); break }
    }
    if (-not $expected) { throw "SHA256SUMS.txt has no entry for $exeName. Nothing was run." }

    $actual = (Get-FileHash -Path $exePath -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $expected) {
        throw "Checksum does not match. Expected $expected, got $actual. Nothing was run."
    }
    Write-Host "Checksum verified (SHA-256)." -ForegroundColor Green

    Write-Host "Starting the installer ..."
    if ($silent) {
        # Called from the app: install without the wizard (the installer closes the running AI Gauge), then reopen it
        $proc = Start-Process -FilePath $exePath -ArgumentList @("/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART") -Wait -PassThru
        if ($proc.ExitCode -ne 0) { throw "The installer exited with code $($proc.ExitCode)." }
        $vbs = Join-Path $env:LOCALAPPDATA "AIGauge\AIGauge.vbs"
        if (Test-Path $vbs) { Start-Process -FilePath "wscript.exe" -ArgumentList ('"' + $vbs + '"') }
    } else {
        Start-Process -FilePath $exePath -Wait
    }
    Write-Host ""
    Write-Host "Done. To update later, run the same command again." -ForegroundColor Green
}
catch {
    Write-Host ""
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($silent) {
        # No console is visible when started from the app: keep a log and tell the user
        try {
            New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null
            Add-Content -Path $logFile -Value ("[{0}] {1}" -f (Get-Date -Format "s"), $_.Exception.Message) -Encoding UTF8
        } catch {}
        try {
            Add-Type -AssemblyName PresentationFramework
            [System.Windows.MessageBox]::Show("The update could not be completed:`n`n$($_.Exception.Message)`n`nYour current version was kept. You can download the new version from https://github.com/vh2c/ai-gauge/releases/latest", "AI Gauge update", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning) | Out-Null
        } catch {}
    }
}
finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
