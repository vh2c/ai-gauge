# AI Gauge Windows Installer
# Developed by VH2C • https://vh2c.com.br

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " ⚡ AI Gauge - Windows Installer (VH2C)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""

# Target Directory: %LOCALAPPDATA%\AIGauge (older versions used ...\GeminiGauge)
$TargetDir = Join-Path $env:LOCALAPPDATA "AIGauge"
$LegacyDir = Join-Path $env:LOCALAPPDATA "GeminiGauge"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir

# ----------------------------------------------------
# 0. LIMPEZA DA VERSÃO ANTERIOR (upgrade limpo)
# ----------------------------------------------------
Write-Host "🧹 Checking for a previous version..." -ForegroundColor Cyan

# 0.1 Close any running AI Gauge instance (current or legacy names)
try {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'wscript.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'AIGauge\.(ps1|vbs)|GeminiGauge\.(ps1|vbs)|AntigravityQuotaHub' -and $_.ProcessId -ne $PID } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 600
} catch {}

# 0.2 Remove old shortcuts (current and legacy names)
$oldShortcutNames = @("AI Gauge.lnk", "Desinstalar AI Gauge.lnk", "Gemini Gauge.lnk", "Antigravity Quota Hub.lnk", "Universal AI Quota.lnk")
$shortcutDirs = @([Environment]::GetFolderPath("Desktop"), (Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"))
foreach ($d in $shortcutDirs) {
    foreach ($n in $oldShortcutNames) {
        $f = Join-Path $d $n
        if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

# 0.3 Reuse an already downloaded portable Node, then drop the legacy folder
if (-not (Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null }
$legacyNode = Join-Path $LegacyDir "bin\node.exe"
if ((Test-Path $legacyNode) -and -not (Test-Path (Join-Path $TargetDir "bin\node.exe"))) {
    New-Item -ItemType Directory -Path (Join-Path $TargetDir "bin") -Force | Out-Null
    Copy-Item $legacyNode (Join-Path $TargetDir "bin\node.exe") -Force
}
if ((Test-Path $LegacyDir) -and ($ScriptDir -notlike "$LegacyDir*")) {
    Remove-Item $LegacyDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "   ✓ Old version removed ($LegacyDir)" -ForegroundColor Green
}

# 0.4 Clean the current install folder (keeps bin\node.exe; your settings live elsewhere and are kept)
if ($ScriptDir -notlike "$TargetDir*") {
    Get-ChildItem -Path $TargetDir -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "bin" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""

# ----------------------------------------------------
# 1. SCAN DE APLICATIVOS DE IA INSTALADOS
# ----------------------------------------------------
Write-Host "🔍 Scanning for AI apps and sessions on this computer..." -ForegroundColor Cyan

$ConfigDir = Join-Path $env:USERPROFILE ".config\UniversalAIQuota"
$ConfigFile = Join-Path $ConfigDir "config.json"
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}

$HasAnti = $false
$HasClaude = $false
$HasChatGPT = $false
$HasCursor = $false
$HasCopilot = $false
$HasGemini = $false

# 1. Antigravity
if ((Get-Process "Antigravity" -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $env:USERPROFILE ".gemini\antigravity"))) {
    $HasAnti = $true
}

# 2. Claude
if ((Test-Path (Join-Path $env:USERPROFILE ".claude")) -or (Get-Command "claude.cmd" -ErrorAction SilentlyContinue) -or (Get-Command "claude.exe" -ErrorAction SilentlyContinue)) {
    $HasClaude = $true
}

# 3. ChatGPT
if ((Test-Path (Join-Path $env:USERPROFILE ".codex\auth.json")) -or (Test-Path (Join-Path $env:APPDATA "ChatGPT"))) {
    $HasChatGPT = $true
}

# 4. Cursor
if ((Test-Path (Join-Path $env:LOCALAPPDATA "Programs\cursor")) -or (Test-Path (Join-Path $env:APPDATA "Cursor")) -or (Get-Process "Cursor" -ErrorAction SilentlyContinue)) {
    $HasCursor = $true
}

# 5. GitHub Copilot (VS Code)
if ((Test-Path (Join-Path $env:APPDATA "Code\User\globalStorage\github.copilot-chat")) -or (Get-Command "gh.exe" -ErrorAction SilentlyContinue)) {
    $HasCopilot = $true
}

# 6. Gemini
if ($env:GEMINI_API_KEY) {
    $HasGemini = $true
}

Write-Host "  [1] ⚡ Antigravity:       $(if ($HasAnti) {'✓ Detected on this system'} else {'○ Not detected (optional)'})" -ForegroundColor $(if ($HasAnti) {'Green'} else {'Gray'})
Write-Host "  [2] 🟣 Claude (Pro/Code): $(if ($HasClaude) {'✓ Session / Token detected'} else {'○ Not detected (optional)'})" -ForegroundColor $(if ($HasClaude) {'Green'} else {'Gray'})
Write-Host "  [3] 🟢 ChatGPT (Desktop): $(if ($HasChatGPT) {'✓ Desktop Session / Codex detected'} else {'○ Not detected (optional)'})" -ForegroundColor $(if ($HasChatGPT) {'Green'} else {'Gray'})
Write-Host "  [4] 🔮 Cursor (IDE):      $(if ($HasCursor) {'✓ Detected on this system'} else {'○ Not detected (optional)'})" -ForegroundColor $(if ($HasCursor) {'Green'} else {'Gray'})
Write-Host "  [5] 🔴 Copilot (VS Code): $(if ($HasCopilot) {'✓ Detected (VS Code)'} else {'○ Not detected (optional)'})" -ForegroundColor $(if ($HasCopilot) {'Green'} else {'Gray'})
Write-Host "  [6] 🔷 Gemini (Studio):   $(if ($HasGemini) {'✓ Chave configurada'} else {'○ Chave de API (opcional)'})" -ForegroundColor $(if ($HasGemini) {'Green'} else {'Gray'})
Write-Host ""

$EnableAnti = $true
$EnableClaude = $HasClaude
$EnableChatGPT = $HasChatGPT
$EnableCursor = $HasCursor
$EnableCopilot = $HasCopilot
$EnableGemini = $HasGemini

# Check if interactive
$IsInteractive = [Environment]::UserInteractive
if ($IsInteractive -and ((-not (Test-Path $ConfigFile)) -or ($args -contains "--setup"))) {
    Write-Host "📋 Which quotas do you want to monitor in AI Gauge?" -ForegroundColor Yellow
    Write-Host "   Pressione ENTER para monitorar todos os detectados [Recomendado]," -ForegroundColor Gray
    Write-Host "   or type the numbers you want, separated by commas (e.g. 1,2,3):" -ForegroundColor Gray
    $UserChoice = Read-Host "   Your choice [Default: Detected]"
    
    if (-not [string]::IsNullOrWhiteSpace($UserChoice)) {
        $EnableAnti = $UserChoice -match "1"
        $EnableClaude = $UserChoice -match "2"
        $EnableChatGPT = $UserChoice -match "3"
        $EnableCursor = $UserChoice -match "4"
        $EnableCopilot = $UserChoice -match "5"
        $EnableGemini = $UserChoice -match "6"
    }
    Write-Host ""
    Write-Host "💡 Note: You can add or remove items at any time later in the app's settings menu." -ForegroundColor Cyan
    Write-Host ""
}

if ((-not (Test-Path $ConfigFile)) -or ($args -contains "--setup")) {
    $CfgObj = @{
        providers = @{
            antigravity = @{ enabled = [bool]$EnableAnti }
            claude_pro = @{ enabled = [bool]$EnableClaude }
            chatgpt_subscription = @{ enabled = [bool]$EnableChatGPT }
            cursor = @{ enabled = [bool]$EnableCursor }
            github_copilot = @{ enabled = [bool]$EnableCopilot }
            gemini = @{ enabled = [bool]$EnableGemini; api_key = if ($env:GEMINI_API_KEY) { $env:GEMINI_API_KEY } else { "" } }
            openai = @{ enabled = $false; api_key = "" }
            anthropic = @{ enabled = $false; api_key = "" }
        }
        refresh_interval_seconds = 30
        hidden_hud_gauges = @()
        onboarding_completed = $true
    }
    $CfgJson = $CfgObj | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($ConfigFile, $CfgJson, [Text.Encoding]::UTF8)
    try {
        $acl = Get-Acl -Path $ConfigFile
        $acl.SetAccessRuleProtection($true, $false)
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user, "FullControl", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl -Path $ConfigFile -AclObject $acl
    } catch {}
    Write-Host "✅ Initial configuration saved to ~/.config/UniversalAIQuota/config.json!" -ForegroundColor Green
}

# ----------------------------------------------------
# 2. INSTALAÇÃO DOS ARQUIVOS
# ----------------------------------------------------
Write-Host "📦 Installing files to $TargetDir..." -ForegroundColor Gray
Copy-Item -Path (Join-Path $RepoDir "core") -Destination $TargetDir -Recurse -Force
Copy-Item -Path (Join-Path $ScriptDir "*") -Destination $TargetDir -Recurse -Force

if (Test-Path (Join-Path $RepoDir "assets\icon.ico")) {
    Copy-Item -Path (Join-Path $RepoDir "assets\icon.ico") -Destination (Join-Path $TargetDir "icon.ico") -Force
}

# ----------------------------------------------------
# 3. NODE.JS PORTÁTIL (não exige instalação no sistema)
# ----------------------------------------------------
function Install-PortableNode ($DestDir) {
    $binDir = Join-Path $DestDir "bin"
    $nodeExe = Join-Path $binDir "node.exe"
    if (Test-Path $nodeExe) { return $true }

    Write-Host "⬇️  Downloading portable Node.js (one time only, ~30 MB)..." -ForegroundColor Cyan
    $tmp = Join-Path $env:TEMP ("aigauge_node_" + [guid]::NewGuid().ToString("N"))
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = "SilentlyContinue"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null

        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "win-arm64" } else { "win-x64" }
        $index = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -UseBasicParsing
        $rel = $index | Where-Object { $_.lts -and ($_.files -contains "$arch-zip") } | Select-Object -First 1
        if (-not $rel) { throw "No Node.js LTS version found for $arch" }
        $ver = $rel.version
        $zipName = "node-$ver-$arch.zip"
        $zipPath = Join-Path $tmp $zipName

        Invoke-WebRequest -Uri "https://nodejs.org/dist/$ver/$zipName" -OutFile $zipPath -UseBasicParsing
        $sums = (Invoke-WebRequest -Uri "https://nodejs.org/dist/$ver/SHASUMS256.txt" -UseBasicParsing).Content
        $expected = ($sums -split "`n" | Where-Object { $_ -match [regex]::Escape($zipName) } | Select-Object -First 1) -split "\s+" | Select-Object -First 1
        $actual = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
        if (-not $expected -or ($expected.ToLower() -ne $actual.ToLower())) { throw "Node.js SHA-256 verification failed" }

        Expand-Archive -Path $zipPath -DestinationPath $tmp -Force
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        Copy-Item -Path (Join-Path $tmp "node-$ver-$arch\node.exe") -Destination $nodeExe -Force
        Write-Host "✅ Node.js $ver instalado em $binDir" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "⚠️  Could not fetch Node.js automatically: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   AI Gauge will open and show a button to download Node.js manually." -ForegroundColor Yellow
        return $false
    } finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (Test-Path (Join-Path $TargetDir "bin\node.exe")) {
    Write-Host "✅ Node.js embutido encontrado." -ForegroundColor Green
} else {
    Install-PortableNode $TargetDir | Out-Null
}

$WshShell = New-Object -ComObject WScript.Shell
$IconPath = Join-Path $TargetDir "icon.ico"

$targetVbs = if (Test-Path (Join-Path $TargetDir "AIGauge.vbs")) { "$TargetDir\AIGauge.vbs" } else { "$TargetDir\GeminiGauge.vbs" }

# 1. Desktop Shortcut (verified; falls back to %USERPROFILE%\Desktop if the shell folder fails)
function New-AppShortcut ($lnkPath) {
    $sc = $WshShell.CreateShortcut($lnkPath)
    $sc.TargetPath = "wscript.exe"
    $sc.Arguments = "`"$targetVbs`""
    $sc.WorkingDirectory = $TargetDir
    $sc.IconLocation = "$IconPath,0"
    $sc.Description = "AI Gauge - AI Quota & Rate Limit Monitor (VH2C)"
    $sc.Save()
    return (Test-Path $lnkPath)
}

$desktopOk = $false
$desktopCandidates = @([Environment]::GetFolderPath("DesktopDirectory"), (Join-Path $env:USERPROFILE "Desktop")) | Where-Object { $_ } | Select-Object -Unique
foreach ($dd in $desktopCandidates) {
    if ($desktopOk) { break }
    try {
        if (-not (Test-Path $dd)) { continue }
        $lnk = Join-Path $dd "AI Gauge.lnk"
        if (New-AppShortcut $lnk) {
            $desktopOk = $true
            Write-Host "✅ Desktop shortcut created: $lnk" -ForegroundColor Green
        }
    } catch {
        Write-Host "⚠️  Could not create the shortcut at ${dd}: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
if (-not $desktopOk) {
    Write-Host "⚠️  The Desktop shortcut was not created. Use Start Menu > AI Gauge." -ForegroundColor Yellow
}

# 2. Start Menu Shortcut
$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$StartShortcut = $WshShell.CreateShortcut((Join-Path $StartMenuDir "AI Gauge.lnk"))
$StartShortcut.TargetPath = "wscript.exe"
$StartShortcut.Arguments = "`"$targetVbs`""
$StartShortcut.WorkingDirectory = $TargetDir
$StartShortcut.IconLocation = "$IconPath,0"
$StartShortcut.Description = "AI Gauge - AI Quota & Rate Limit Monitor (VH2C)"
$StartShortcut.Save()

# 3. Uninstall shortcut + entry in Windows "Apps installed" (per-user, no admin needed)
$UninstallPs1 = Join-Path $TargetDir "uninstall.ps1"
if (Test-Path $UninstallPs1) {
    $UninstShortcut = $WshShell.CreateShortcut((Join-Path $StartMenuDir "Uninstall AI Gauge.lnk"))
    $UninstShortcut.TargetPath = "powershell.exe"
    $UninstShortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$UninstallPs1`""
    $UninstShortcut.WorkingDirectory = $TargetDir
    $UninstShortcut.IconLocation = "$IconPath,0"
    $UninstShortcut.Save()

    try {
        $uk = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\AIGauge"
        New-Item -Path $uk -Force | Out-Null
        Set-ItemProperty -Path $uk -Name "DisplayName" -Value "AI Gauge"
        Set-ItemProperty -Path $uk -Name "DisplayVersion" -Value "1.1"
        Set-ItemProperty -Path $uk -Name "Publisher" -Value "VH2C"
        Set-ItemProperty -Path $uk -Name "DisplayIcon" -Value $IconPath
        Set-ItemProperty -Path $uk -Name "InstallLocation" -Value $TargetDir
        Set-ItemProperty -Path $uk -Name "UninstallString" -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$UninstallPs1`""
        Set-ItemProperty -Path $uk -Name "NoModify" -Value 1 -Type DWord
        Set-ItemProperty -Path $uk -Name "NoRepair" -Value 1 -Type DWord
    } catch {}
}

Write-Host "✅ Start Menu shortcut created!" -ForegroundColor Green
Write-Host "🚀 Iniciando o AI Gauge..." -ForegroundColor Cyan

Start-Process "wscript.exe" -ArgumentList "`"$targetVbs`""

Write-Host ""
Write-Host "🎉 Installation completed successfully!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
