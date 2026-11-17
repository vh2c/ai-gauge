# AI Gauge Windows Installer
# Developed by VH2C • https://vh2c.com.br

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " ⚡ AI Gauge - Instalador Windows (VH2C)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""

# Target Directory: %LOCALAPPDATA%\GeminiGauge
$TargetDir = Join-Path $env:LOCALAPPDATA "GeminiGauge"
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir

# ----------------------------------------------------
# 1. SCAN DE APLICATIVOS DE IA INSTALADOS
# ----------------------------------------------------
Write-Host "🔍 Escaneando aplicativos e sessões de IA no computador..." -ForegroundColor Cyan

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

Write-Host "  [1] ⚡ Antigravity:       $(if ($HasAnti) {'✓ Detectado no sistema'} else {'○ Não detectado (opcional)'})" -ForegroundColor $(if ($HasAnti) {'Green'} else {'Gray'})
Write-Host "  [2] 🟣 Claude (Pro/Code): $(if ($HasClaude) {'✓ Sessão / Token detectado'} else {'○ Não detectado (opcional)'})" -ForegroundColor $(if ($HasClaude) {'Green'} else {'Gray'})
Write-Host "  [3] 🟢 ChatGPT (Desktop): $(if ($HasChatGPT) {'✓ Sessão Desktop / Codex detectada'} else {'○ Não detectado (opcional)'})" -ForegroundColor $(if ($HasChatGPT) {'Green'} else {'Gray'})
Write-Host "  [4] 🔮 Cursor (IDE):      $(if ($HasCursor) {'✓ Detectado no sistema'} else {'○ Não detectado (opcional)'})" -ForegroundColor $(if ($HasCursor) {'Green'} else {'Gray'})
Write-Host "  [5] 🔴 Copilot (VS Code): $(if ($HasCopilot) {'✓ Detectado (VS Code)'} else {'○ Não detectado (opcional)'})" -ForegroundColor $(if ($HasCopilot) {'Green'} else {'Gray'})
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
    Write-Host "📋 Quais quotas você deseja monitorar no seu AI Gauge?" -ForegroundColor Yellow
    Write-Host "   Pressione ENTER para monitorar todos os detectados [Recomendado]," -ForegroundColor Gray
    Write-Host "   ou digite os números desejados separados por vírgula (ex: 1,2,3):" -ForegroundColor Gray
    $UserChoice = Read-Host "   Sua escolha [Padrão: Detectados]"
    
    if (-not [string]::IsNullOrWhiteSpace($UserChoice)) {
        $EnableAnti = $UserChoice -match "1"
        $EnableClaude = $UserChoice -match "2"
        $EnableChatGPT = $UserChoice -match "3"
        $EnableCursor = $UserChoice -match "4"
        $EnableCopilot = $UserChoice -match "5"
        $EnableGemini = $UserChoice -match "6"
    }
    Write-Host ""
    Write-Host "💡 Informação: Você poderá adicionar ou excluir itens a qualquer momento depois no menu de configurações do app." -ForegroundColor Cyan
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
    Write-Host "✅ Configuração inicial gravada com sucesso em ~/.config/UniversalAIQuota/config.json!" -ForegroundColor Green
}

# ----------------------------------------------------
# 2. VERIFICAÇÃO DE DEPENDÊNCIAS
# ----------------------------------------------------
$NodeCmd = Get-Command "node.exe" -ErrorAction SilentlyContinue
if (-not $NodeCmd) {
    Write-Host "⚠️  Node.js (v18+) não foi detectado no sistema." -ForegroundColor Yellow
    Write-Host "   O AI Gauge precisa do Node.js para agregar as cotas." -ForegroundColor Yellow
    Write-Host "   Baixe e instale gratuitamente em: https://nodejs.org" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "✅ Node.js detectado: $(& node -v)" -ForegroundColor Green
}

# ----------------------------------------------------
# 3. INSTALAÇÃO DOS ARQUIVOS
# ----------------------------------------------------
Write-Host "📦 Instalando arquivos em $TargetDir..." -ForegroundColor Gray
Copy-Item -Path (Join-Path $RepoDir "core") -Destination $TargetDir -Recurse -Force
Copy-Item -Path (Join-Path $ScriptDir "*") -Destination $TargetDir -Recurse -Force

if (Test-Path (Join-Path $RepoDir "assets\icon.ico")) {
    Copy-Item -Path (Join-Path $RepoDir "assets\icon.ico") -Destination (Join-Path $TargetDir "icon.ico") -Force
}

$WshShell = New-Object -ComObject WScript.Shell
$IconPath = Join-Path $TargetDir "icon.ico"

$targetVbs = if (Test-Path (Join-Path $TargetDir "AIGauge.vbs")) { "$TargetDir\AIGauge.vbs" } else { "$TargetDir\GeminiGauge.vbs" }

# 1. Desktop Shortcut
$DesktopDir = [Environment]::GetFolderPath("Desktop")
$DesktopShortcut = $WshShell.CreateShortcut((Join-Path $DesktopDir "AI Gauge.lnk"))
$DesktopShortcut.TargetPath = "wscript.exe"
$DesktopShortcut.Arguments = "`"$targetVbs`""
$DesktopShortcut.WorkingDirectory = $TargetDir
$DesktopShortcut.IconLocation = "$IconPath,0"
$DesktopShortcut.Description = "AI Gauge - AI Quota & Rate Limit Monitor (VH2C)"
$DesktopShortcut.Save()

# 2. Start Menu Shortcut
$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$StartShortcut = $WshShell.CreateShortcut((Join-Path $StartMenuDir "AI Gauge.lnk"))
$StartShortcut.TargetPath = "wscript.exe"
$StartShortcut.Arguments = "`"$targetVbs`""
$StartShortcut.WorkingDirectory = $TargetDir
$StartShortcut.IconLocation = "$IconPath,0"
$StartShortcut.Description = "AI Gauge - AI Quota & Rate Limit Monitor (VH2C)"
$StartShortcut.Save()

Write-Host "✅ Atalhos criados com sucesso na Área de Trabalho e no Menu Iniciar!" -ForegroundColor Green
Write-Host "🚀 Iniciando o AI Gauge..." -ForegroundColor Cyan

Start-Process "wscript.exe" -ArgumentList "`"$targetVbs`""

Write-Host ""
Write-Host "🎉 Instalação concluída com sucesso!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
