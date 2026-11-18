# AI Gauge Windows Uninstaller
# Developed by VH2C • https://vh2c.com.br

Add-Type -AssemblyName PresentationFramework

$TargetDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $env:TEMP   # do not keep the install folder locked
$ConfigDir = Join-Path $env:USERPROFILE ".config\UniversalAIQuota"

$ask = [System.Windows.MessageBox]::Show("Deseja desinstalar o AI Gauge deste computador?", "Uninstall AI Gauge", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
if ($ask -ne [System.Windows.MessageBoxResult]::Yes) { exit 0 }

$removeCfg = [System.Windows.MessageBox]::Show("Also remove your settings (accounts, tokens and colors)?`n`nChoose 'No' to keep them in case you reinstall later.", "Uninstall AI Gauge", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)

# Close running instances
try {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'wscript.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'AIGauge\.(ps1|vbs)|GeminiGauge\.(ps1|vbs)|AntigravityQuotaHub' -and $_.ProcessId -ne $PID } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 600
} catch {}

# Shortcuts
$names = @("AI Gauge.lnk", "Uninstall AI Gauge.lnk", "Desinstalar AI Gauge.lnk")
$dirs = @([Environment]::GetFolderPath("Desktop"), (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"))
foreach ($d in $dirs) {
    foreach ($n in $names) {
        $f = Join-Path $d $n
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

# "Apps installed" entry
Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AIGauge" -Recurse -Force -ErrorAction SilentlyContinue

if ($removeCfg -eq [System.Windows.MessageBoxResult]::Yes) {
    Remove-Item $ConfigDir -Recurse -Force -ErrorAction SilentlyContinue
}

[System.Windows.MessageBox]::Show("AI Gauge foi desinstalado.", "AI Gauge", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null

# This script lives inside the install folder, so delete the folder after it exits
Start-Process -FilePath "cmd.exe" -ArgumentList "/c ping 127.0.0.1 -n 3 >nul & rmdir /s /q `"$TargetDir`"" -WindowStyle Hidden
