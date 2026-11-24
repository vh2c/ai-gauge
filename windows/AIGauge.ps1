<#
.SYNOPSIS
    AI Gauge - Windows Edition (PowerShell + WPF)
    Developed by VH2C • https://vh2c.com.br
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Set AppUserModelID so Windows Taskbar identifies AI Gauge with its own icon
try {
    $typeDef = @"
using System;
using System.Runtime.InteropServices;
public class Win32AppId {
    [DllImport("shell32.dll", SetLastError = true)]
    public static extern void SetCurrentProcessExplicitAppUserModelID([MarshalAs(UnmanagedType.LPWStr)] string AppID);
}
"@
    Add-Type -TypeDefinition $typeDef -ErrorAction SilentlyContinue
    [Win32AppId]::SetCurrentProcessExplicitAppUserModelID("VH2C.AIGauge.Cockpit.1.1")
} catch {}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

# Ensure TLS 1.2+ on Windows PowerShell 5.1 (.NET Framework 4.x) so HTTPS promo images & API calls succeed
try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
} catch {}

function Get-UnixSeconds {
    return [int64]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
}

trap {
    try {
        $err = $_.Exception.ToString()
        $logPath = Join-Path $env:TEMP "ai_gauge_error.log"
        Set-Content -Path $logPath -Value $err -Encoding UTF8 -Force
        [System.Windows.MessageBox]::Show("An error occurred while running AI Gauge:`n`n$($_.Exception.Message)`n`nLog file saved to:`n$logPath", "AI Gauge - Error", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    } catch {}
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$EngineScript = Join-Path $ScriptDir "core\engine.js"
if (-not (Test-Path $EngineScript)) {
    $EngineScript = Join-Path $RepoDir "core\engine.js"
}

$global:AppVersion = "1.2.0"
$updaterCandidates = @(
    (Join-Path $ScriptDir "core\updater.js"),
    (Join-Path $RepoDir "core\updater.js")
)
foreach ($u in $updaterCandidates) {
    if (Test-Path $u) {
        try {
            $uContent = Get-Content $u -Raw
            if ($uContent -match "CURRENT_VERSION\s*=\s*['""]([^'""]+)['""]") {
                $global:AppVersion = $matches[1]
                break
            }
        } catch {}
    }
}

# Demo mode (--demo): fictitious accounts, isolated config, no Node, no telemetry.
$DemoMode = ($args -contains "--demo")

$ConfigDir = Join-Path $env:USERPROFILE ".config\UniversalAIQuota"
if ($DemoMode) { $ConfigDir = Join-Path $env:TEMP "AIGaugeDemo" }
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}
function Write-Utf8NoBom ($path, $content) {
    [System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
}

$ConfigFile = Join-Path $ConfigDir "config.json"
if ($DemoMode -and -not (Test-Path $ConfigFile)) {
    Write-Utf8NoBom $ConfigFile '{"providers":{},"hidden_hud_gauges":[],"onboarding_completed":true}'
}
$DeviceIdFile = Join-Path $ConfigDir "device_id"

# First run without config (e.g. installed via Setup.exe): write a starter config with local auto-discovery enabled.
function Initialize-DefaultConfig {
    $up = $env:USERPROFILE
    $localApp = $env:LOCALAPPDATA
    $appData = $env:APPDATA
    $progFiles = $env:ProgramFiles
    $hasClaude = (Test-Path (Join-Path $up ".claude")) -or [bool](Get-Command "claude.cmd" -ErrorAction SilentlyContinue) -or [bool](Get-Command "claude.exe" -ErrorAction SilentlyContinue)
    $hasChatGPT = (Test-Path (Join-Path $up ".codex\auth.json")) -or ($appData -and (Test-Path (Join-Path $appData "ChatGPT")))
    $hasCursor = ($localApp -and (Test-Path (Join-Path $localApp "Programs\cursor"))) -or ($localApp -and (Test-Path (Join-Path $localApp "Programs\Cursor"))) -or ($localApp -and (Test-Path (Join-Path $localApp "cursor"))) -or ($progFiles -and (Test-Path (Join-Path $progFiles "Cursor"))) -or ($appData -and (Test-Path (Join-Path $appData "Cursor"))) -or [bool](Get-Process "Cursor" -ErrorAction SilentlyContinue)
    $hasCopilot = ($appData -and (Test-Path (Join-Path $appData "Code\User\globalStorage\github.copilot-chat"))) -or [bool](Get-Command "gh.exe" -ErrorAction SilentlyContinue)
    $hasGemini = [bool]$env:GEMINI_API_KEY
    $hasAnti = [bool](Get-Process "Antigravity" -ErrorAction SilentlyContinue) -or [bool](Get-Process "language_server*" -ErrorAction SilentlyContinue) -or (Test-Path (Join-Path $up ".gemini\antigravity")) -or ($localApp -and (Test-Path (Join-Path $localApp "Programs\Antigravity"))) -or ($progFiles -and (Test-Path (Join-Path $progFiles "Antigravity")))

    if (Test-Path $ConfigFile) {
        try {
            $raw = (Get-Content $ConfigFile -Raw -Encoding UTF8).TrimStart([char]0xFEFF)
            $existing = $raw | ConvertFrom-Json
            if ($existing -and $existing.providers) {
                $dirty = $false
                if ($hasAnti -and ($null -eq $existing.providers.antigravity -or $existing.providers.antigravity.enabled -ne $true)) {
                    if (-not $existing.providers.antigravity) {
                        $existing.providers | Add-Member -MemberType NoteProperty -Name "antigravity" -Value (@{ enabled = $true }) -Force
                    } else {
                        $existing.providers.antigravity.enabled = $true
                    }
                    $dirty = $true
                }
                if ($hasCursor -and ($null -eq $existing.providers.cursor -or $existing.providers.cursor.enabled -ne $true)) {
                    if (-not $existing.providers.cursor) {
                        $existing.providers | Add-Member -MemberType NoteProperty -Name "cursor" -Value (@{ enabled = $true }) -Force
                    } else {
                        $existing.providers.cursor.enabled = $true
                    }
                    $dirty = $true
                }
                if ($dirty) {
                    Write-Utf8NoBom $ConfigFile ($existing | ConvertTo-Json -Depth 5)
                }
            }
        } catch {}
        return
    }
    try {
        # Names shown if any tool is found on startup
        $global:FirstRunDetected = @()
        if ($hasAnti) { $global:FirstRunDetected += "Antigravity" }
        if ($hasClaude) { $global:FirstRunDetected += "Claude" }
        if ($hasChatGPT) { $global:FirstRunDetected += "ChatGPT" }
        if ($hasCursor) { $global:FirstRunDetected += "Cursor" }
        if ($hasCopilot) { $global:FirstRunDetected += "GitHub Copilot" }
        if ($hasGemini) { $global:FirstRunDetected += "Gemini" }
        $cfg = @{
            providers = @{
                antigravity = @{ enabled = $true }
                claude_pro = @{ enabled = $true }
                chatgpt_subscription = @{ enabled = $true }
                cursor = @{ enabled = $true }
                github_copilot = @{ enabled = $true }
                gemini = @{ enabled = [bool]$hasGemini; api_key = if ($env:GEMINI_API_KEY) { $env:GEMINI_API_KEY } else { "" } }
                openai = @{ enabled = [bool]$env:OPENAI_API_KEY; api_key = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { "" } }
                anthropic = @{ enabled = [bool]$env:ANTHROPIC_API_KEY; api_key = if ($env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY } else { "" } }
            }
            refresh_interval_seconds = 30
            hidden_hud_gauges = @()
            onboarding_completed = $false
        }
        Write-Utf8NoBom $ConfigFile ($cfg | ConvertTo-Json -Depth 5)
        try {
            $acl = Get-Acl -Path $ConfigFile
            $acl.SetAccessRuleProtection($true, $false)
            $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($user, "FullControl", "Allow")))
            Set-Acl -Path $ConfigFile -AclObject $acl
        } catch {}
    } catch {}
}
Initialize-DefaultConfig

# 1. Curated 6 Pastel Colors (Yellow removed, 1:1 match with providers)
$PastelDefaults = @{
    "antigravity"          = "#8FBCFF"
    "claude_pro"           = "#D78C68"
    "chatgpt_subscription" = "#8AE39A"
    "cursor"               = "#C084FC"
    "github_copilot"       = "#FF5265"
    "gemini"               = "#67E8F9"
    "openai"               = "#8AE39A"
    "anthropic"            = "#D78C68"
}

$PastelPalette = @(
    @{ Name = "Sky Blue";   Hex = "#8FBCFF" },
    @{ Name = "Mint";       Hex = "#8AE39A" },
    @{ Name = "Coral";      Hex = "#FF5265" },
    @{ Name = "Terracotta"; Hex = "#D78C68" },
    @{ Name = "Lavender";   Hex = "#C084FC" },
    @{ Name = "Cyan";       Hex = "#67E8F9" }
)

function Convert-HexToColor ($hexStr) {
    try {
        if (-not $hexStr) { return [System.Windows.Media.Color]::FromRgb(0x8F, 0xBC, 0xFF) }
        $clean = $hexStr.Trim().TrimStart('#')
        if ($clean.Length -eq 6) {
            $r = [Convert]::ToByte($clean.Substring(0, 2), 16)
            $g = [Convert]::ToByte($clean.Substring(2, 2), 16)
            $b = [Convert]::ToByte($clean.Substring(4, 2), 16)
            return [System.Windows.Media.Color]::FromRgb($r, $g, $b)
        }
    } catch {}
    return [System.Windows.Media.Color]::FromRgb(0x8F, 0xBC, 0xFF)
}

function Convert-HexToBrush ($hexStr) {
    return (New-Object System.Windows.Media.SolidColorBrush (Convert-HexToColor $hexStr))
}

function Get-ProviderActivity ($data, $provKey) {
    if (-not $data) { return $null }
    if ($data.activity -and $data.activity.providers) {
        $pMap = $data.activity.providers
        if ($pMap -is [System.Collections.IDictionary]) {
            if ($pMap.Contains($provKey)) { return $pMap[$provKey] }
        } else {
            $prop = $pMap.PSObject.Properties[$provKey]
            if ($prop) { return $prop.Value }
        }
    }
    if ($data.groups) {
        foreach ($g in $data.groups) {
            $gk = Get-ProviderKey $g.name $g.provider
            if ($gk -eq $provKey -and $g.activity) { return $g.activity }
        }
    }
    return $null
}

function Get-EffectivePollSeconds ($data) {
    if ($data) {
        if ($data.activity -and $data.activity.recommended_poll_seconds) {
            return [int]$data.activity.recommended_poll_seconds
        }
        if ($data.recommended_poll_seconds) {
            return [int]$data.recommended_poll_seconds
        }
    }
    return 30
}

function Get-ActivityFingerprint ($act) {
    if (-not $act) { return "" }
    $parts = New-Object System.Collections.ArrayList
    [void]$parts.Add("$($act.overall_status)")
    [void]$parts.Add("$($act.recommended_poll_seconds)")
    if ($act.providers) {
        foreach ($k in @("antigravity", "claude_pro", "chatgpt_subscription", "cursor", "github_copilot")) {
            $item = $null
            if ($act.providers -is [System.Collections.IDictionary]) {
                if ($act.providers.Contains($k)) { $item = $act.providers[$k] }
            } else {
                $p = $act.providers.PSObject.Properties[$k]
                if ($p) { $item = $p.Value }
            }
            if ($item) {
                [void]$parts.Add("${k}:$($item.status):$($item.detail)")
            }
        }
    }
    return ($parts -join "|")
}

function Get-ActivityTooltip ($title, $act, $pollSecs) {
    $st = if ($act -and $act.status) { "$($act.status)" } else { "idle" }
    $statusText = if ($st -eq "working") { "Working" } elseif ($st -eq "waiting") { "Waiting for input" } else { "Idle" }
    $pollLabel = if ($pollSecs -ge 300) { "5 min (idle)" } else { "${pollSecs}s (active)" }
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add("$title · $statusText")
    if ($act -and $act.detail) {
        [void]$lines.Add("$($act.detail)")
    } elseif ($act -and $act.project) {
        [void]$lines.Add("Project: $($act.project)")
    }
    if ($act -and $null -ne $act.age_seconds -and $st -ne "idle") {
        [void]$lines.Add("Updated $($act.age_seconds)s ago · Polling: $pollLabel")
    } else {
        [void]$lines.Add("Polling: $pollLabel")
    }
    return ($lines -join "`n")
}

function New-ActivityGlyph ($status, $accentHex, $size = 9) {
    $cv = New-Object System.Windows.Controls.Canvas
    $cv.Width = $size
    $cv.Height = $size
    $cv.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $cx = $size / 2.0
    $cy = $size / 2.0
    $r = [Math]::Max(2.5, ($size / 2.0) - 1.2)

    if ($status -eq "working") {
        $track = New-Object System.Windows.Shapes.Ellipse
        $track.Width = $r * 2
        $track.Height = $r * 2
        $trBrush = Convert-HexToBrush $accentHex
        $trBrush.Opacity = 0.24
        $track.Stroke = $trBrush
        $track.StrokeThickness = 1.4
        [System.Windows.Controls.Canvas]::SetLeft($track, $cx - $r)
        [System.Windows.Controls.Canvas]::SetTop($track, $cy - $r)
        $cv.Children.Add($track) | Out-Null

        $arcStr = Get-ArcGeometry $cx $cy $r 0 140
        if ($arcStr) {
            $arc = New-Object System.Windows.Shapes.Path
            $arc.Data = [System.Windows.Media.Geometry]::Parse($arcStr)
            $arc.Stroke = Convert-HexToBrush $accentHex
            $arc.StrokeThickness = 1.6
            $arc.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
            $arc.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
            $rot = New-Object System.Windows.Media.RotateTransform
            $rot.CenterX = $cx
            $rot.CenterY = $cy
            $arc.RenderTransform = $rot
            $anim = New-Object System.Windows.Media.Animation.DoubleAnimation(0, 360, [TimeSpan]::FromSeconds(1.1))
            $anim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $rot.BeginAnimation([System.Windows.Media.RotateTransform]::AngleProperty, $anim)
            $cv.Children.Add($arc) | Out-Null
        }
    } elseif ($status -eq "waiting") {
        $ring = New-Object System.Windows.Shapes.Ellipse
        $ring.Width = $size - 1
        $ring.Height = $size - 1
        $ringBrush = Convert-HexToBrush "#F5A623"
        $ring.Stroke = $ringBrush
        $ring.StrokeThickness = 1.2
        [System.Windows.Controls.Canvas]::SetLeft($ring, 0.5)
        [System.Windows.Controls.Canvas]::SetTop($ring, 0.5)
        $pulseAnim = New-Object System.Windows.Media.Animation.DoubleAnimation(0.9, 0.15, [TimeSpan]::FromSeconds(0.8))
        $pulseAnim.AutoReverse = $true
        $pulseAnim.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
        $ring.BeginAnimation([System.Windows.UIElement]::OpacityProperty, $pulseAnim)
        $cv.Children.Add($ring) | Out-Null

        $dotR = [Math]::Max(2.0, $r * 0.62)
        $dot = New-Object System.Windows.Shapes.Ellipse
        $dot.Width = $dotR * 2
        $dot.Height = $dotR * 2
        $dot.Fill = Convert-HexToBrush "#F5A623"
        [System.Windows.Controls.Canvas]::SetLeft($dot, $cx - $dotR)
        [System.Windows.Controls.Canvas]::SetTop($dot, $cy - $dotR)
        $cv.Children.Add($dot) | Out-Null
    } else {
        $idleR = [Math]::Max(2.0, $r * 0.68)
        $circle = New-Object System.Windows.Shapes.Ellipse
        $circle.Width = $idleR * 2
        $circle.Height = $idleR * 2
        $circle.Stroke = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(190, 0x7A, 0x7A, 0x86))
        $circle.StrokeThickness = 1.2
        [System.Windows.Controls.Canvas]::SetLeft($circle, $cx - $idleR)
        [System.Windows.Controls.Canvas]::SetTop($circle, $cy - $idleR)
        $cv.Children.Add($circle) | Out-Null
    }
    return $cv
}

function Load-CurrentConfig {
    if (Test-Path $ConfigFile) {
        try {
            $raw = (Get-Content $ConfigFile -Raw -Encoding UTF8).TrimStart([char]0xFEFF)
            return ($raw | ConvertFrom-Json)
        } catch {}
    }
    return $null
}

function Get-ProviderKey ($groupName, $providerName) {
    $gn = "$groupName".ToLower()
    $pn = "$providerName".ToLower()
    if ($pn.Contains("antigravity") -or $gn.Contains("antigravity") -or $gn.Contains("claude and gpt") -or $gn.Contains("argon")) { return "antigravity" }
    if ($pn.Contains("cursor") -or $gn.Contains("cursor")) { return "cursor" }
    if ($pn.Contains("copilot") -or $gn.Contains("copilot") -or $pn.Contains("github")) { return "github_copilot" }
    if ($pn.Contains("chatgpt") -or $gn.Contains("chatgpt")) { return "chatgpt_subscription" }
    if ($pn.Contains("claude") -or $gn.Contains("claude")) { return "claude_pro" }
    if ($pn.Contains("studio") -or $gn.Contains("gemini") -or $pn.Contains("gemini")) { return "gemini" }
    if ($pn.Contains("openai") -or $gn.Contains("openai")) { return "openai" }
    if ($pn.Contains("anthropic") -or $gn.Contains("anthropic")) { return "anthropic" }
    return "antigravity"
}

function Get-GroupColorHex ($groupName, $providerName) {
    $cfg = Load-CurrentConfig
    $key = Get-ProviderKey $groupName $providerName
    if ($cfg -and $cfg.section_colors -and $cfg.section_colors.$key) {
        return "$($cfg.section_colors.$key)"
    }
    if ($PastelDefaults.ContainsKey($key)) {
        return $PastelDefaults[$key]
    }
    return "#8FBCFF"
}

function Get-StatusBrush ($pct, $accentHex) {
    if ($pct -le 15) {
        return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xFF, 0x4D, 0x4F)))
    }
    if ($pct -le 30) {
        return (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF5, 0xA6, 0x23)))
    }
    return (Convert-HexToBrush $accentHex)
}

function Get-ArcGeometry ($cx, $cy, $r, $startDeg, $sweepDeg) {
    if ($sweepDeg -le 0.5) { return "" }
    if ($sweepDeg -ge 360) { $sweepDeg = 359.99 }
    
    $startRad = [Math]::PI * $startDeg / 180.0
    $endRad   = [Math]::PI * ($startDeg + $sweepDeg) / 180.0
    
    $x1 = [Math]::Round($cx + $r * [Math]::Cos($startRad), 2)
    $y1 = [Math]::Round($cy + $r * [Math]::Sin($startRad), 2)
    $x2 = [Math]::Round($cx + $r * [Math]::Cos($endRad), 2)
    $y2 = [Math]::Round($cy + $r * [Math]::Sin($endRad), 2)
    
    $isLarge = if ($sweepDeg -gt 180) { 1 } else { 0 }
    
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "M {0},{1} A {2},{2} 0 {3} 1 {4},{5}", $x1, $y1, $r, $isLarge, $x2, $y2)
}

function Get-NeedleGeometry ($cx, $cy, $r, $pct, $startDeg = 140, $sweepDeg = 260) {
    $pClamped = [Math]::Min([Math]::Max($pct, 0), 100)
    $angDeg = $startDeg + ($pClamped / 100.0) * $sweepDeg
    $angRad = $angDeg * [Math]::PI / 180.0
    
    $tipLen = $r - 4.5
    $tipX = [Math]::Round($cx + $tipLen * [Math]::Cos($angRad), 2)
    $tipY = [Math]::Round($cy + $tipLen * [Math]::Sin($angRad), 2)
    
    $baseR = 2.2
    $b1Rad = $angRad + ([Math]::PI / 2.0)
    $b2Rad = $angRad - ([Math]::PI / 2.0)
    $b1X = [Math]::Round($cx + $baseR * [Math]::Cos($b1Rad), 2)
    $b1Y = [Math]::Round($cy + $baseR * [Math]::Sin($b1Rad), 2)
    $b2X = [Math]::Round($cx + $baseR * [Math]::Cos($b2Rad), 2)
    $b2Y = [Math]::Round($cy + $baseR * [Math]::Sin($b2Rad), 2)
    
    return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "M {0},{1} L {2},{3} L {4},{5} Z", $b1X, $b1Y, $tipX, $tipY, $b2X, $b2Y)
}

function Get-BucketWindowLabel ($bucketName, $bucketId) {
    $n = ("$bucketName $bucketId").ToLower()
    if ($n.Contains("5h") -or $n.Contains("5 hour")) { return "5 HOURS LIMIT" }
    if ($n.Contains("3h") -or $n.Contains("3 hour")) { return "3 HOURS LIMIT" }
    if ($n.Contains("weekly") -or $n.Contains("7d") -or $n.Contains("semanal")) { return "WEEKLY LIMIT" }
    if ($n.Contains("month") -or $n.Contains("mensal") -or $n.Contains("ciclo")) { return "MONTHLY CYCLE" }
    if ($n.Contains("fast")) { return "FAST REQUESTS" }
    if ($n.Contains("rate") -or $n.Contains("rpm")) { return "RATE LIMIT" }
    if ($n.Contains("chat")) { return "CHAT LIMIT" }
    return "QUOTA LIMIT"
}

function Get-BucketModelName ($bucketName, $groupName) {
    $bn = "$bucketName".Trim()
    $gn = "$groupName".Trim()
    $bnLow = $bn.ToLower()
    $gnLow = $gn.ToLower()
    if (($bnLow.Contains("claude") -and $bnLow.Contains("gpt")) -or ($gnLow.Contains("claude") -and $gnLow.Contains("gpt"))) { return "Claude/GPT" }
    if ($bnLow.Contains("argon") -or $gnLow.Contains("argon")) { return "Argon" }
    if ($bnLow.Contains("gpt-4o")) { return "GPT-4o" }
    if ($bnLow.Contains("o1")) { return "o1 Reasoning" }
    if ($bnLow.Contains("gemini")) { return "Gemini" }
    if ($bnLow.Contains("claude")) { return "Claude" }
    if ($gnLow.Contains("gemini")) { return "Gemini" }
    if ($gnLow.Contains("claude")) { return "Claude" }
    if ($gnLow.Contains("chatgpt")) { return "ChatGPT" }
    if ($gnLow.Contains("cursor")) { return "Cursor" }
    if ($gnLow.Contains("copilot")) { return "Copilot" }
    if ($gnLow.Contains("openai")) { return "OpenAI" }
    if ($gnLow.Contains("anthropic")) { return "Anthropic" }
    
    $clean = $bn -replace '(?i)\b(Weekly|Limit|Remaining|Five|Hour|Hours|5h|3h|7d)\b', ''
    $clean = $clean.Trim()
    if ($clean.Length -gt 0) { return $clean }
    return $bn
}

function Get-SectionCleanTitle ($provKey, $fallbackName) {
    switch ($provKey) {
        "antigravity"          { return "Antigravity" }
        "claude_pro"           { return "Claude" }
        "chatgpt_subscription" { return "ChatGPT" }
        "cursor"               { return "Cursor" }
        "github_copilot"       { return "Copilot" }
        "gemini"               { return "Gemini" }
        "openai"               { return "OpenAI" }
        "anthropic"            { return "Anthropic" }
        default                { return "$fallbackName" }
    }
}

# 2. Telemetry: sent only by the Node engine (core/telemetry.js), which also caches the
#    update/announcement data returned by the API. A second PowerShell heartbeat used to consume
#    the 6h throttle and discard the announcement, so it was removed.

# 3. Find Node binary (bundled copy first, so the app works without a system Node.js)
function Find-NodeBinary {
    $localNode = Join-Path $ScriptDir "bin\node.exe"
    if (Test-Path $localNode) { return $localNode }
    $cmd = Get-Command "node.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$NodeExe = Find-NodeBinary

function Write-AppError ($ex) {
    try {
        $logPath = Join-Path $env:TEMP "ai_gauge_error.log"
        Add-Content -Path $logPath -Value ("[{0}] {1}" -f (Get-Date -Format "s"), $ex.ToString()) -Encoding UTF8
    } catch {}
}

function New-NodeMissingData {
    return @{
        account = "Node.js not detected"
        plan = "Installation Required"
        updated_at = (Get-Date -Format "HH:mm:ss")
        groups = @()
        node_missing = $true
    }
}

# Asynchronous engine runner: the UI thread never blocks while node.exe collects quotas.
$global:quotaFetch = $null
$global:initialLoad = $true

function New-DemoData {
    function B ($id, $name, $pct, $reset) { return @{ id = $id; name = $name; remaining_pct = $pct; reset_in = $reset } }
    return @{
        account = "demo@aigauge.test  (MODO DEMO)"
        plan = "DEMO"
        updated_at = (Get-Date -Format "HH:mm:ss")
        tier = "free"
        recommended_poll_seconds = 30
        activity = @{
            overall_status = "waiting"
            active_count = 2
            working_count = 1
            waiting_count = 1
            recommended_poll_seconds = 30
            providers = @{
                antigravity = @{ status = "waiting"; sessions_count = 1; project = "ai_gauge"; summary = "Waiting for your response"; detail = "ai_gauge · Waiting for your response"; age_seconds = 14 }
                claude_pro = @{ status = "working"; sessions_count = 1; project = "ai_gauge"; summary = "Running Bash"; detail = "ai_gauge · Running Bash"; age_seconds = 3 }
                chatgpt_subscription = @{ status = "idle"; sessions_count = 0; project = "Codex"; summary = "Idle"; detail = ""; age_seconds = 940 }
                cursor = @{ status = "idle"; sessions_count = 0; project = "Cursor IDE"; summary = "Idle"; detail = ""; age_seconds = $null }
            }
        }
        # Two independent components (like the real API): `announcement` = version notice banner, `promo` = ad toast
        announcement = @{
            type = "versao"
            title = "Version 2.1 Available"
            message = "Download the latest version now."
            action_label = "Download Update"
            action_url = "https://github.com/vh2c/ai-gauge/releases/latest"
        }
        # Same shape/values the real API sends for the "Super Offer" ad: image, no action link, no countdown
        promo = @{
            type = "publicidade"
            title = "Super Offer"
            message = "Today only: get your PRO license for just R$ 10.00"
            action_label = $null
            action_url = $null
            image_url = "https://dashboard.vh2c.com.br/uploads/ads/ad_20261116_144942_2f64117f.jpg"
            image_fit = "cover"
            image_position = "center"
            image_scale = 1.05
            duracao_segundos = $null
        }
        groups = @(
            @{ name = "Antigravity"; provider = "Antigravity (Live)"; buckets = @(
                (B "demo-ag-gemini-weekly" "Gemini Weekly Limit Remaining" 43 "4d 1h"),
                (B "demo-ag-gemini-5h" "Gemini Five Hour Limit Remaining" 98 "4h 51m"),
                (B "demo-ag-argon-weekly" "Argon Weekly Limit Remaining" 27 "4d 1h")) },
            @{ name = "Claude Pro"; provider = "Claude Pro"; buckets = @(
                (B "demo-claude-5h" "Claude 5 Hour Limit" 84 "4h 27m"),
                (B "demo-claude-weekly" "Claude Weekly Limit" 82 "2d 18h")) },
            @{ name = "ChatGPT Plus"; provider = "ChatGPT"; buckets = @(
                (B "demo-gpt4o-3h" "GPT-4o 3 Hour Limit" 100 "29d 23h"),
                (B "demo-o1-weekly" "o1 Reasoning Weekly" 100 "7d")) },
            @{ name = "Cursor"; provider = "Cursor"; buckets = @(
                (B "demo-cursor-fast" "Fast Requests (Claude)" 64 "14d"),
                (B "demo-cursor-month" "Monthly Billing Cycle" 12 "14d")) }
        )
    }
}

$global:lastFetchWasScan = $false
$global:scanEmptyNotice = $false

function Start-QuotaFetch ($force = $false, $scan = $false) {
    if ($global:quotaFetch) { return }
    if ($DemoMode) {
        Complete-QuotaFetch (New-DemoData)
        return
    }
    if (-not $NodeExe) {
        Complete-QuotaFetch (New-NodeMissingData)
        return
    }
    try {
        if ($scan) { $global:lastFetchWasScan = $true }
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $NodeExe
        # --startup: the app was just opened, so the engine contacts the AI Gauge API once (version/announcements).
        # --scan: discovers all active local AI subscriptions & auto-enables them in config.json.
        $psi.Arguments = "`"$EngineScript`""
        if ($force) { $psi.Arguments += " --force" }
        if ($scan) { $psi.Arguments += " --scan" }
        if (-not $global:StartupSent) { $psi.Arguments += " --startup" }
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $proc = [System.Diagnostics.Process]::Start($psi)
        $global:quotaFetch = @{
            Proc    = $proc
            Out     = $proc.StandardOutput.ReadToEndAsync()
            Err     = $proc.StandardError.ReadToEndAsync()
            Started = Get-Date
        }
        $global:quotaPoll.Start()
    } catch {
        $global:lastFetchWasScan = $false
        Write-AppError $_.Exception
        Complete-QuotaFetch $null
    }
}

function Start-SubscriptionScan {
    if ($global:quotaFetch) { return }
    $global:scanEmptyNotice = $false
    if ($txtAcc) {
        $txtAcc.Text = "Scanning local AI subscriptions (Antigravity, Claude, ChatGPT, Codex, Cursor, Copilot)..."
    }
    if ($btnRefresh) {
        $btnRefresh.Content = "Scanning..."
        $btnRefresh.IsEnabled = $false
    }
    Start-QuotaFetch $true $true
}

$global:StartupSent = $false
$global:quotaPoll = New-Object System.Windows.Threading.DispatcherTimer
$global:quotaPoll.Interval = [TimeSpan]::FromMilliseconds(150)
$global:quotaPoll.Add_Tick({
    $f = $global:quotaFetch
    if (-not $f) { $global:quotaPoll.Stop(); return }
    $timedOut = (((Get-Date) - $f.Started).TotalSeconds -gt 60)
    if (-not $f.Proc.HasExited -and -not $timedOut) { return }
    $global:quotaPoll.Stop()
    $global:quotaFetch = $null
    $result = $null
    try {
        if (-not $f.Proc.HasExited) {
            $f.Proc.Kill()
        } else {
            $f.Proc.WaitForExit()
            if ($f.Proc.ExitCode -eq 0) {
                $json = $f.Out.Result
                if ($json) { $result = $json | ConvertFrom-Json; $global:StartupSent = $true }
            }
        }
    } catch { Write-AppError $_.Exception }
    try { Complete-QuotaFetch $result } catch { Write-AppError $_.Exception }
})

# 4. Main Window XAML (Frameless Glass Cockpit & Radial HUD Dock)
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AI Gauge - Universal AI Quota Cockpit" Height="640" Width="460"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType"
        FontFamily="Segoe UI"
        ResizeMode="NoResize">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#25252D"/>
            <Setter Property="Foreground" Value="#E5E7EB"/>
            <Setter Property="BorderBrush" Value="#383846"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="Bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.90"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.45"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    
    <Border Name="RootBorder" Background="#181818" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="12">
        <Grid>
            <!-- 1. FULL COCKPIT VIEW -->
            <Grid Name="CockpitView" Margin="18,12,18,14" Visibility="Visible">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- Custom Cockpit TitleBar -->
                <Grid Name="CockpitTitleBar" Grid.Row="0" Height="28" Background="Transparent" Margin="0,0,0,4">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Image Name="AppLogo" Width="15" Height="15" Margin="0,0,7,0" VerticalAlignment="Center"/>
                        <TextBlock Text="AI Gauge - Universal AI Quota Cockpit" Foreground="#9CA3AF" FontSize="11.5" FontWeight="Medium"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <Button Name="BtnMin" Content="—" Width="24" Height="22" Background="#222228" Foreground="#9CA3AF" BorderBrush="#303038" BorderThickness="1" FontSize="10" FontWeight="Bold" Cursor="Hand" Margin="0,0,4,0"/>
                        <Button Name="BtnTopClose" Content="✕" Width="24" Height="22" Background="#222228" Foreground="#9CA3AF" BorderBrush="#303038" BorderThickness="1" FontSize="10" FontWeight="Bold" Cursor="Hand"/>
                    </StackPanel>
                </Grid>
                
                <!-- Subtitle / Account Info -->
                <StackPanel Grid.Row="1" Margin="2,2,0,12">
                    <TextBlock Name="TxtAppName" Text="AI Gauge" Foreground="White" FontSize="16" FontWeight="Bold"/>
                    <TextBlock Name="TxtAccount" Text="Loading quotas..." Foreground="#D9D9E0" FontSize="12" FontWeight="Medium" Margin="0,3,0,0"/>
                    <TextBlock Name="TxtUpdated" Text="" Foreground="#8C8C96" FontSize="10.5" Margin="0,2,0,0"/>
                    <Border Height="1" Background="#28282E" Margin="0,10,0,0"/>
                </StackPanel>
                
                <!-- Cards List -->
                <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                    <StackPanel Name="CardsPanel" Margin="0,0,4,0"/>
                </ScrollViewer>
                
                <!-- Cockpit Footer (4 equal-width buttons, matching macOS) -->
                <StackPanel Grid.Row="3" Margin="0,12,0,0">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Name="BtnRefresh" Grid.Column="0" Content="↻ Refresh" Height="28" Margin="0,0,6,0" Background="#EEEEF0" Foreground="#181818" BorderThickness="0" FontWeight="SemiBold" FontSize="11.5" Cursor="Hand"/>
                        <Button Name="BtnHud" Grid.Column="1" Content="⤢ HUD Bar" Height="28" Margin="0,0,6,0" Background="#EEEEF0" Foreground="#181818" BorderThickness="0" FontWeight="SemiBold" FontSize="11.5" Cursor="Hand"/>
                        <Button Name="BtnSettings" Grid.Column="2" Content="⚙ Settings" Height="28" Margin="0,0,6,0" Background="#EEEEF0" Foreground="#181818" BorderThickness="0" FontWeight="SemiBold" FontSize="11.5" Cursor="Hand"/>
                        <Button Name="BtnClose" Grid.Column="3" Content="✕ Close" Height="28" Background="#EEEEF0" Foreground="#181818" BorderThickness="0" FontWeight="SemiBold" FontSize="11.5" Cursor="Hand"/>
                    </Grid>
                    
                    <!-- Brand Link -->
                    <TextBlock Name="TxtBrand" Text="Developed by vh2c.com.br"
                               ToolTip="Support AI Gauge via Stripe Donation"
                               Foreground="#9CA3AF" FontSize="11" FontWeight="Medium"
                               HorizontalAlignment="Center" Margin="0,8,0,0" Cursor="Hand"/>
                </StackPanel>
            </Grid>
            
            <!-- 2. COMPACT HUD BAR VIEW (Mac-identical aesthetic) -->
            <Border Name="HudView" Background="Transparent" Padding="5,6,5,5" Visibility="Collapsed" CornerRadius="14">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- HUD Top Controls (Mac-identical: borderless icons) -->
                    <Grid Grid.Row="0" Margin="2,0,2,4" Height="20">
                        <Button Name="BtnHudCockpit" Content="⤢" Width="22" Height="20" HorizontalAlignment="Left" ToolTip="Cockpit Mode (Ctrl+M)" Background="Transparent" Foreground="#A6A6AE" BorderThickness="0" FontSize="12" FontWeight="Bold" Cursor="Hand"/>
                        <Button Name="BtnHudMenu" Content="⋯" Width="22" Height="20" HorizontalAlignment="Center" ToolTip="Options" Background="Transparent" Foreground="#A6A6AE" BorderThickness="0" FontSize="14" FontWeight="Bold" Cursor="Hand"/>
                        <Button Name="BtnHudClose" Content="✕" Width="22" Height="20" HorizontalAlignment="Right" ToolTip="Close AI Gauge" Background="Transparent" Foreground="#A6A6AE" BorderThickness="0" FontSize="10" FontWeight="Bold" Cursor="Hand"/>
                    </Grid>
                    
                    <!-- HUD Tachometer Gauges List (Zero wide scrollbar, smooth wheel scroll) -->
                    <ScrollViewer Name="HudScrollViewer" Grid.Row="1" VerticalScrollBarVisibility="Hidden" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel Name="HudCardsPanel" HorizontalAlignment="Center"/>
                    </ScrollViewer>
                    
                    <!-- HUD Footer (VH2C / Stripe Donation Link) -->
                    <Border Grid.Row="2" Margin="0,4,0,1">
                        <TextBlock Name="TxtHudBrand" Text="vh2c.com.br" Foreground="#73737D" FontSize="8.5" FontWeight="Medium"
                                   HorizontalAlignment="Center" Cursor="Hand" ToolTip="Support AI Gauge via Stripe Donation"/>
                    </Border>
                </Grid>
            </Border>
        </Grid>
    </Border>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Set Window and Logo Icon
$iconFile = Join-Path $ScriptDir "icon.ico"
if (-not (Test-Path $iconFile)) {
    $iconFile = Join-Path $RepoDir "assets\icon.ico"
}
if (Test-Path $iconFile) {
    try {
        $frame = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($iconFile)))
        $window.Icon = $frame
        $appLogo = $window.FindName("AppLogo")
        if ($appLogo) { $appLogo.Source = $frame }
    } catch {}
}

$cockpitView = $window.FindName("CockpitView")
$cockpitTitleBar = $window.FindName("CockpitTitleBar")
$btnMin = $window.FindName("BtnMin")
$btnTopClose = $window.FindName("BtnTopClose")
$txtAcc = $window.FindName("TxtAccount")
$txtUpdated = $window.FindName("TxtUpdated")
$txtAppName = $window.FindName("TxtAppName")
$cardsPanel = $window.FindName("CardsPanel")
$btnRefresh = $window.FindName("BtnRefresh")
$btnHud = $window.FindName("BtnHud")
$btnSettings = $window.FindName("BtnSettings")
$btnClose = $window.FindName("BtnClose")
$txtBrand = $window.FindName("TxtBrand")

$hudView = $window.FindName("HudView")
$hudScrollViewer = $window.FindName("HudScrollViewer")
$hudCardsPanel = $window.FindName("HudCardsPanel")
$btnHudClose = $window.FindName("BtnHudClose")
$btnHudCockpit = $window.FindName("BtnHudCockpit")
$btnHudMenu = $window.FindName("BtnHudMenu")
$rootBorder = $window.FindName("RootBorder")

$global:isHudMode = $false
$global:currentData = $null
$global:prevLeft = $null
$global:prevTop = $null

# ---------- HUD helpers (metrics identical in spirit to the macOS HUD) ----------
$global:HudWidth = 116
$global:HudOrientation = "vertical"
try {
    $initCfg = Load-CurrentConfig
    if ($initCfg -and $initCfg.hud_orientation -eq "horizontal") { $global:HudOrientation = "horizontal" }
} catch {}

function Get-GaugeKey ($b) {
    if ($b.id) { return "$($b.id)" }
    return "$($b.name)"
}

function Get-HiddenGauges {
    $cfg = Load-CurrentConfig
    if ($cfg -and $cfg.hidden_hud_gauges) {
        return @($cfg.hidden_hud_gauges | ForEach-Object { "$_" })
    }
    return @()
}

function Get-VisibleBuckets ($g, $hidden) {
    if (-not $g.buckets) { return @() }
    return @($g.buckets | Where-Object { $hidden -notcontains (Get-GaugeKey $_) })
}

# Groups buckets by provider section (e.g. merges Antigravity groups into one "Antigravity" section)
function Get-HudSections ($data) {
    $hidden = Get-HiddenGauges
    $sectionOrder = New-Object System.Collections.ArrayList
    $sectionMap = @{}

    if ($data -and $data.groups) {
        foreach ($g in $data.groups) {
            $visible = @(Get-VisibleBuckets $g $hidden)
            if ($visible.Count -eq 0) { continue }
            $provKey = Get-ProviderKey $g.name $g.provider
            if (-not $sectionMap.ContainsKey($provKey)) {
                $accentHex = Get-GroupColorHex $g.name $g.provider
                $cleanTitle = Get-SectionCleanTitle $provKey $g.name
                $secObj = @{
                    Key         = $provKey
                    Title       = $cleanTitle
                    AccentHex   = $accentHex
                    AccentBrush = (Convert-HexToBrush $accentHex)
                    Items       = (New-Object System.Collections.ArrayList)
                }
                $sectionMap[$provKey] = $secObj
                [void]$sectionOrder.Add($secObj)
            }
            foreach ($b in $visible) {
                [void]$sectionMap[$provKey].Items.Add(@{
                    GroupName = "$($g.name)"
                    Bucket    = $b
                })
            }
        }
    }
    return @($sectionOrder)
}

function Get-HudDimensions ($data, $orientation = $null) {
    $orient = if ($orientation) { $orientation } else { $global:HudOrientation }
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $sections = @(Get-HudSections $data)
    $secCount = $sections.Count
    $items = 0
    foreach ($s in $sections) {
        $items += $s.Items.Count
    }
    if ($orient -eq "horizontal") {
        if ($items -eq 0) {
            return @{ Width = 260; Height = 152 }
        }
        $totalW = 24
        foreach ($s in $sections) {
            $totalW += [Math]::Max(108, ($s.Items.Count * 96) + 14) + 10
        }
        $maxW = [Math]::Max(300, $workArea.Width - 40)
        return @{ Width = [Math]::Min($maxW, [Math]::Max(260, $totalW)); Height = 166 }
    }
    if ($items -eq 0) {
        return @{ Width = $global:HudWidth; Height = 180 }
    }
    $calc = 56 + ($secCount * 28) + ($items * 106)
    $maxH = [Math]::Min(780, $workArea.Height - 60)
    return @{ Width = $global:HudWidth; Height = [Math]::Min($maxH, [Math]::Max(160, $calc)) }
}

function Get-HudHeight ($data) {
    return (Get-HudDimensions $data "vertical").Height
}

function Save-HudOrientation ($orient) {
    $global:HudOrientation = $orient
    $cfg = Load-CurrentConfig
    if ($cfg) {
        $cfg | Add-Member -NotePropertyName "hud_orientation" -NotePropertyValue $orient -Force
        Write-Utf8NoBom $ConfigFile ($cfg | ConvertTo-Json -Depth 6)
    }
}

function Toggle-HudOrientation {
    $next = if ($global:HudOrientation -eq "vertical") { "horizontal" } else { "vertical" }
    Save-HudOrientation $next
    if ($global:isHudMode) {
        $dims = Get-HudDimensions $global:currentData $next
        $workArea = [System.Windows.SystemParameters]::WorkArea
        $cx = $window.Left + ($window.Width / 2)
        $cy = $window.Top + ($window.Height / 2)
        $window.Width = $dims.Width
        $window.Height = $dims.Height
        $nx = [Math]::Max($workArea.Left, [Math]::Min($cx - ($dims.Width / 2), $workArea.Right - $dims.Width))
        $ny = [Math]::Max($workArea.Top, [Math]::Min($cy - ($dims.Height / 2), $workArea.Bottom - $dims.Height))
        $window.Left = $nx
        $window.Top = $ny
        Render-HUD $global:currentData
    }
}

function Set-HudChrome ($hud) {
    if ($hud) {
        $rootBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(0xF2, 0x18, 0x18, 0x18)))
        $rootBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2A, 0x2A, 0x2E)))
        $rootBorder.CornerRadius = (New-Object System.Windows.CornerRadius(14))
    } else {
        $rootBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x18, 0x18, 0x18)))
        $rootBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2C, 0x2C, 0x30)))
        $rootBorder.CornerRadius = (New-Object System.Windows.CornerRadius(12))
    }
}

function Set-HudGaugeHidden ($key, $hide) {
    $cfg = Load-CurrentConfig
    if (-not $cfg) { return }
    $list = @(Get-HiddenGauges | Where-Object { $_ -ne $key })
    if ($hide) { $list += $key }
    $cfg | Add-Member -NotePropertyName "hidden_hud_gauges" -NotePropertyValue @($list) -Force
    Write-Utf8NoBom $ConfigFile ($cfg | ConvertTo-Json -Depth 6)
    if ($global:isHudMode) {
        $dims = Get-HudDimensions $global:currentData
        $window.Width = $dims.Width
        $window.Height = $dims.Height
        Render-HUD $global:currentData
    }
}

function Show-HudMenu {
    $menu = New-Object System.Windows.Controls.ContextMenu
    $menu.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x20, 0x20, 0x26)))
    $menu.Foreground = [System.Windows.Media.Brushes]::White
    $menu.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2A, 0x2A, 0x2E)))

    $miSettings = New-Object System.Windows.Controls.MenuItem
    $miSettings.Header = "Settings"
    $miSettings.Add_Click({ Show-SettingsDialog })
    $menu.Items.Add($miSettings) | Out-Null

    $miRefresh = New-Object System.Windows.Controls.MenuItem
    $miRefresh.Header = "Refresh now"
    $miRefresh.Add_Click({ Refresh-Data })
    $menu.Items.Add($miRefresh) | Out-Null

    $miTop = New-Object System.Windows.Controls.MenuItem
    $miTop.Header = "Always on top"
    $miTop.IsCheckable = $true
    $miTop.IsChecked = [bool]$window.Topmost
    $miTop.Add_Click({ param($s, $e) $window.Topmost = [bool]$s.IsChecked })
    $menu.Items.Add($miTop) | Out-Null

    $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

    $miGauges = New-Object System.Windows.Controls.MenuItem
    $miGauges.Header = "HUD Gauges"
    $hidden = Get-HiddenGauges
    if ($global:currentData -and $global:currentData.groups) {
        foreach ($g in $global:currentData.groups) {
            if (-not $g.buckets) { continue }
            foreach ($b in $g.buckets) {
                $key = Get-GaugeKey $b
                $mi = New-Object System.Windows.Controls.MenuItem
                $mi.Header = "$($g.name) - $(Get-BucketWindowLabel $b.name $b.id)"
                $mi.IsCheckable = $true
                $mi.StaysOpenOnClick = $true
                $mi.IsChecked = ($hidden -notcontains $key)
                $mi.Tag = $key
                $mi.Add_Click({ param($s, $e) Set-HudGaugeHidden $s.Tag (-not $s.IsChecked) })
                $miGauges.Items.Add($mi) | Out-Null
            }
        }
    }
    $menu.Items.Add($miGauges) | Out-Null

    $menu.Items.Add((New-Object System.Windows.Controls.Separator)) | Out-Null

    $miOrient = New-Object System.Windows.Controls.MenuItem
    $miOrient.Header = if ($global:HudOrientation -eq "vertical") { "Switch to Horizontal Bar" } else { "Switch to Vertical Bar" }
    $miOrient.Add_Click({ Toggle-HudOrientation })
    $menu.Items.Add($miOrient) | Out-Null

    $miCockpit = New-Object System.Windows.Controls.MenuItem
    $miCockpit.Header = "Open full window"
    $miCockpit.Add_Click({ Toggle-HudMode })
    $menu.Items.Add($miCockpit) | Out-Null

    $menu.PlacementTarget = $btnHudMenu
    $menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $menu.IsOpen = $true
}

$global:hudIdleSince = $null
$global:hudManualOverride = $false
$global:hudPeekWin = $null
$global:isHoveringHud = $false
$global:hudHoverRevealUntil = [DateTime]::MinValue
$global:hudHideTimer = $null
$global:hudRestLeft = $null
$global:isHudHiding = $false

function Schedule-HudAutoHideCheck ([double]$delaySec) {
    if ($null -eq $global:hudHideTimer) {
        $global:hudHideTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:hudHideTimer.Add_Tick({
            $global:hudHideTimer.Stop()
            Apply-HudAutoHidePolicy
        })
    }
    $global:hudHideTimer.Stop()
    $global:hudHideTimer.Interval = [TimeSpan]::FromSeconds([Math]::Max(0.1, $delaySec))
    $global:hudHideTimer.Start()
}

function Hide-HudPeekHandle {
    if ($global:hudPeekWin) {
        try { $global:hudPeekWin.Hide() } catch {}
    }
}

function Show-HudPeekHandle {
    if (-not $global:isHudMode) { Hide-HudPeekHandle; return }
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $hudMidX = if ($null -ne $global:hudRestLeft) { $global:hudRestLeft + ($global:HudWidth / 2.0) } else { $window.Left + ($window.Width / 2.0) }
    $hudMidY = $window.Top + ($window.Height / 2.0)
    $onRight = ($hudMidX -ge ($workArea.Left + ($workArea.Width / 2.0)))
    $peekW = 10
    $peekH = 76
    $peekX = if ($onRight) { $workArea.Right - $peekW } else { $workArea.Left }
    $peekY = [Math]::Min([Math]::Max($hudMidY - ($peekH / 2.0), $workArea.Top + 12), $workArea.Bottom - $peekH - 12)

    if ($null -eq $global:hudPeekWin) {
        $pw = New-Object System.Windows.Window
        $pw.WindowStyle = [System.Windows.WindowStyle]::None
        $pw.AllowsTransparency = $true
        $pw.Background = [System.Windows.Media.Brushes]::Transparent
        $pw.ShowInTaskbar = $false
        $pw.Topmost = $true
        $pw.ResizeMode = [System.Windows.ResizeMode]::NoResize
        $pw.Width = $peekW
        $pw.Height = $peekH

        $grid = New-Object System.Windows.Controls.Grid
        $pill = New-Object System.Windows.Controls.Border
        $pill.Width = 4
        $pill.Height = 52
        $pill.CornerRadius = New-Object System.Windows.CornerRadius(2)
        $pill.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(130, 200, 200, 208)))
        $pill.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(75, 255, 255, 255)))
        $pill.BorderThickness = New-Object System.Windows.Thickness(0.5)
        $pill.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $pill.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $grid.Children.Add($pill) | Out-Null
        $pw.Content = $grid

        $pw.Add_MouseEnter({ Invoke-HudPeekTrigger })
        $pw.Add_MouseLeftButtonDown({ Invoke-HudPeekTrigger })
        $global:hudPeekWin = $pw
    }
    $global:hudPeekWin.Left = $peekX
    $global:hudPeekWin.Top = $peekY
    try { $global:hudPeekWin.Show() } catch {}
}

function Invoke-HudPeekTrigger {
    if (-not $global:isHudMode) { return }
    $global:hudHoverRevealUntil = (Get-Date).AddSeconds(2.5)
    $global:isHoveringHud = $false
    Hide-HudPeekHandle
    Show-HudAnimated
    Schedule-HudAutoHideCheck 2.6
}

function Get-OffscreenHudLeft ([double]$restLeft) {
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $onRight = (($restLeft + ($global:HudWidth / 2.0)) -ge ($workArea.Left + ($workArea.Width / 2.0)))
    if ($onRight) { return ($workArea.Right + 8) } else { return ($workArea.Left - $global:HudWidth - 8) }
}

function Show-HudAnimated {
    if (-not $window) { return }
    $wasHiding = $global:isHudHiding
    $global:isHudHiding = $false
    $rest = if ($null -ne $global:hudRestLeft) { $global:hudRestLeft } else { $window.Left }
    if ($window.Visibility -ne [System.Windows.Visibility]::Visible -or $wasHiding -or $window.Opacity -lt 0.99) {
        if ($window.Visibility -ne [System.Windows.Visibility]::Visible) {
            $window.Left = Get-OffscreenHudLeft $rest
            $window.Opacity = 0.0
            try { $window.Show() } catch {}
        }
        $easeOut = New-Object System.Windows.Media.Animation.CubicEase
        $easeOut.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
        $dur = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(260))

        $animX = New-Object System.Windows.Media.Animation.DoubleAnimation($rest, $dur)
        $animX.EasingFunction = $easeOut
        $animX.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $animX.Add_Completed({ $window.Left = $rest; $global:hudRestLeft = $null })

        $animOp = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, $dur)
        $animOp.EasingFunction = $easeOut
        $animOp.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
        $animOp.Add_Completed({ $window.Opacity = 1.0 })

        $window.BeginAnimation([System.Windows.Window]::LeftProperty, $animX)
        $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $animOp)
    }
}

function Hide-HudAnimated {
    if (-not $window -or $window.Visibility -ne [System.Windows.Visibility]::Visible) {
        Show-HudPeekHandle
        return
    }
    if ($global:isHudHiding) { return }
    $global:isHudHiding = $true
    $rest = $window.Left
    $global:hudRestLeft = $rest
    $offX = Get-OffscreenHudLeft $rest
    $easeIn = New-Object System.Windows.Media.Animation.CubicEase
    $easeIn.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseInOut
    $dur = [System.Windows.Duration]::new([TimeSpan]::FromMilliseconds(220))

    $animX = New-Object System.Windows.Media.Animation.DoubleAnimation($offX, $dur)
    $animX.EasingFunction = $easeIn
    $animX.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop

    $animOp = New-Object System.Windows.Media.Animation.DoubleAnimation(0.0, $dur)
    $animOp.EasingFunction = $easeIn
    $animOp.FillBehavior = [System.Windows.Media.Animation.FillBehavior]::Stop
    $animOp.Add_Completed({
        if (-not $global:isHudHiding) { return }
        $global:isHudHiding = $false
        try { $window.Hide() } catch {}
        $window.Left = $rest
        $window.Opacity = 1.0
        if ($global:isHudMode) { Show-HudPeekHandle }
    })

    $window.BeginAnimation([System.Windows.Window]::LeftProperty, $animX)
    $window.BeginAnimation([System.Windows.Window]::OpacityProperty, $animOp)
}

function Test-AnyAgentActive ($data) {
    if (-not $data) { return $false }
    if ($data.activity) {
        if (($data.activity.working_count -gt 0) -or ($data.activity.waiting_count -gt 0)) {
            return $true
        }
    }
    if ($data.groups) {
        foreach ($g in $data.groups) {
            if ($g.activity -and ($g.activity.state -eq "working" -or $g.activity.state -eq "waiting")) {
                return $true
            }
        }
    }
    return $false
}

function Apply-HudAutoHidePolicy {
    if (-not $global:isHudMode) {
        $global:hudIdleSince = $null
        $global:hudManualOverride = $false
        Hide-HudPeekHandle
        if ($global:hudHideTimer) { $global:hudHideTimer.Stop() }
        if ($window -and $window.Visibility -ne [System.Windows.Visibility]::Visible) {
            try { $window.Show() } catch {}
        }
        return
    }
    $cfg = Load-CurrentConfig
    $autoHide = [bool]($cfg -and $cfg.hud_auto_hide)
    if (-not $autoHide) {
        $global:hudIdleSince = $null
        $global:hudManualOverride = $false
        Hide-HudPeekHandle
        if ($global:hudHideTimer) { $global:hudHideTimer.Stop() }
        Show-HudAnimated
        return
    }
    $showOnActivity = $true
    if ($cfg -and $null -ne $cfg.hud_show_on_activity) {
        $showOnActivity = [bool]$cfg.hud_show_on_activity
    }
    $hasActive = Test-AnyAgentActive $global:currentData
    if ($showOnActivity -and $hasActive) {
        $global:hudIdleSince = $null
        $global:hudManualOverride = $false
        Hide-HudPeekHandle
        Show-HudAnimated
        return
    }
    if ($global:isHoveringHud -or ((Get-Date) -lt $global:hudHoverRevealUntil)) {
        Hide-HudPeekHandle
        Show-HudAnimated
        return
    }
    if ($global:hudManualOverride) {
        Hide-HudPeekHandle
        Show-HudAnimated
        return
    }
    if ($null -eq $global:hudIdleSince) {
        $global:hudIdleSince = Get-Date
        Schedule-HudAutoHideCheck 4.1
        return
    }
    $elapsed = ((Get-Date) - $global:hudIdleSince).TotalSeconds
    if ($elapsed -ge 4.0) {
        Hide-HudAnimated
    } else {
        Schedule-HudAutoHideCheck (4.0 - $elapsed + 0.1)
    }
}

function Toggle-HudMode {
    $workArea = [System.Windows.SystemParameters]::WorkArea
    if ($global:isHudMode) {
        # Switch back to Cockpit Mode
        $global:isHudMode = $false
        $global:hudIdleSince = $null
        $global:hudManualOverride = $false
        $hudView.Visibility = [System.Windows.Visibility]::Collapsed
        $cockpitView.Visibility = [System.Windows.Visibility]::Visible
        
        Set-HudChrome $false
        $window.Title = "AI Gauge - Universal AI Quota Cockpit"
        $window.Topmost = $false
        $window.Width = 460
        $window.Height = 640
        if ($null -ne $global:prevLeft -and $null -ne $global:prevTop) {
            $window.Left = $global:prevLeft
            $window.Top = $global:prevTop
        } else {
            $window.Left = [Math]::Max(0, ($workArea.Width - 460) / 2)
            $window.Top = [Math]::Max(0, ($workArea.Height - 640) / 2)
        }
        
        if ($window.Visibility -ne [System.Windows.Visibility]::Visible) {
            try { $window.Show() } catch {}
        }
        Render-UI $global:currentData
        if (((Get-Date) - $global:lastQuotaFetchAt).TotalSeconds -gt 15) {
            Refresh-Data
        }
    } else {
        # Switch to HUD Bar Mode
        $global:isHudMode = $true
        $global:hudIdleSince = $null
        $global:hudManualOverride = $false
        $global:prevLeft = $window.Left
        $global:prevTop = $window.Top
        
        $cockpitView.Visibility = [System.Windows.Visibility]::Collapsed
        $hudView.Visibility = [System.Windows.Visibility]::Visible
        
        Set-HudChrome $true
        $dims = Get-HudDimensions $global:currentData
        
        $window.Title = "AI Gauge HUD"
        $window.Topmost = $true
        $window.Width = $dims.Width
        $window.Height = $dims.Height
        if ($global:HudOrientation -eq "horizontal") {
            $window.Left = [Math]::Max($workArea.Left, ($workArea.Width - $dims.Width) / 2)
            $window.Top = $workArea.Bottom - ($dims.Height + 16)
        } else {
            $window.Left = $workArea.Right - ($dims.Width + 16)
            $window.Top = [Math]::Max(20, ($workArea.Height - $dims.Height) / 2)
        }
        
        Render-HUD $global:currentData
        Apply-HudAutoHidePolicy
    }
}

# Window Controls
$btnMin.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$btnTopClose.Add_Click({ $window.Close() })
$btnClose.Add_Click({ $window.Close() })
$btnHud.Add_Click({ Toggle-HudMode })

$btnHudClose.Add_Click({ Hide-HudPeekHandle; $window.Close() })
$btnHudCockpit.Add_Click({ Toggle-HudMode })
$btnHudMenu.Add_Click({ Show-HudMenu })

$hudView.Add_MouseEnter({
    $global:isHoveringHud = $true
    $global:hudHoverRevealUntil = [DateTime]::MinValue
    if ($global:hudHideTimer) { $global:hudHideTimer.Stop() }
})
$hudView.Add_MouseLeave({
    $global:isHoveringHud = $false
    if ($global:isHudMode) {
        $cfg = Load-CurrentConfig
        if ($cfg -and $cfg.hud_auto_hide) {
            $global:hudManualOverride = $false
            $global:hudHoverRevealUntil = [DateTime]::MinValue
            if ($null -eq $global:hudIdleSince) { $global:hudIdleSince = (Get-Date).AddSeconds(-3.0) }
            Schedule-HudAutoHideCheck 1.5
        }
    }
})

# Dragging Support
$cockpitTitleBar.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        try { $window.DragMove() } catch {}
    }
})

function Update-HudAutoOrientationAfterDrag ($startL, $startT) {
    if (-not $global:isHudMode) { return }
    if ([Math]::Abs($window.Left - $startL) -lt 3 -and [Math]::Abs($window.Top - $startT) -lt 3) { return }
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $leftDist = [Math]::Max(0, $window.Left - $workArea.Left)
    $rightDist = [Math]::Max(0, $workArea.Right - ($window.Left + $window.Width))
    $topDist = [Math]::Max(0, $window.Top - $workArea.Top)
    $bottomDist = [Math]::Max(0, $workArea.Bottom - ($window.Top + $window.Height))
    $minLR = [Math]::Min($leftDist, $rightDist)
    $minTB = [Math]::Min($topDist, $bottomDist)
    $edgeMargin = 90

    $newOrient = $global:HudOrientation
    if ($minLR -le $edgeMargin -and $minTB -le $edgeMargin) {
        $newOrient = "vertical"
    } elseif ($minTB -le $edgeMargin) {
        $newOrient = "horizontal"
    } elseif ($minLR -le $edgeMargin) {
        $newOrient = "vertical"
    }

    if ($newOrient -eq $global:HudOrientation) { return }

    $cx = $window.Left + ($window.Width / 2)
    $cy = $window.Top + ($window.Height / 2)
    Save-HudOrientation $newOrient

    $dims = Get-HudDimensions $global:currentData $newOrient
    $window.Width = $dims.Width
    $window.Height = $dims.Height
    $nx = $cx - ($dims.Width / 2)
    $ny = $cy - ($dims.Height / 2)
    if ($newOrient -eq "horizontal") {
        if ($topDist -le 48) { $ny = $workArea.Top + 12 }
        elseif ($bottomDist -le 48) { $ny = $workArea.Bottom - $dims.Height - 12 }
    } else {
        if ($leftDist -le 48) { $nx = $workArea.Left + 12 }
        elseif ($rightDist -le 48) { $nx = $workArea.Right - $dims.Width - 12 }
    }
    $window.Left = [Math]::Max($workArea.Left, [Math]::Min($nx, [Math]::Max($workArea.Left, $workArea.Right - $dims.Width)))
    $window.Top = [Math]::Max($workArea.Top, [Math]::Min($ny, [Math]::Max($workArea.Top, $workArea.Bottom - $dims.Height)))
    Render-HUD $global:currentData
}

$window.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($global:isHudMode -and $e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        $startL = $window.Left
        $startT = $window.Top
        try { $window.DragMove() } catch {}
        Update-HudAutoOrientationAfterDrag $startL $startT
    }
})

# Double-click on HUD to expand back to Cockpit
$hudView.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.ClickCount -eq 2) {
        Toggle-HudMode
    }
})

# Global Hotkey Ctrl+M
$window.Add_KeyDown({
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::M -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        Toggle-HudMode
    }
})

$global:FixedFreeTitle = "Help AI GAUGE developers team"

# Builds one top-of-window notice banner (info = amber, versao = green), identical to the macOS one.
# "Update now": runs the get-ai-gauge.ps1 that ships INSIDE the app (no remote script is executed). It downloads the
# release installer from GitHub, verifies its SHA-256, runs it silently (it closes this app) and reopens AI Gauge.
function Invoke-SelfUpdate ($version, $fallbackUrl, $button) {
    $updater = Join-Path $ScriptDir "get-ai-gauge.ps1"
    if ($DemoMode -or -not $version -or -not (Test-Path $updater)) {
        if ($fallbackUrl) { [System.Diagnostics.Process]::Start("$fallbackUrl") | Out-Null }
        return
    }
    $ask = [System.Windows.MessageBox]::Show("AI Gauge will download the new version, verify its checksum, close, install it and open again. This takes a few seconds.", "Update AI Gauge to v$version?", [System.Windows.MessageBoxButton]::OKCancel, [System.Windows.MessageBoxImage]::Question)
    if ($ask -ne [System.Windows.MessageBoxResult]::OK) { return }
    # Run a temporary copy: the installer replaces the files of the app folder while the updater is still running
    $tmpDir = Join-Path $env:TEMP "aigauge-update"
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
    $tmpUpdater = Join-Path $tmpDir "get-ai-gauge.ps1"
    Copy-Item -Path $updater -Destination $tmpUpdater -Force
    $env:AIGAUGE_VERSION = "v$version"
    $env:AIGAUGE_SILENT = "1"
    Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", ('"' + $tmpUpdater + '"')) -WindowStyle Hidden | Out-Null
    if ($button) { $button.Content = "Updating..."; $button.IsEnabled = $false }
}

function New-NoticeBanner ($ann, $data) {
    $isVersao = ("$($ann.type)" -eq "versao")
    $mk = { param($a, $r, $g, $b) New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb($a, $r, $g, $b)) }
    if ($isVersao) {
        $fill = & $mk 0x80 0x06 0x2A 0x1E;  $border = & $mk 0x99 0x10 0xB9 0x81
        $titleC = & $mk 0xFF 0x34 0xD3 0x99; $btnFill = & $mk 0x38 0x10 0xB9 0x81; $btnBorder = & $mk 0xB3 0x10 0xB9 0x81
    } else {
        $fill = & $mk 0x80 0x2D 0x24 0x18;  $border = & $mk 0x99 0xF5 0x9E 0x0B
        $titleC = & $mk 0xFF 0xFB 0xBF 0x24; $btnFill = & $mk 0x38 0xF5 0x9E 0x0B; $btnBorder = & $mk 0xB3 0xF5 0x9E 0x0B
    }

    $annBorder = New-Object System.Windows.Controls.Border
    $annBorder.Background = $fill
    $annBorder.BorderBrush = $border
    $annBorder.BorderThickness = (New-Object System.Windows.Thickness(1))
    $annBorder.CornerRadius = (New-Object System.Windows.CornerRadius(7))
    $annBorder.Padding = (New-Object System.Windows.Thickness(14, 10, 14, 11))
    $annBorder.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 10))

    $annStack = New-Object System.Windows.Controls.StackPanel

    $annHead = New-Object System.Windows.Controls.TextBlock
    $annHead.Text = if ($ann.title) { "$($ann.title)" } elseif ($isVersao) { "New Version Available" } else { "Notice" }
    $annHead.FontWeight = [System.Windows.FontWeights]::Bold
    $annHead.FontSize = 11.5
    $annHead.Foreground = $titleC
    $annStack.Children.Add($annHead) | Out-Null

    $annMsg = New-Object System.Windows.Controls.TextBlock
    $annMsg.Text = "$($ann.message)"
    $annMsg.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $annMsg.FontSize = 10.5
    $annMsg.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xD9, 0xD9, 0xD9)))
    $annMsg.Margin = (New-Object System.Windows.Thickness(0, 3, 0, 0))
    $annStack.Children.Add($annMsg) | Out-Null

    $versionBtn = $null
    $annUrl = "$($ann.action_url)".Trim()
    $hasAction = $isVersao -or ($ann.action_label -and "$($ann.action_label)".Trim()) -or $annUrl
    if ($hasAction) {
        $defaultLabel = if ($isVersao) { "Download Now" } else { "View Details" }
        $actLabel = if ($ann.action_label -and "$($ann.action_label)".Trim()) { "$($ann.action_label)".Trim() } else { $defaultLabel }
        $arrow = [string][char]0x2192
        $btnText = if ($actLabel.EndsWith("!") -or $actLabel.Contains($arrow)) { $actLabel } else { "$actLabel $arrow" }

        $updUrl = if ($data -and $data.update) { "$($data.update.download_url)".Trim() } else { "" }
        $target = if ($isVersao) {
            if ($annUrl) { $annUrl } elseif ($updUrl) { $updUrl } else { "https://github.com/vh2c/ai-gauge/releases/latest" }
        } else {
            if ($annUrl) { $annUrl } else { "https://ai-gauge.vh2c.com.br/donate" }
        }
        if ($target -match '\{machine_id\}') {
            $midv = ""
            if (Test-Path $DeviceIdFile) { $midv = (Get-Content $DeviceIdFile -Raw).Trim() }
            $target = $target.Replace("{machine_id}", $midv)
        }

        $btnAct = New-Object System.Windows.Controls.Button
        $btnAct.Content = $btnText
        $btnAct.Tag = $target
        $btnAct.MinWidth = 170
        $btnAct.Height = 26
        $btnAct.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $btnAct.Margin = (New-Object System.Windows.Thickness(0, 8, 0, 0))
        $btnAct.Padding = (New-Object System.Windows.Thickness(16, 0, 16, 0))
        $btnAct.Background = $btnFill
        $btnAct.BorderBrush = $btnBorder
        $btnAct.BorderThickness = (New-Object System.Windows.Thickness(1))
        $btnAct.Foreground = $titleC
        $btnAct.FontWeight = [System.Windows.FontWeights]::Bold
        $btnAct.FontSize = 11
        $btnAct.Cursor = [System.Windows.Input.Cursors]::Hand
        # URL kept in Tag: this function's locals are gone by the time the click happens
        # The version to install (built-in update notice only) travels in DataContext, the URL in Tag
        $btnAct.DataContext = "$($ann.update_version)"
        $btnAct.Add_Click({ param($sender, $e)
            try {
                $ver = "$($sender.DataContext)"
                if ($ver) { Invoke-SelfUpdate $ver "$($sender.Tag)" $sender }
                else { [System.Diagnostics.Process]::Start("$($sender.Tag)") }
            } catch { Write-AppError $_.Exception }
        })
        if ($isVersao) {
            # Compact strip: button on the right, vertically centered
            $btnAct.MinWidth = 160
            $btnAct.Margin = (New-Object System.Windows.Thickness(14, 0, 0, 0))
            $btnAct.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
            $btnAct.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $versionBtn = $btnAct
        } else {
            $annStack.Children.Add($btnAct) | Out-Null
        }
    }

    if ($isVersao -and $versionBtn) {
        $annBorder.Padding = (New-Object System.Windows.Thickness(16, 10, 14, 10))
        $vg = New-Object System.Windows.Controls.Grid
        $vc1 = New-Object System.Windows.Controls.ColumnDefinition; $vc1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $vc2 = New-Object System.Windows.Controls.ColumnDefinition; $vc2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
        $vg.ColumnDefinitions.Add($vc1)
        $vg.ColumnDefinitions.Add($vc2)
        $annStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($annStack, 0)
        [System.Windows.Controls.Grid]::SetColumn($versionBtn, 1)
        $vg.Children.Add($annStack) | Out-Null
        $vg.Children.Add($versionBtn) | Out-Null
        $annBorder.Child = $vg
    } else {
        $annBorder.Child = $annStack
    }
    return $annBorder
}

# Independent advertising toast (1 minute after loading the app, then every 6 hours).
$global:promoShownAtEpoch = 0
$global:promoWindow = $null
$global:promoRemaining = 0
$global:promoTimer = $null
$global:promoRepeatTimer = $null
$global:promoCountdownBtn = $null

function Close-PromoToast {
    try { if ($global:promoTimer) { $global:promoTimer.Stop() } } catch {}
    $global:promoTimer = $null
    $global:promoCountdownBtn = $null
    try { if ($global:promoWindow) { $global:promoWindow.Close() } } catch {}
    $global:promoWindow = $null
}

$global:AppStartedAt = Get-Date
$global:promoPending = $false
$global:promoPendingAd = $null
$global:promoDelayTimer = $null

# Shows the ad 1 minute after the app opens, and then every 6 hours while the app remains running.
function Show-PromoToast ($ann) {
    if (-not $ann) { return }
    $global:promoPendingAd = $ann
    if ($global:promoWindow -or $global:promoPending) { return }

    $nowEpoch = Get-UnixSeconds
    $intervalSec = 21600
    if ($global:promoShownAtEpoch -gt 0 -and (($nowEpoch - $global:promoShownAtEpoch) -lt $intervalSec)) {
        return
    }

    $initial = if ($DemoMode) { 6 } elseif ($global:promoShownAtEpoch -eq 0) { 60 } else { 0.2 }
    $elapsedSinceStart = ((Get-Date) - $global:AppStartedAt).TotalSeconds
    $wait = if ($global:promoShownAtEpoch -eq 0) { [Math]::Max(0.2, $initial - $elapsedSinceStart) } else { 0.2 }

    $global:promoPending = $true
    if (-not $global:promoDelayTimer) {
        $global:promoDelayTimer = New-Object System.Windows.Threading.DispatcherTimer
        $global:promoDelayTimer.Add_Tick({
            $global:promoDelayTimer.Stop()
            $global:promoPending = $false
            $global:promoShownAtEpoch = Get-UnixSeconds
            $adNow = $global:promoPendingAd
            if ($adNow) {
                Show-PromoToastNow $adNow
            }
            if (-not $global:promoRepeatTimer) {
                $global:promoRepeatTimer = New-Object System.Windows.Threading.DispatcherTimer
                $global:promoRepeatTimer.Interval = [TimeSpan]::FromHours(6)
                $global:promoRepeatTimer.Add_Tick({
                    if ($global:promoPendingAd) { Show-PromoToast $global:promoPendingAd }
                })
            }
            $global:promoRepeatTimer.Stop()
            $global:promoRepeatTimer.Start()
        })
    }
    $global:promoDelayTimer.Interval = [TimeSpan]::FromSeconds($wait)
    $global:promoDelayTimer.Start()
}

function Show-PromoToastNow ($ann) {
    if (-not $ann -or $global:promoWindow) { return }
    try {
        [xml]$toastXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AI Gauge" Width="380" SizeToContent="Height"
        WindowStyle="None" AllowsTransparency="True" ShowActivated="False" Focusable="False"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType"
        FontFamily="Segoe UI"
        Background="Transparent" ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="12" Opacity="1" Name="Bd">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.88"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Margin="14" Background="#16171F" BorderBrush="#26FFFFFF" BorderThickness="1" CornerRadius="18" Padding="16,14,16,16">
        <Border.Effect><DropShadowEffect BlurRadius="22" ShadowDepth="5" Opacity="0.55"/></Border.Effect>
        <StackPanel>
            <Grid Height="20">
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                    <Image Name="PromoIcon" Width="16" Height="16"/>
                    <TextBlock Text="AI GAUGE - PROMOTION" Foreground="#94A3B8" FontSize="10.5" FontWeight="Bold" Margin="8,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
                <Button Name="BtnPromoClose" Content="✕" Width="20" Height="20" HorizontalAlignment="Right" Background="Transparent" Foreground="#64748B" BorderThickness="0" FontSize="11" FontWeight="Bold" Cursor="Hand"/>
            </Grid>
            <Border Name="MediaBox" Height="165" CornerRadius="12" ClipToBounds="True" Background="#0E1015" Margin="0,10,0,0" Visibility="Collapsed">
                <Image Name="PromoImage" Stretch="UniformToFill"/>
            </Border>
            <TextBlock Name="PromoTitle" FontSize="16" FontWeight="Bold" Foreground="White" TextWrapping="Wrap" Margin="0,12,0,4"/>
            <TextBlock Name="PromoText" FontSize="12" Foreground="#94A3B8" TextWrapping="Wrap" MaxHeight="66" TextTrimming="CharacterEllipsis" Margin="0,0,0,14"/>
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Button Name="BtnLater" Grid.Column="0" Height="36" Margin="0,0,4,0" Content="Not now" Background="#14FFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1" Foreground="#E2E8F0" FontSize="12.5" FontWeight="SemiBold"/>
                <Button Name="BtnPromo" Grid.Column="1" Height="36" Margin="4,0,0,0" Content="View Details" BorderThickness="0" Foreground="White" FontSize="12.5" FontWeight="SemiBold" Focusable="False">
                    <Button.Background>
                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                            <GradientStop Color="#6366F1" Offset="0"/><GradientStop Color="#4F46E5" Offset="1"/>
                        </LinearGradientBrush>
                    </Button.Background>
                </Button>
            </Grid>
        </StackPanel>
    </Border>
</Window>
"@
        $tw = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $toastXaml))
        $global:promoWindow = $tw

        $tw.FindName("PromoTitle").Text = if ($ann.title) { "$($ann.title)" } else { "AI Gauge Pro" }
        $tw.FindName("PromoText").Text = "$($ann.message)"

        try {
            if (Test-Path $iconFile) {
                $tw.FindName("PromoIcon").Source = [System.Windows.Media.Imaging.BitmapFrame]::Create((New-Object System.Uri($iconFile)))
            }
        } catch {}

        # Optional image: download bytes safely into a MemoryStream under TLS 1.2 so remote HTTPS ads render reliably
        $imgUrl = "$($ann.image_url)".Trim()
        if ($imgUrl) {
            if ($imgUrl.StartsWith("http://")) { $imgUrl = "https://" + $imgUrl.Substring(7) }
            try {
                $wc = New-Object System.Net.WebClient
                $wc.Headers.Add("User-Agent", "AIGauge/1.2")
                $bytes = $wc.DownloadData($imgUrl)
                $wc.Dispose()
                if ($bytes -and $bytes.Length -gt 0) {
                    $ms = New-Object System.IO.MemoryStream(, $bytes)
                    $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                    $bmp.BeginInit()
                    $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                    $bmp.StreamSource = $ms
                    $bmp.EndInit()
                    $bmp.Freeze()
                    $ms.Dispose()

                    $img = $tw.FindName("PromoImage")
                    $img.Source = $bmp
                    if ("$($ann.image_fit)" -eq "contain") { $img.Stretch = [System.Windows.Media.Stretch]::Uniform }
                    $sc = 1.0
                    if ($ann.image_scale) {
                        [void][double]::TryParse("$($ann.image_scale)", [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$sc)
                    }
                    if ($sc -ne 1.0) {
                        $img.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
                        $img.RenderTransform = New-Object System.Windows.Media.ScaleTransform($sc, $sc)
                    }
                    $tw.FindName("MediaBox").Visibility = [System.Windows.Visibility]::Visible
                }
            } catch { Write-AppError $_.Exception }
        }

        # Action button (only when the ad has a link)
        $btnPromo = $tw.FindName("BtnPromo")
        $btnLater = $tw.FindName("BtnLater")
        $btnPromoClose = $tw.FindName("BtnPromoClose")
        if ($btnPromoClose) { $btnPromoClose.Add_Click({ Close-PromoToast }) }

        $actUrl = "$($ann.action_url)".Trim()
        if ($actUrl) {
            if ($actUrl -match '\{machine_id\}') {
                $midp = ""
                if (Test-Path $DeviceIdFile) { $midp = (Get-Content $DeviceIdFile -Raw).Trim() }
                $actUrl = $actUrl.Replace("{machine_id}", $midp)
            }
            if ($ann.action_label -and "$($ann.action_label)".Trim()) { $btnPromo.Content = "$($ann.action_label)".Trim() }
            $btnPromo.Tag = $actUrl
            $btnPromo.Add_Click({
                param($s, $e)
                if ($s.Tag) {
                    try { [System.Diagnostics.Process]::Start("$($s.Tag)") } catch { Write-AppError $_.Exception }
                }
                Close-PromoToast
            })
        } else {
            $btnPromo.Visibility = [System.Windows.Visibility]::Collapsed
            $btnLater.Margin = New-Object System.Windows.Thickness(0)
            [System.Windows.Controls.Grid]::SetColumnSpan($btnLater, 2)
        }

        # "Not now" closes immediately (or unlocks after optional duracao_segundos countdown)
        $durSec = 0
        if ($ann.duracao_segundos) { [void][int]::TryParse("$($ann.duracao_segundos)", [ref]$durSec) }
        if ($durSec -gt 0) {
            $global:promoRemaining = $durSec
            $global:promoCountdownBtn = $btnLater
            $btnLater.IsEnabled = $false
            $btnLater.Content = "Not now ($($global:promoRemaining)s)"
            $global:promoTimer = New-Object System.Windows.Threading.DispatcherTimer
            $global:promoTimer.Interval = [TimeSpan]::FromSeconds(1)
            $global:promoTimer.Add_Tick({
                $global:promoRemaining--
                if ($global:promoRemaining -le 0) {
                    $global:promoTimer.Stop()
                    if ($global:promoCountdownBtn) {
                        $global:promoCountdownBtn.IsEnabled = $true
                        $global:promoCountdownBtn.Content = "Not now"
                    }
                } else {
                    if ($global:promoCountdownBtn) {
                        $global:promoCountdownBtn.Content = "Not now ($($global:promoRemaining)s)"
                    }
                }
            })
            $global:promoTimer.Start()
        } else {
            $btnLater.IsEnabled = $true
        }
        $btnLater.Add_Click({ param($s, $e) Close-PromoToast })

        $positionToast = {
            param($win)
            try {
                $wa = [System.Windows.SystemParameters]::WorkArea
                $aw = if ($win.ActualWidth -gt 50) { $win.ActualWidth } else { 380 }
                $ah = if ($win.ActualHeight -gt 50) { $win.ActualHeight } else { 260 }
                $win.Left = [Math]::Max($wa.Left + 10, $wa.Right - $aw - 12)
                $win.Top = [Math]::Max($wa.Top + 10, $wa.Bottom - $ah - 12)
            } catch {}
        }
        $tw.Add_ContentRendered({ param($s, $e) & $positionToast $s })
        $tw.Add_SizeChanged({ param($s, $e) & $positionToast $s })
        & $positionToast $tw

        $tw.Add_MouseLeftButtonDown({ param($s, $e) try { $s.DragMove() } catch {} })
        $tw.Add_Closed({
            try { if ($global:promoTimer) { $global:promoTimer.Stop() } } catch {}
            $global:promoTimer = $null
            $global:promoCountdownBtn = $null
            $global:promoWindow = $null
        })
        $tw.Show()
    } catch {
        Write-AppError $_.Exception
        $global:promoWindow = $null
    }
}

# 5. Render Full Cockpit UI
function Render-UI ($data) {
    $global:currentData = $data
    $cardsPanel.Children.Clear()
    $txtUpdated.Text = ""
    
    $appVer = if ($data -and $data.version) { "$($data.version)" } else { $global:AppVersion }
    if ($txtAppName) {
        $txtAppName.Inlines.Clear()
        $runTitle = New-Object System.Windows.Documents.Run("AI Gauge")
        $runVer = New-Object System.Windows.Documents.Run("  v$appVer")
        $runVer.FontSize = 12
        $runVer.FontWeight = [System.Windows.FontWeights]::Normal
        $runVer.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x88, 0x88, 0x94))
        $txtAppName.Inlines.Add($runTitle)
        $txtAppName.Inlines.Add($runVer)
    }
    if ($window) {
        $window.Title = "AI Gauge v$appVer - Universal AI Quota Cockpit"
    }
    if ($txtBrand) {
        $txtBrand.Text = "⚡ AI Gauge v$appVer  •  Developed by vh2c.com.br"
    }

    $hasGroups = ($data -and $data.groups -and $data.groups.Count -gt 0)
    
    # ----------------- EMPTY STATE (ONBOARDING) -----------------
    if (-not $hasGroups) {
        $txtAcc.Text = "No AI account or quota detected locally"
        
        $emptyBorder = New-Object System.Windows.Controls.Border
        $emptyBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1B, 0x1B, 0x22)))
        $emptyBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2E, 0x2E, 0x3A)))
        $emptyBorder.BorderThickness = (New-Object System.Windows.Thickness(1))
        $emptyBorder.CornerRadius = (New-Object System.Windows.CornerRadius(10))
        $emptyBorder.Padding = (New-Object System.Windows.Thickness(18, 16, 18, 18))
        $emptyBorder.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 10))
        
        $emptyStack = New-Object System.Windows.Controls.StackPanel
        
        # Check if Node.js is missing
        if ($data -and $data.node_missing) {
            $txtAcc.Text = "Node.js was not found on this system"
            $tIconNode = New-Object System.Windows.Controls.TextBlock
            $tIconNode.Text = "⚠️"
            $tIconNode.FontSize = 18
            $tIconNode.Margin = (New-Object System.Windows.Thickness(0, 0, 8, 0))
            
            $tTitleNode = New-Object System.Windows.Controls.TextBlock
            $tTitleNode.Text = "Node.js Required"
            $tTitleNode.FontSize = 14
            $tTitleNode.FontWeight = [System.Windows.FontWeights]::Bold
            $tTitleNode.Foreground = [System.Windows.Media.Brushes]::White
            
            $tRowNode = New-Object System.Windows.Controls.StackPanel
            $tRowNode.Orientation = [System.Windows.Controls.Orientation]::Horizontal
            $tRowNode.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 6))
            $tRowNode.Children.Add($tIconNode) | Out-Null
            $tRowNode.Children.Add($tTitleNode) | Out-Null
            $emptyStack.Children.Add($tRowNode) | Out-Null
            
            $tDescNode = New-Object System.Windows.Controls.TextBlock
            $tDescNode.Text = "AI Gauge needs Node.js (v18+) to aggregate quotas in the background. Click the button below to download it for free:"
            $tDescNode.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $tDescNode.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xBB, 0xBB, 0xC4)))
            $tDescNode.FontSize = 11
            $tDescNode.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 14))
            $emptyStack.Children.Add($tDescNode) | Out-Null
            
            $btnNode = New-Object System.Windows.Controls.Button
            $btnNode.Content = "⬇ Download Official Node.js (nodejs.org)"
            $btnNode.Height = 32
            $btnNode.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
            $btnNode.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x12, 0x12, 0x14)))
            $btnNode.FontWeight = [System.Windows.FontWeights]::Bold
            $btnNode.FontSize = 11.5
            $btnNode.Cursor = [System.Windows.Input.Cursors]::Hand
            $btnNode.Add_Click({ [System.Diagnostics.Process]::Start("https://nodejs.org") })
            $emptyStack.Children.Add($btnNode) | Out-Null
            
            $emptyBorder.Child = $emptyStack
            $cardsPanel.Children.Add($emptyBorder) | Out-Null
            return
        }

        if ($global:scanEmptyNotice) {
            $txtAcc.Text = "Scan complete: no active local subscriptions found."
        }

        # 1. Welcome Title & Installed Version Badge
        $tRow = New-Object System.Windows.Controls.StackPanel
        $tRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $tRow.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 4))
        
        $tTitle = New-Object System.Windows.Controls.TextBlock
        $tTitle.Text = "Welcome to AI Gauge"
        $tTitle.FontSize = 15
        $tTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $tTitle.Foreground = [System.Windows.Media.Brushes]::White
        $tTitle.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $tRow.Children.Add($tTitle) | Out-Null
        
        $emptyStack.Children.Add($tRow) | Out-Null

        $tVerBadge = New-Object System.Windows.Controls.TextBlock
        $tVerBadge.Text = "Installed Version: v$appVer"
        $tVerBadge.FontSize = 11
        $tVerBadge.FontWeight = [System.Windows.FontWeights]::SemiBold
        $tVerBadge.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
        $tVerBadge.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 10))
        $emptyStack.Children.Add($tVerBadge) | Out-Null
        
        # 2. Scan AI Subscriptions Explanation & Primary CTA
        $tDesc = New-Object System.Windows.Controls.TextBlock
        if ($global:scanEmptyNotice) {
            $tDesc.Text = "Scan complete: no active local subscriptions found. Sign in to one of your AI apps and scan again, or use the links below to connect an API Key or Token."
        } else {
            $tDesc.Text = "Click below to automatically search this computer for Antigravity, Claude, ChatGPT, Codex, Cursor, and GitHub Copilot and prepare AI Gauge."
        }
        $tDesc.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $tDesc.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xBB, 0xBB, 0xC4)))
        $tDesc.FontSize = 11
        $tDesc.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 10))
        $emptyStack.Children.Add($tDesc) | Out-Null

        $btnScan = New-Object System.Windows.Controls.Button
        $btnScan.Content = "Scan AI Subscriptions"
        $btnScan.Height = 34
        $btnScan.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 14))
        $btnScan.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
        $btnScan.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x12, 0x12, 0x14)))
        $btnScan.FontWeight = [System.Windows.FontWeights]::Bold
        $btnScan.FontSize = 12
        $btnScan.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnScan.Add_Click({ Start-SubscriptionScan })
        $emptyStack.Children.Add($btnScan) | Out-Null
        
        # 3. Direct API Key / Token Links Card
        $guideBox = New-Object System.Windows.Controls.Border
        $guideBox.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x14, 0x14, 0x18)))
        $guideBox.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x25, 0x25, 0x30)))
        $guideBox.BorderThickness = (New-Object System.Windows.Thickness(1))
        $guideBox.CornerRadius = (New-Object System.Windows.CornerRadius(6))
        $guideBox.Padding = (New-Object System.Windows.Thickness(12, 10, 12, 10))
        $guideBox.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 12))
        
        $guideStack = New-Object System.Windows.Controls.StackPanel
        
        $gHead = New-Object System.Windows.Controls.TextBlock
        $gHead.Text = "No Subscriptions Found? Get API Keys & Tokens"
        $gHead.FontWeight = [System.Windows.FontWeights]::Bold
        $gHead.Foreground = [System.Windows.Media.Brushes]::White
        $gHead.FontSize = 11
        $gHead.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 8))
        $guideStack.Children.Add($gHead) | Out-Null

        $apiLinks = @(
            @{ Label = "Google Gemini API Key (Google AI Studio) ->"; Url = "https://aistudio.google.com/app/apikey" },
            @{ Label = "OpenAI API Key (ChatGPT / Codex Platform) ->"; Url = "https://platform.openai.com/api-keys" },
            @{ Label = "Anthropic API Key (Claude Console) ->"; Url = "https://console.anthropic.com/settings/keys" },
            @{ Label = "Cursor Account & Session Token ->"; Url = "https://www.cursor.com/settings" },
            @{ Label = "GitHub Copilot Personal Token ->"; Url = "https://github.com/settings/tokens" }
        )
        foreach ($lnkItem in $apiLinks) {
            $bLnk = New-Object System.Windows.Controls.Button
            $bLnk.Content = $lnkItem.Label
            $bLnk.Tag = $lnkItem.Url
            $bLnk.Height = 26
            $bLnk.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 5))
            $bLnk.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
            $bLnk.Padding = (New-Object System.Windows.Thickness(10, 0, 10, 0))
            $bLnk.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1E, 0x1E, 0x26)))
            $bLnk.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xCB, 0xD5, 0xE1)))
            $bLnk.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2E, 0x2E, 0x3A)))
            $bLnk.BorderThickness = (New-Object System.Windows.Thickness(1))
            $bLnk.FontSize = 10.5
            $bLnk.FontWeight = [System.Windows.FontWeights]::SemiBold
            $bLnk.Cursor = [System.Windows.Input.Cursors]::Hand
            $bLnk.Add_Click({
                param($s, $e)
                if ($s.Tag) { try { [System.Diagnostics.Process]::Start("$($s.Tag)") } catch { Write-AppError $_.Exception } }
            })
            $guideStack.Children.Add($bLnk) | Out-Null
        }
        
        $guideBox.Child = $guideStack
        $emptyStack.Children.Add($guideBox) | Out-Null
        
        # 4. Settings Button (paste API key or session token)
        $btnConfig = New-Object System.Windows.Controls.Button
        $btnConfig.Content = "Configure API Keys & Tokens"
        $btnConfig.Height = 30
        $btnConfig.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x32)))
        $btnConfig.Foreground = [System.Windows.Media.Brushes]::White
        $btnConfig.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x3A, 0x3A, 0x48)))
        $btnConfig.BorderThickness = (New-Object System.Windows.Thickness(1))
        $btnConfig.FontWeight = [System.Windows.FontWeights]::SemiBold
        $btnConfig.FontSize = 11.5
        $btnConfig.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnConfig.Add_Click({ Show-SettingsDialog })
        $emptyStack.Children.Add($btnConfig) | Out-Null
        $emptyBorder.Child = $emptyStack
        $cardsPanel.Children.Add($emptyBorder) | Out-Null
        return
    }
    
    $cacheInfo = if ($data.from_cache) { "Cache" } elseif ($DemoMode) { "Demo" } else { "Live" }
    $pollSecs = Get-EffectivePollSeconds $data
    $pollText = if ($pollSecs -ge 300) { "Polling 5 min (idle)" } else { "Polling ${pollSecs}s (active)" }
    $actWork = if ($data.activity -and $null -ne $data.activity.working_count) { [int]$data.activity.working_count } else { 0 }
    $actWait = if ($data.activity -and $null -ne $data.activity.waiting_count) { [int]$data.activity.waiting_count } else { 0 }
    $sumParts = @()
    if ($actWork -gt 0) { $sumParts += "$actWork working" }
    if ($actWait -gt 0) { $sumParts += "$actWait waiting" }
    $sumLabel = if ($sumParts.Count -gt 0) { $sumParts -join " · " } else { "All idle" }
    $txtAcc.Text = "$($data.account)  •  Plan $($data.plan)"
    $txtUpdated.Text = "Updated at $($data.updated_at) ($cacheInfo) · $pollText · $sumLabel"

    # The version that is running, next to the title
    if ($data.version -and $txtAppName) {
        $txtAppName.Inlines.Clear()
        $runTitle = New-Object System.Windows.Documents.Run("AI Gauge")
        $runVer = New-Object System.Windows.Documents.Run("  v$($data.version)")
        $runVer.FontSize = 12
        $runVer.FontWeight = [System.Windows.FontWeights]::Normal
        $runVer.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x88, 0x88, 0x94))
        $txtAppName.Inlines.Add($runTitle)
        $txtAppName.Inlines.Add($runVer)
    }
    
    # ----------------- BANNERS (top of the window) + independent promo toast -----------------
    $ann = $data.announcement
    $annType = if ($ann) { "$($ann.type)" } else { "" }
    $annIsAd = ($annType -eq "publicidade")
    $updAvail = ($data.update -and $data.update.update_available)

    # 1. New-version notice (from the app's own update check)
    if ($updAvail -and $annType -ne "versao") {
        $upAnn = @{ type = "versao"; title = "New Version Available"; message = "Version $($data.update.latest_version) is available."; action_label = "Update now"; action_url = $data.update.download_url; update_version = "$($data.update.latest_version)" }
        $cardsPanel.Children.Add((New-NoticeBanner $upAnn $data)) | Out-Null
    }

    # 2. Dashboard notice (version / info / warning). Ads are NOT banners: they go to the toast below.
    if ($ann -and -not $annIsAd -and $ann.message -and "$($ann.message)".Trim() -and ("$($ann.title)".Trim().ToLower() -ne $global:FixedFreeTitle.ToLower())) {
        $cardsPanel.Children.Add((New-NoticeBanner $ann $data)) | Out-Null
    }

    # 3. Fixed banner for FREE users
    $tierName = if ($data.tier) { "$($data.tier)".ToLower() } else { "free" }
    if ($tierName -ne "pro" -and $tierName -ne "enterprise") {
        $mid = ""
        if (Test-Path $DeviceIdFile) { $mid = (Get-Content $DeviceIdFile -Raw).Trim() }
        $donateUrl = if ($mid) { "https://ai-gauge.vh2c.com.br/donate?mid=$mid" } else { "https://ai-gauge.vh2c.com.br/donate" }
        $fixedAnn = @{ type = "promo"; title = $global:FixedFreeTitle; message = "AI GAUGE is developed by independent developers. Support this initiative by making a donation of any amount."; action_label = "MAKE A DONATION!"; action_url = $donateUrl }
        $cardsPanel.Children.Add((New-NoticeBanner $fixedAnn $data)) | Out-Null
    }

    # 4. Advertising = independent toast window: API `promo` (or, with an older API, an ad in `announcement`)
    $adPromo = if ($data.promo) { $data.promo } elseif ($annIsAd) { $ann } else { $null }
    if ($adPromo) { Show-PromoToast $adPromo }

    foreach ($g in $data.groups) {
        $provKey = Get-ProviderKey $g.name $g.provider
        $accentHex = Get-GroupColorHex $g.name $g.provider
        $accentBrush = Convert-HexToBrush $accentHex
        
        $cleanTitle = $g.name
        if ($provKey -eq "claude_pro") { $cleanTitle = "Claude" }
        elseif ($provKey -eq "chatgpt_subscription") { $cleanTitle = "ChatGPT" }
        elseif ($provKey -eq "cursor") { $cleanTitle = "Cursor" }
        elseif ($provKey -eq "github_copilot") { $cleanTitle = "Copilot" }
        elseif ($provKey -eq "gemini") { $cleanTitle = "Google Gemini" }
        
        $provLabels = @{ antigravity = "ANTIGRAVITY"; claude_pro = "CLAUDE"; chatgpt_subscription = "CHATGPT"; cursor = "CURSOR"; github_copilot = "COPILOT"; gemini = "GEMINI"; openai = "OPENAI"; anthropic = "ANTHROPIC" }
        $badgeLabel = if ($provLabels.ContainsKey($provKey)) { $provLabels[$provKey] } else { "$provKey".ToUpper() }

        $act = Get-ProviderActivity $data $provKey
        $actStatus = if ($act -and $act.status) { "$($act.status)" } else { "idle" }
        $cardBorderBrush = if ($actStatus -eq "waiting") {
            $wb = Convert-HexToBrush "#F5A623"
            $wb.Opacity = 0.55
            $wb
        } else {
            New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2C, 0x2C, 0x30))
        }

        $card = New-Object System.Windows.Controls.Border
        $card.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1E, 0x1E, 0x22))
        $card.BorderBrush = $cardBorderBrush
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(8)
        $card.Padding = New-Object System.Windows.Thickness(14, 11, 14, 12)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
        $card.ToolTip = Get-ActivityTooltip $cleanTitle $act $pollSecs
        
        $cardStack = New-Object System.Windows.Controls.StackPanel

        # Card header INSIDE the card: group title (left) + live activity + provider tag (right)
        $headerGrid = New-Object System.Windows.Controls.Grid
        $hCol1 = New-Object System.Windows.Controls.ColumnDefinition; $hCol1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $hCol2 = New-Object System.Windows.Controls.ColumnDefinition; $hCol2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
        $headerGrid.ColumnDefinitions.Add($hCol1)
        $headerGrid.ColumnDefinitions.Add($hCol2)

        $gbTitle = New-Object System.Windows.Controls.TextBlock
        $gbTitle.Text = $cleanTitle
        $gbTitle.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF2, 0xF2, 0xF4)))
        $gbTitle.FontSize = 12.5
        $gbTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $gbTitle.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        [System.Windows.Controls.Grid]::SetColumn($gbTitle, 0)
        $headerGrid.Children.Add($gbTitle) | Out-Null

        $rightHdr = New-Object System.Windows.Controls.StackPanel
        $rightHdr.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $rightHdr.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $glyph = New-ActivityGlyph $actStatus $accentHex 10
        $glyph.Margin = New-Object System.Windows.Thickness(0, 0, 4, 0)
        $rightHdr.Children.Add($glyph) | Out-Null

        $stTb = New-Object System.Windows.Controls.TextBlock
        $stTb.Text = if ($actStatus -eq "waiting") { "Waiting" } elseif ($actStatus -eq "working") { "Working" } else { "Idle" }
        $stTb.FontSize = 10
        $stTb.FontWeight = [System.Windows.FontWeights]::Medium
        $stTb.Foreground = if ($actStatus -eq "waiting") {
            Convert-HexToBrush "#F5A623"
        } elseif ($actStatus -eq "working") {
            New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xE5, 0xE7, 0xEB))
        } else {
            New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x71, 0x71, 0x7A))
        }
        $stTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $rightHdr.Children.Add($stTb) | Out-Null

        $dotTb = New-Object System.Windows.Controls.TextBlock
        $dotTb.Text = " · "
        $dotTb.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x52, 0x52, 0x5B))
        $dotTb.FontSize = 10
        $dotTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $rightHdr.Children.Add($dotTb) | Out-Null

        $tagBadge = New-Object System.Windows.Controls.TextBlock
        $tagBadge.Text = $badgeLabel
        $tagBadge.Foreground = $accentBrush
        $tagBadge.FontSize = 8.5
        $tagBadge.FontWeight = [System.Windows.FontWeights]::Bold
        $tagBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $rightHdr.Children.Add($tagBadge) | Out-Null

        [System.Windows.Controls.Grid]::SetColumn($rightHdr, 1)
        $headerGrid.Children.Add($rightHdr) | Out-Null
        $cardStack.Children.Add($headerGrid) | Out-Null

        $hSep = New-Object System.Windows.Controls.Border
        $hSep.Height = 1
        $hSep.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x2E))
        $hSep.Margin = New-Object System.Windows.Thickness(0, 8, 0, 7)
        $cardStack.Children.Add($hSep) | Out-Null

        if (($actStatus -eq "working" -or $actStatus -eq "waiting") -and $act -and $act.detail) {
            $prefix = if ($actStatus -eq "waiting") { "Paused" } else { "Active" }
            $ageTxt = if ($null -ne $act.age_seconds) { " · $($act.age_seconds)s ago" } else { "" }
            $sessTb = New-Object System.Windows.Controls.TextBlock
            $sessTb.Text = "$prefix · $($act.detail)$ageTxt"
            $sessTb.FontSize = 10
            $sessTb.Foreground = if ($actStatus -eq "waiting") {
                Convert-HexToBrush "#F5B84D"
            } else {
                New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xA1, 0xA1, 0xAA))
            }
            $sessTb.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $sessTb.Margin = New-Object System.Windows.Thickness(0, 0, 0, 7)
            $cardStack.Children.Add($sessTb) | Out-Null
        }
        
        $idx = 0
        foreach ($b in $g.buckets) {
            if ($idx -gt 0) {
                $sep = New-Object System.Windows.Controls.Border
                $sep.Height = 1
                $sep.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x2E))
                $sep.Margin = New-Object System.Windows.Thickness(0, 7, 0, 7)
                $cardStack.Children.Add($sep) | Out-Null
            }
            
            $pct = [int]$b.remaining_pct
            $statusBrush = Get-StatusBrush $pct $accentHex

            $row = New-Object System.Windows.Controls.Grid
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
            $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
            $row.ColumnDefinitions.Add($c1)
            $row.ColumnDefinitions.Add($c2)
            $row.ColumnDefinitions.Add($c3)
            
            $tbName = New-Object System.Windows.Controls.TextBlock
            $tbName.Text = $b.name
            $tbName.Foreground = [System.Windows.Media.Brushes]::White
            $tbName.FontSize = 11.5
            $tbName.FontWeight = [System.Windows.FontWeights]::Medium
            $tbName.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $tbName.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            [System.Windows.Controls.Grid]::SetColumn($tbName, 0)
            $row.Children.Add($tbName) | Out-Null

            if ($b.reset_in) {
                $tbReset = New-Object System.Windows.Controls.TextBlock
                $tbReset.Text = if ($b.reset_in -eq "Now") { "Renews now" } elseif ($b.reset_in -eq "Active") { "Active" } elseif ($b.reset_in -eq "Outdated") { "Outdated · sign in again" } else { "Renews in $($b.reset_in)" }
                $tbReset.Foreground = if ($b.reset_in -eq "Outdated") { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF5, 0xA6, 0x23)) } else { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x88, 0x88, 0x94)) }
                $tbReset.FontSize = 9.5
                $tbReset.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $tbReset.Margin = New-Object System.Windows.Thickness(8, 0, 10, 0)
                [System.Windows.Controls.Grid]::SetColumn($tbReset, 1)
                $row.Children.Add($tbReset) | Out-Null
            }
            
            $isOutdated = ($b.reset_in -eq "Outdated")
            $tbVal = New-Object System.Windows.Controls.TextBlock
            $tbVal.Text = if ($isOutdated) { "--%" } else { "$pct%" }
            $tbVal.Foreground = if ($isOutdated) { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF5, 0xA6, 0x23)) } else { $statusBrush }
            $tbVal.FontWeight = [System.Windows.FontWeights]::Bold
            $tbVal.FontSize = 13
            $tbVal.MinWidth = 44
            $tbVal.TextAlignment = [System.Windows.TextAlignment]::Right
            $tbVal.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            [System.Windows.Controls.Grid]::SetColumn($tbVal, 2)
            $row.Children.Add($tbVal) | Out-Null
            
            $cardStack.Children.Add($row) | Out-Null
            
            # Progress bar: two star columns, crisp 6px track matching macOS
            $pctClamped = if ($isOutdated) { 0 } else { [Math]::Min([Math]::Max($pct, 0), 100) }
            $pbar = New-Object System.Windows.Controls.Grid
            $pbar.Height = 6
            $pbar.Margin = New-Object System.Windows.Thickness(0, 5, 0, 0)
            $pb1 = New-Object System.Windows.Controls.ColumnDefinition; $pb1.Width = New-Object System.Windows.GridLength($pctClamped, [System.Windows.GridUnitType]::Star)
            $pb2 = New-Object System.Windows.Controls.ColumnDefinition; $pb2.Width = New-Object System.Windows.GridLength((100 - $pctClamped), [System.Windows.GridUnitType]::Star)
            $pbar.ColumnDefinitions.Add($pb1)
            $pbar.ColumnDefinitions.Add($pb2)

            $pbarBg = New-Object System.Windows.Controls.Border
            $pbarBg.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x2D))
            $pbarBg.CornerRadius = New-Object System.Windows.CornerRadius(3)
            [System.Windows.Controls.Grid]::SetColumn($pbarBg, 0)
            [System.Windows.Controls.Grid]::SetColumnSpan($pbarBg, 2)
            $pbar.Children.Add($pbarBg) | Out-Null

            $pbarFill = New-Object System.Windows.Controls.Border
            $pbarFill.Background = $statusBrush
            $pbarFill.CornerRadius = New-Object System.Windows.CornerRadius(3)
            [System.Windows.Controls.Grid]::SetColumn($pbarFill, 0)
            $pbar.Children.Add($pbarFill) | Out-Null

            $cardStack.Children.Add($pbar) | Out-Null
            
            $idx++
        }
        
        $card.Child = $cardStack
        $cardsPanel.Children.Add($card) | Out-Null
    }
}

# 6. Render HUD UI (Framed Section Capsules & Signature Tachometer Dials)
function Render-HUD ($data) {
    $hudCardsPanel.Children.Clear()
    $isHoriz = ($global:HudOrientation -eq "horizontal")
    $hudCardsPanel.Orientation = if ($isHoriz) { [System.Windows.Controls.Orientation]::Horizontal } else { [System.Windows.Controls.Orientation]::Vertical }
    if ($hudScrollViewer) {
        $hudScrollViewer.VerticalScrollBarVisibility = if ($isHoriz) { [System.Windows.Controls.ScrollBarVisibility]::Disabled } else { [System.Windows.Controls.ScrollBarVisibility]::Hidden }
        $hudScrollViewer.HorizontalScrollBarVisibility = if ($isHoriz) { [System.Windows.Controls.ScrollBarVisibility]::Hidden } else { [System.Windows.Controls.ScrollBarVisibility]::Disabled }
    }
    
    $hasGroups = ($data -and $data.groups -and $data.groups.Count -gt 0)
    
    if (-not $hasGroups) {
        $card = New-Object System.Windows.Controls.Border
        $card.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1B, 0x1B, 0x20)))
        $card.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x32)))
        $card.BorderThickness = (New-Object System.Windows.Thickness(1))
        $card.CornerRadius = (New-Object System.Windows.CornerRadius(10))
        $card.Width = 106
        $card.Height = 116
        $card.Margin = (New-Object System.Windows.Thickness(0, 4, 0, 6))
        $card.Padding = (New-Object System.Windows.Thickness(6, 10, 6, 8))
        $card.Cursor = [System.Windows.Input.Cursors]::Hand
        $card.Add_MouseLeftButtonDown({ Show-SettingsDialog })
        
        $cardStack = New-Object System.Windows.Controls.StackPanel
        $cardStack.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        
        $icon = New-Object System.Windows.Controls.TextBlock
        $icon.Text = "⚙"
        $icon.FontSize = 18
        $icon.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x8F, 0xBC, 0xFF)))
        $icon.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $cardStack.Children.Add($icon) | Out-Null
        
        $t1 = New-Object System.Windows.Controls.TextBlock
        $t1.Text = "NO QUOTAS"
        $t1.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x8F, 0xBC, 0xFF)))
        $t1.FontSize = 8.5
        $t1.FontWeight = [System.Windows.FontWeights]::Bold
        $t1.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $t1.Margin = (New-Object System.Windows.Thickness(0, 4, 0, 2))
        $cardStack.Children.Add($t1) | Out-Null
        
        $t2 = New-Object System.Windows.Controls.TextBlock
        $t2.Text = "Click to configure accounts or tokens."
        $t2.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $t2.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x94, 0xA3, 0xB8)))
        $t2.FontSize = 8
        $t2.TextAlignment = [System.Windows.TextAlignment]::Center
        $cardStack.Children.Add($t2) | Out-Null
        
        $card.Child = $cardStack
        $hudCardsPanel.Children.Add($card) | Out-Null
        return
    }
    
    $sections = @(Get-HudSections $data)
    $pollSecs = Get-EffectivePollSeconds $data
    foreach ($sec in $sections) {
        $accentHex = $sec.AccentHex
        $accentBrush = $sec.AccentBrush
        $cleanTitle = $sec.Title
        $act = Get-ProviderActivity $data $sec.Key
        $actStatus = if ($act -and $act.status) { "$($act.status)" } else { "idle" }

        # Section Frame Container Grid (Mac-aligned 102px width in vertical, auto width in horizontal)
        $secGrid = New-Object System.Windows.Controls.Grid
        if ($isHoriz) {
            $secGrid.Width = [double]::NaN
            $secGrid.Margin = New-Object System.Windows.Thickness(0, 0, 8, 0)
            $secGrid.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
        } else {
            $secGrid.Width = 102
            $secGrid.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
            $secGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        }
        $secGrid.ToolTip = Get-ActivityTooltip $cleanTitle $act $pollSecs

        # Outer Rounded Border (Proposta A: color/opacity responds to working / waiting / idle)
        $frameBorderBrush = if ($actStatus -eq "waiting") {
            $wb = Convert-HexToBrush "#F5A623"
            $pulseB = New-Object System.Windows.Media.Animation.DoubleAnimation(1.0, 0.48, [TimeSpan]::FromSeconds(0.9))
            $pulseB.AutoReverse = $true
            $pulseB.RepeatBehavior = [System.Windows.Media.Animation.RepeatBehavior]::Forever
            $wb.BeginAnimation([System.Windows.Media.Brush]::OpacityProperty, $pulseB)
            $wb
        } elseif ($actStatus -eq "working") {
            Convert-HexToBrush $accentHex
        } else {
            $ib = Convert-HexToBrush $accentHex
            $ib.Opacity = 0.42
            $ib
        }

        $secBorder = New-Object System.Windows.Controls.Border
        $secBorder.BorderBrush = $frameBorderBrush
        $secBorder.BorderThickness = New-Object System.Windows.Thickness(1.6)
        $secBorder.CornerRadius = New-Object System.Windows.CornerRadius(12)
        $secBorder.Margin = New-Object System.Windows.Thickness(0, 7, 0, 0)
        $secBorder.Background = [System.Windows.Media.Brushes]::Transparent

        # Stack inside the Section Frame
        $secStack = New-Object System.Windows.Controls.StackPanel
        $secStack.Orientation = if ($isHoriz) { [System.Windows.Controls.Orientation]::Horizontal } else { [System.Windows.Controls.Orientation]::Vertical }
        $secStack.Margin = if ($isHoriz) { New-Object System.Windows.Thickness(6, 11, 6, 6) } else { New-Object System.Windows.Thickness(0, 9, 0, 6) }
        $secBorder.Child = $secStack
        $secGrid.Children.Add($secBorder) | Out-Null

        # Cut-out Title + Live Glyph on Top Line (Proposta A)
        $titleBadge = New-Object System.Windows.Controls.Border
        $titleBadge.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x18, 0x18, 0x18))
        $titleBadge.Padding = New-Object System.Windows.Thickness(4, 0, 4, 0)
        $titleBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $titleBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Top

        $titleStack = New-Object System.Windows.Controls.StackPanel
        $titleStack.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $titleStack.VerticalAlignment = [System.Windows.VerticalAlignment]::Center

        $hdrGlyph = New-ActivityGlyph $actStatus $accentHex 9
        $hdrGlyph.Margin = New-Object System.Windows.Thickness(0, 0, 3.5, 0)
        $titleStack.Children.Add($hdrGlyph) | Out-Null

        $titleTb = New-Object System.Windows.Controls.TextBlock
        $titleTb.Text = $cleanTitle
        $titleBrush = if ($actStatus -eq "waiting") {
            Convert-HexToBrush "#F5A623"
        } elseif ($actStatus -eq "working") {
            Convert-HexToBrush $accentHex
        } else {
            $tb = Convert-HexToBrush $accentHex
            $tb.Opacity = 0.75
            $tb
        }
        $titleTb.Foreground = $titleBrush
        $titleTb.FontSize = if ($cleanTitle.Length -ge 10) { 9.8 } else { 10.2 }
        $titleTb.FontWeight = [System.Windows.FontWeights]::SemiBold
        $titleStack.Children.Add($titleTb) | Out-Null

        $titleBadge.Child = $titleStack
        $secGrid.Children.Add($titleBadge) | Out-Null

        foreach ($itemWrap in $sec.Items) {
            $b = $itemWrap.Bucket
            $itemGroupName = $itemWrap.GroupName
            $isOutdated = ($b.reset_in -eq "Outdated")
            $pct = if ($isOutdated) { 0 } else { [int]$b.remaining_pct }
            $statusBrush = if ($isOutdated) {
                (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF5, 0xA6, 0x23)))
            } else {
                Get-StatusBrush $pct $accentHex
            }
            
            # Tachometer Gauge Item Container (96x104, refined to match macOS)
            $dialStack = New-Object System.Windows.Controls.StackPanel
            $dialStack.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $dialStack.Margin = New-Object System.Windows.Thickness(0)
            $dialStack.Width = 96
            $dialStack.Height = 104

            $cx = 44.0; $cy = 44.0; $ar = 31.0
            $dialGrid = New-Object System.Windows.Controls.Grid
            $dialGrid.Width = 88
            $dialGrid.Height = 84

            # Background circular tint
            $bgCircle = New-Object System.Windows.Shapes.Ellipse
            $bgCircle.Width = 64
            $bgCircle.Height = 64
            $bgCircle.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(220, 0x14, 0x14, 0x16)))
            $bgCircle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $bgCircle.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $dialGrid.Children.Add($bgCircle) | Out-Null

            # Curved window label (e.g. WEEKLY LIMIT / 5 HOURS LIMIT) along the top of the dial
            $wLabel = (Get-BucketWindowLabel $b.name $b.id)
            $labelR = 40.0
            $stepDeg = 5.6 / $labelR * 180.0 / [Math]::PI
            $startAng = -($wLabel.Length - 1) * $stepDeg / 2.0
            $labelBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xA8, 0xA8, 0xB4)))
            for ($ci = 0; $ci -lt $wLabel.Length; $ci++) {
                $ch = $wLabel.Substring($ci, 1)
                if ($ch -eq " ") { continue }
                $angDeg = $startAng + $ci * $stepDeg
                $angRad = $angDeg * [Math]::PI / 180.0
                $px = $cx + $labelR * [Math]::Sin($angRad)
                $py = $cy - $labelR * [Math]::Cos($angRad)
                $tbCh = New-Object System.Windows.Controls.TextBlock
                $tbCh.Text = $ch
                $tbCh.Width = 7
                $tbCh.Height = 9
                $tbCh.TextAlignment = [System.Windows.TextAlignment]::Center
                $tbCh.FontSize = 6.5
                $tbCh.FontWeight = [System.Windows.FontWeights]::Bold
                $tbCh.Foreground = $labelBrush
                $tbCh.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
                $tbCh.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
                $tbCh.Margin = New-Object System.Windows.Thickness(($px - 3.5), ($py - 4.5), 0, 0)
                $tbCh.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
                $tbCh.RenderTransform = New-Object System.Windows.Media.RotateTransform($angDeg)
                $dialGrid.Children.Add($tbCh) | Out-Null
            }

            # Track Arc (260 deg from 140 deg to 400 deg)
            $trackStr = Get-ArcGeometry $cx $cy $ar 140 260
            if ($trackStr) {
                $trackPath = New-Object System.Windows.Shapes.Path
                $trackPath.Data = [System.Windows.Media.Geometry]::Parse($trackStr)
                $trackPath.Stroke = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2A, 0x2A, 0x2D)))
                $trackPath.StrokeThickness = 5
                $trackPath.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
                $trackPath.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
                $dialGrid.Children.Add($trackPath) | Out-Null
            }

            # 24 Radial Graduation Tick Marks (matching macOS TachometerGaugeView)
            $numTicks = 24
            $majorTickBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(200, 140, 140, 148))
            $minorTickBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(120, 84, 84, 92))
            for ($ti = 0; $ti -le $numTicks; $ti++) {
                $frac = $ti / [double]$numTicks
                $tDeg = 140.0 + ($frac * 260.0)
                $tRad = $tDeg * [Math]::PI / 180.0
                $isMajor = (($ti % 6) -eq 0)
                $rIn = $ar - 3.5
                $rOut = $rIn - $(if ($isMajor) { 4.2 } else { 2.5 })
                $tk = New-Object System.Windows.Shapes.Line
                $tk.X1 = [Math]::Round($cx + $rIn * [Math]::Cos($tRad), 2)
                $tk.Y1 = [Math]::Round($cy + $rIn * [Math]::Sin($tRad), 2)
                $tk.X2 = [Math]::Round($cx + $rOut * [Math]::Cos($tRad), 2)
                $tk.Y2 = [Math]::Round($cy + $rOut * [Math]::Sin($tRad), 2)
                $tk.Stroke = if ($isMajor) { $majorTickBrush } else { $minorTickBrush }
                $tk.StrokeThickness = if ($isMajor) { 1.1 } else { 0.7 }
                $dialGrid.Children.Add($tk) | Out-Null
            }

            # Active Progress Arc
            $sweep = ($pct / 100.0) * 260.0
            if ($sweep -gt 260.0) { $sweep = 260.0 }
            if ($sweep -ge 1.0) {
                $progStr = Get-ArcGeometry $cx $cy $ar 140 $sweep
                if ($progStr) {
                    $progPath = New-Object System.Windows.Shapes.Path
                    $progPath.Data = [System.Windows.Media.Geometry]::Parse($progStr)
                    $progPath.Stroke = $statusBrush
                    $progPath.StrokeThickness = 5
                    $progPath.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
                    $progPath.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
                    $dialGrid.Children.Add($progPath) | Out-Null
                }
            }

            # Needle Pointer
            $needleStr = Get-NeedleGeometry $cx $cy $ar $pct 140 260
            if ($needleStr) {
                $needlePath = New-Object System.Windows.Shapes.Path
                $needlePath.Data = [System.Windows.Media.Geometry]::Parse($needleStr)
                $needlePath.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(242, 245, 245, 250)))
                $dialGrid.Children.Add($needlePath) | Out-Null
            }

            # Center Hub Pin
            $hub = New-Object System.Windows.Shapes.Ellipse
            $hub.Width = 7
            $hub.Height = 7
            $hub.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x26, 0x26, 0x2B)))
            $hub.Stroke = $statusBrush
            $hub.StrokeThickness = 1.2
            $hub.Margin = New-Object System.Windows.Thickness(($cx - 3.5), ($cy - 3.5), 0, 0)
            $hub.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
            $hub.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
            $dialGrid.Children.Add($hub) | Out-Null

            # Center Percentage Text (sits in the gap at the bottom of the arc)
            $tbPct = New-Object System.Windows.Controls.TextBlock
            $tbPct.Text = if ($isOutdated) { "--%" } else { "$pct%" }
            $tbPct.Foreground = if ($isOutdated) { $statusBrush } else { [System.Windows.Media.Brushes]::White }
            $tbPct.FontSize = if ($pct -ge 100) { 10.5 } else { 11 }
            $tbPct.FontWeight = [System.Windows.FontWeights]::Bold
            $tbPct.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $tbPct.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
            $tbPct.Margin = New-Object System.Windows.Thickness(0, 56, 0, 0)
            $dialGrid.Children.Add($tbPct) | Out-Null

            $dialStack.Children.Add($dialGrid) | Out-Null
            
            # 3. Model Name Underneath (e.g. "Gemini", "Claude/GPT", "Argon", "Claude")
            $mName = Get-BucketModelName $b.name $itemGroupName
            $tbMName = New-Object System.Windows.Controls.TextBlock
            $tbMName.Text = $mName
            $tbMName.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xC8, 0xCD, 0xD6)))
            $tbMName.FontSize = 9.5
            $tbMName.FontWeight = [System.Windows.FontWeights]::Medium
            $tbMName.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $tbMName.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $tbMName.MaxWidth = 92
            $tbMName.Margin = New-Object System.Windows.Thickness(0, -10, 0, 0)
            $dialStack.Children.Add($tbMName) | Out-Null
            
            # 4. Reset Countdown Underneath (e.g. "4d 1h", "4h 51m")
            $tbReset = New-Object System.Windows.Controls.TextBlock
            $tbReset.Text = if ($b.reset_in) { $b.reset_in } else { "Active" }
            $tbReset.Foreground = if ($isOutdated) { $statusBrush } else { (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x8E, 0x8E, 0x98))) }
            $tbReset.FontSize = 8.5
            $tbReset.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $tbReset.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $tbReset.MaxWidth = 92
            $dialStack.Children.Add($tbReset) | Out-Null
            
            $secStack.Children.Add($dialStack) | Out-Null
        }
        
        $hudCardsPanel.Children.Add($secGrid) | Out-Null
    }
}

function Show-HudGaugeSelectionDialog ($data) {
    if (-not $data -or -not $data.groups -or $data.groups.Count -eq 0) { return }

    [xml]$hudSelXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Subscriptions Detected - Select HUD Bar Gauges" Height="560" Width="460"
        WindowStartupLocation="CenterOwner" Background="#18181A" ResizeMode="NoResize"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Text="Subscriptions Detected - Select HUD Bar Gauges" Foreground="#FFFFFF" FontSize="14" FontWeight="Bold"/>
            <TextBlock Name="TxtSelSub" Text="Choose which gauges you want displayed on the floating HUD Bar:" Foreground="#94A3B8" FontSize="10.5" TextWrapping="Wrap" Margin="0,4,0,0"/>
        </StackPanel>

        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel Name="HudSelStack" Margin="0,0,6,0"/>
        </ScrollViewer>

        <Grid Grid.Row="2" Margin="0,12,0,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                <Button Name="BtnSelectAllHud" Content="Select All" Width="82" Height="28" Background="#282830" Foreground="#E5E7EB" BorderBrush="#3A3A46" BorderThickness="1" Margin="0,0,6,0"/>
                <Button Name="BtnClearAllHud" Content="Clear All" Width="78" Height="28" Background="#282830" Foreground="#E5E7EB" BorderBrush="#3A3A46" BorderThickness="1"/>
            </StackPanel>
            <Button Name="BtnSaveHudSel" Content="Save &amp; Ready to Use" Width="156" Height="28" HorizontalAlignment="Right" Background="#00E699" Foreground="#121214" FontWeight="Bold"/>
        </Grid>
    </Grid>
</Window>
"@

    $selReader = (New-Object System.Xml.XmlNodeReader $hudSelXaml)
    $selWin = [System.Windows.Markup.XamlReader]::Load($selReader)
    $ownerSet = $false
    try {
        if ($window -and $window.IsVisible) { $selWin.Owner = $window; $ownerSet = $true }
    } catch {}
    if (-not $ownerSet) {
        $selWin.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    }

    $txtSelSub = $selWin.FindName("TxtSelSub")
    $hudSelStack = $selWin.FindName("HudSelStack")
    $btnSelectAllHud = $selWin.FindName("BtnSelectAllHud")
    $btnClearAllHud = $selWin.FindName("BtnClearAllHud")
    $btnSaveHudSel = $selWin.FindName("BtnSaveHudSel")

    $hiddenKeys = Get-HiddenGauges
    $checkBoxes = New-Object System.Collections.ArrayList

    $provNames = @()
    foreach ($g in $data.groups) {
        if ($g.name -and ($provNames -notcontains "$($g.name)")) { $provNames += "$($g.name)" }
    }
    if ($txtSelSub -and $provNames.Count -gt 0) {
        $txtSelSub.Text = "Detected: $($provNames -join ', '). Choose which gauges you want displayed on the floating HUD Bar:"
    }

    foreach ($g in $data.groups) {
        if (-not $g.buckets) { continue }
        foreach ($b in $g.buckets) {
            $key = Get-GaugeKey $b
            $pct = [int]$b.remaining_pct
            $rowBorder = New-Object System.Windows.Controls.Border
            $rowBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1F, 0x1F, 0x24)))
            $rowBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2E, 0x2E, 0x38)))
            $rowBorder.BorderThickness = (New-Object System.Windows.Thickness(1))
            $rowBorder.CornerRadius = (New-Object System.Windows.CornerRadius(6))
            $rowBorder.Padding = (New-Object System.Windows.Thickness(10, 8, 12, 8))
            $rowBorder.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 6))

            $rowGrid = New-Object System.Windows.Controls.Grid
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
            $rowGrid.ColumnDefinitions.Add($c1)
            $rowGrid.ColumnDefinitions.Add($c2)

            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = "$($g.name)  •  $($b.name)"
            $cb.Foreground = [System.Windows.Media.Brushes]::White
            $cb.FontSize = 11.5
            $cb.FontWeight = [System.Windows.FontWeights]::SemiBold
            $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $cb.Tag = $key
            $cb.IsChecked = ($hiddenKeys -notcontains $key)
            [System.Windows.Controls.Grid]::SetColumn($cb, 0)
            $rowGrid.Children.Add($cb) | Out-Null

            $lblPct = New-Object System.Windows.Controls.TextBlock
            $lblPct.Text = if ($b.reset_in -eq "Outdated") { "--%" } else { "$pct%" }
            $lblPct.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
            $lblPct.FontSize = 11.5
            $lblPct.FontWeight = [System.Windows.FontWeights]::Bold
            $lblPct.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $lblPct.Margin = (New-Object System.Windows.Thickness(8, 0, 0, 0))
            [System.Windows.Controls.Grid]::SetColumn($lblPct, 1)
            $rowGrid.Children.Add($lblPct) | Out-Null

            $rowBorder.Child = $rowGrid
            $hudSelStack.Children.Add($rowBorder) | Out-Null
            $checkBoxes.Add($cb) | Out-Null
        }
    }

    $btnSelectAllHud.Tag = $checkBoxes
    $btnSelectAllHud.Add_Click({
        param($s, $e)
        foreach ($c in $s.Tag) { $c.IsChecked = $true }
    })

    $btnClearAllHud.Tag = $checkBoxes
    $btnClearAllHud.Add_Click({
        param($s, $e)
        foreach ($c in $s.Tag) { $c.IsChecked = $false }
    })

    $btnSaveHudSel.Tag = $checkBoxes
    $btnSaveHudSel.Add_Click({
        param($s, $e)
        $newHidden = @()
        foreach ($c in $s.Tag) {
            if (-not [bool]$c.IsChecked) {
                $newHidden += "$($c.Tag)"
            }
        }
        $cfg = Load-CurrentConfig
        if (-not $cfg) {
            $cfg = New-Object PSObject
            $cfg | Add-Member -NotePropertyName "providers" -NotePropertyValue (@{ antigravity = @{ enabled = $true } }) -Force
        }
        $cfg | Add-Member -NotePropertyName "hidden_hud_gauges" -NotePropertyValue @($newHidden) -Force
        $cfg | Add-Member -NotePropertyName "onboarding_completed" -NotePropertyValue $true -Force
        Write-Utf8NoBom $ConfigFile ($cfg | ConvertTo-Json -Depth 6)
        $selWin.Close()
        try {
            Render-UI $global:currentData
            if ($global:isHudMode) {
                $window.Height = Get-HudHeight $global:currentData
                Render-HUD $global:currentData
            }
        } catch { Write-AppError $_.Exception }
    })

    $selWin.ShowDialog() | Out-Null
}

function Invoke-ProviderKeyTest ($provider, $key) {
    if (-not $key -or -not $key.Trim()) {
        return @{ ok = $false; provider = $provider; error = "Empty key" }
    }
    if ($DemoMode) {
        return @{ ok = $true; provider = $provider; status = "OK" }
    }
    if (-not $NodeExe) {
        return @{ ok = $false; provider = $provider; error = "Node.js not found" }
    }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $NodeExe
        $cleanKey = $key.Trim().Replace('"', '')
        $psi.Arguments = "`"$EngineScript`" --test-key $provider `"$cleanKey`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $proc = [System.Diagnostics.Process]::Start($psi)
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $started = Get-Date
        while (-not $proc.HasExited) {
            if (((Get-Date) - $started).TotalSeconds -gt 12) {
                try { $proc.Kill() } catch {}
                return @{ ok = $false; provider = $provider; error = "Timeout" }
            }
            $frame = New-Object System.Windows.Threading.DispatcherFrame
            $dt = New-Object System.Windows.Threading.DispatcherTimer
            $dt.Interval = [TimeSpan]::FromMilliseconds(40)
            $dt.Tag = $frame
            $dt.Add_Tick({ param($s, $e) $s.Stop(); $s.Tag.Continue = $false })
            $dt.Start()
            [System.Windows.Threading.Dispatcher]::PushFrame($frame)
        }
        $proc.WaitForExit()
        $rawOut = $outTask.Result
        if ($rawOut) {
            $parsed = $rawOut.Trim() | ConvertFrom-Json
            if ($parsed) { return $parsed }
        }
    } catch {
        return @{ ok = $false; provider = $provider; error = $_.Exception.Message }
    }
    return @{ ok = $false; provider = $provider; error = "Invalid key" }
}

function Wait-WpfDelayMs ($ms) {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $dt = New-Object System.Windows.Threading.DispatcherTimer
    $dt.Interval = [TimeSpan]::FromMilliseconds($ms)
    $dt.Tag = $frame
    $dt.Add_Tick({ param($s, $e) $s.Stop(); $s.Tag.Continue = $false })
    $dt.Start()
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

# 7. Settings Dialog with 6 Pastel Palette Swatches & Live API Key Validation
function Show-SettingsDialog {
    [xml]$cfgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Settings - AI Gauge" Height="680" Width="480"
        WindowStartupLocation="CenterOwner" Background="#18181A" ResizeMode="NoResize"
        UseLayoutRounding="True" SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Display" TextOptions.TextRenderingMode="ClearType"
        FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Name="Bd" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.88"/></Trigger>
                            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.45"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Text="Settings - AI Providers &amp; Pastel Colors" Foreground="#FFFFFF" FontSize="14" FontWeight="Bold"/>
            <TextBlock Text="Enable providers, verify API keys and customize section colors:" Foreground="#888894" FontSize="10.5" Margin="0,3,0,0"/>
        </StackPanel>
        
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel Name="SettingsStack" Margin="0,0,6,0">
                <!-- HUD Side Bar Behavior -->
                <Border Background="#1E1E22" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <TextBlock Text="HUD Side Bar Behavior" Foreground="#A1A1AA" FontSize="10" FontWeight="Bold" Margin="0,0,0,6"/>
                        <CheckBox Name="ChkHudAutoHide" Content="Auto-hide HUD when idle" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                        <CheckBox Name="ChkHudShowOnActivity" Content="Show HUD automatically while an agent is working or waiting" Foreground="#CBD5E1" FontSize="10.5" Margin="18,6,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                </Border>

                <!-- Antigravity -->
                <Border Background="#1E1E22" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkAnti" Content="Antigravity" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelAnti" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <TextBlock Text="Detects IDE quotas while running or via headless probe." Foreground="#888894" FontSize="9.5" Margin="20,4,0,0"/>
                    </StackPanel>
                </Border>
                
                <!-- Claude -->
                <Border Background="#1E1E22" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkClaudePro" Content="Claude" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelClaude" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtClaudeProToken" Height="26" Background="#141416" Foreground="#FFFFFF" BorderBrush="#33333A" Padding="6,3" Margin="0,6,0,4"/>
                        <TextBlock Name="LinkClaudeToken" Text="OAuth Session Token (auto-detected) • Console -&gt;" Foreground="#38BDF8" FontSize="9.5" Cursor="Hand"/>
                    </StackPanel>
                </Border>
                
                <!-- ChatGPT -->
                <Border Background="#1E1E22" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkChatGPT" Content="ChatGPT" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelChatGPT" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtChatGPTToken" Height="26" Background="#141416" Foreground="#FFFFFF" BorderBrush="#33333A" Padding="6,3" Margin="0,6,0,4"/>
                        <TextBlock Text="Session / Access Token (3h window &amp; weekly o1 quota)" Foreground="#888894" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- Cursor -->
                <Border Background="#1E1E22" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkCursor" Content="Cursor" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelCursor" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtCursorToken" Height="26" Background="#141416" Foreground="#FFFFFF" BorderBrush="#33333A" Padding="6,3" Margin="0,6,0,4"/>
                        <TextBlock Name="LinkCursorToken" Text="Get Cursor Session / Account Settings (cursor.com) -&gt;" Foreground="#38BDF8" FontSize="9.5" Cursor="Hand"/>
                    </StackPanel>
                </Border>
                
                <!-- Copilot -->
                <Border Background="#1E1E22" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkCopilot" Content="Copilot" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelCopilot" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtCopilotToken" Height="26" Background="#141416" Foreground="#FFFFFF" BorderBrush="#33333A" Padding="6,3" Margin="0,6,0,4"/>
                        <TextBlock Name="LinkCopilotToken" Text="Get GitHub Personal Access Token (github.com/settings/tokens) -&gt;" Foreground="#38BDF8" FontSize="9.5" Cursor="Hand"/>
                    </StackPanel>
                </Border>
                
                <!-- Google Gemini -->
                <Border Background="#1E1E22" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkGemini" Content="Google Gemini" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelGemini" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <Grid Margin="0,6,0,4">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <PasswordBox Name="TxtGeminiKey" Grid.Column="0" Height="26" Background="#141416" Foreground="#FFFFFF" BorderBrush="#33333A" Padding="6,3" Margin="0,0,6,0"/>
                            <Button Name="BtnTestGemini" Grid.Column="1" Content="Test" Width="76" Height="26" Background="#282832" Foreground="#FFFFFF" BorderBrush="#383846" BorderThickness="1" FontSize="11" FontWeight="SemiBold"/>
                        </Grid>
                        <TextBlock Name="TxtGeminiStatus" Text="" Foreground="#00E699" FontSize="10" FontWeight="SemiBold" Margin="0,0,0,2" Visibility="Collapsed"/>
                        <TextBlock Name="LinkAiStudio" Text="Get API Key at Google AI Studio (aistudio.google.com) -&gt;" Foreground="#38BDF8" FontSize="9.5" Cursor="Hand"/>
                    </StackPanel>
                </Border>
                
                <!-- OpenAI -->
                <Border Background="#1E1E22" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkOpenAI" Content="OpenAI" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelOpenAI" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <Grid Margin="0,6,0,4">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <PasswordBox Name="TxtOpenAIKey" Grid.Column="0" Height="26" Background="#141416" Foreground="#FFFFFF" BorderBrush="#33333A" Padding="6,3" Margin="0,0,6,0"/>
                            <Button Name="BtnTestOpenAI" Grid.Column="1" Content="Test" Width="76" Height="26" Background="#282832" Foreground="#FFFFFF" BorderBrush="#383846" BorderThickness="1" FontSize="11" FontWeight="SemiBold"/>
                        </Grid>
                        <TextBlock Name="TxtOpenAIStatus" Text="" Foreground="#00E699" FontSize="10" FontWeight="SemiBold" Margin="0,0,0,2" Visibility="Collapsed"/>
                        <TextBlock Name="LinkOpenAIKeys" Text="Get OpenAI API Key (platform.openai.com/api-keys) -&gt;" Foreground="#38BDF8" FontSize="9.5" Cursor="Hand"/>
                    </StackPanel>
                </Border>
                
                <!-- Anthropic -->
                <Border Background="#1E1E22" BorderBrush="#2C2C30" BorderThickness="1" CornerRadius="8" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkClaude" Content="Anthropic" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelAnthropic" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <Grid Margin="0,6,0,4">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <PasswordBox Name="TxtClaudeKey" Grid.Column="0" Height="26" Background="#141416" Foreground="#FFFFFF" BorderBrush="#33333A" Padding="6,3" Margin="0,0,6,0"/>
                            <Button Name="BtnTestAnthropic" Grid.Column="1" Content="Test" Width="76" Height="26" Background="#282832" Foreground="#FFFFFF" BorderBrush="#383846" BorderThickness="1" FontSize="11" FontWeight="SemiBold"/>
                        </Grid>
                        <TextBlock Name="TxtAnthropicStatus" Text="" Foreground="#00E699" FontSize="10" FontWeight="SemiBold" Margin="0,0,0,2" Visibility="Collapsed"/>
                        <TextBlock Name="LinkAnthropicKeys" Text="Get Anthropic API Key (console.anthropic.com) -&gt;" Foreground="#38BDF8" FontSize="9.5" Cursor="Hand"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </ScrollViewer>
        
        <Grid Grid.Row="2" Margin="0,12,0,0">
            <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                <Button Name="BtnSave" Content="Save &amp; Refresh" Width="114" Height="28" Background="#00E699" Foreground="#121214" FontWeight="Bold" Margin="0,0,6,0" Cursor="Hand"/>
                <Button Name="BtnCfgScan" Content="Scan Subscriptions" Width="122" Height="28" Background="#282830" Foreground="#E5E7EB" BorderBrush="#3A3A46" BorderThickness="1" Margin="0,0,6,0" Cursor="Hand"/>
                <Button Name="BtnCfgHud" Content="HUD Gauges" Width="88" Height="28" Background="#282830" Foreground="#E5E7EB" BorderBrush="#3A3A46" BorderThickness="1" Cursor="Hand"/>
            </StackPanel>
            <Button Name="BtnCancel" Content="Cancel" Width="74" Height="28" HorizontalAlignment="Right" Background="#282830" Foreground="#E5E7EB" BorderBrush="#3A3A46" BorderThickness="1" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@

    $cfgReader = (New-Object System.Xml.XmlNodeReader $cfgXaml)
    $cfgWin = [System.Windows.Markup.XamlReader]::Load($cfgReader)
    # Owner can only be set on a window that has already been shown (WPF restriction).
    $ownerSet = $false
    try {
        if ($window -and $window.IsVisible) { $cfgWin.Owner = $window; $ownerSet = $true }
    } catch {}
    if (-not $ownerSet) {
        $cfgWin.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen
    }
    
    $chkAnti = $cfgWin.FindName("ChkAnti")
    $chkClaudePro = $cfgWin.FindName("ChkClaudePro")
    $txtClaudeProToken = $cfgWin.FindName("TxtClaudeProToken")
    $linkClaudeToken = $cfgWin.FindName("LinkClaudeToken")
    $chkChatGPT = $cfgWin.FindName("ChkChatGPT")
    $txtChatGPTToken = $cfgWin.FindName("TxtChatGPTToken")
    $chkCursor = $cfgWin.FindName("ChkCursor")
    $txtCursorToken = $cfgWin.FindName("TxtCursorToken")
    $linkCursorToken = $cfgWin.FindName("LinkCursorToken")
    $chkCopilot = $cfgWin.FindName("ChkCopilot")
    $txtCopilotToken = $cfgWin.FindName("TxtCopilotToken")
    $linkCopilotToken = $cfgWin.FindName("LinkCopilotToken")
    $chkGemini = $cfgWin.FindName("ChkGemini")
    $txtGeminiKey = $cfgWin.FindName("TxtGeminiKey")
    $btnTestGemini = $cfgWin.FindName("BtnTestGemini")
    $txtGeminiStatus = $cfgWin.FindName("TxtGeminiStatus")
    $linkAiStudio = $cfgWin.FindName("LinkAiStudio")
    $chkOpenAI = $cfgWin.FindName("ChkOpenAI")
    $txtOpenAIKey = $cfgWin.FindName("TxtOpenAIKey")
    $btnTestOpenAI = $cfgWin.FindName("BtnTestOpenAI")
    $txtOpenAIStatus = $cfgWin.FindName("TxtOpenAIStatus")
    $linkOpenAIKeys = $cfgWin.FindName("LinkOpenAIKeys")
    $chkClaude = $cfgWin.FindName("ChkClaude")
    $txtClaudeKey = $cfgWin.FindName("TxtClaudeKey")
    $btnTestAnthropic = $cfgWin.FindName("BtnTestAnthropic")
    $txtClaudeStatus = $cfgWin.FindName("TxtAnthropicStatus")
    $linkAnthropicKeys = $cfgWin.FindName("LinkAnthropicKeys")
    
    $pAnti = $cfgWin.FindName("ColorPanelAnti")
    $pClaude = $cfgWin.FindName("ColorPanelClaude")
    $pChatGPT = $cfgWin.FindName("ColorPanelChatGPT")
    $pCursor = $cfgWin.FindName("ColorPanelCursor")
    $pCopilot = $cfgWin.FindName("ColorPanelCopilot")
    $pGemini = $cfgWin.FindName("ColorPanelGemini")
    $pOpenAI = $cfgWin.FindName("ColorPanelOpenAI")
    $pAnthropic = $cfgWin.FindName("ColorPanelAnthropic")
    
    $btnSave = $cfgWin.FindName("BtnSave")
    $btnCfgScan = $cfgWin.FindName("BtnCfgScan")
    $btnCfgHud = $cfgWin.FindName("BtnCfgHud")
    $btnCancel = $cfgWin.FindName("BtnCancel")
    $chkHudAutoHide = $cfgWin.FindName("ChkHudAutoHide")
    $chkHudShowOnActivity = $cfgWin.FindName("ChkHudShowOnActivity")

    $currentCfg = Load-CurrentConfig
    $pData = if ($currentCfg -and $currentCfg.providers) { $currentCfg.providers } else { @{} }
    $sColors = if ($currentCfg -and $currentCfg.section_colors) { $currentCfg.section_colors } else { @{} }

    $autoHideEnabled = [bool]($currentCfg -and $currentCfg.hud_auto_hide)
    $showOnActEnabled = if ($currentCfg -and $null -ne $currentCfg.hud_show_on_activity) { [bool]$currentCfg.hud_show_on_activity } else { $true }
    $chkHudAutoHide.IsChecked = $autoHideEnabled
    $chkHudShowOnActivity.IsChecked = $showOnActEnabled
    $chkHudShowOnActivity.IsEnabled = $autoHideEnabled
    $chkHudShowOnActivity.Opacity = if ($autoHideEnabled) { 1.0 } else { 0.5 }
    $chkHudAutoHide.Add_Checked({
        $chkHudShowOnActivity.IsEnabled = $true
        $chkHudShowOnActivity.Opacity = 1.0
    })
    $chkHudAutoHide.Add_Unchecked({
        $chkHudShowOnActivity.IsEnabled = $false
        $chkHudShowOnActivity.Opacity = 0.5
    })

    # Helper: Populate Swatches
    $chosenColors = @{}
    $swatchPanels = @{
        "antigravity"          = $pAnti
        "claude_pro"           = $pClaude
        "chatgpt_subscription" = $pChatGPT
        "cursor"               = $pCursor
        "github_copilot"       = $pCopilot
        "gemini"               = $pGemini
        "openai"               = $pOpenAI
        "anthropic"            = $pAnthropic
    }

    foreach ($secKey in $swatchPanels.Keys) {
        $parentPanel = $swatchPanels[$secKey]
        $activeHex = if ($sColors.$secKey) { "$($sColors.$secKey)" } else { $PastelDefaults[$secKey] }
        $chosenColors[$secKey] = $activeHex
        $parentPanel.Tag = "$activeHex"

        $bordersList = @()
        foreach ($swatch in $PastelPalette) {
            $hex = $swatch.Hex
            $b = New-Object System.Windows.Controls.Border
            $b.Width = 14
            $b.Height = 14
            $b.CornerRadius = New-Object System.Windows.CornerRadius(7)
            $b.Background = Convert-HexToBrush $hex
            $b.Margin = New-Object System.Windows.Thickness(2, 0, 2, 0)
            $b.Cursor = [System.Windows.Input.Cursors]::Hand
            $b.ToolTip = $swatch.Name
            
            if ($hex.ToUpper() -eq $activeHex.ToUpper()) {
                $b.BorderBrush = [System.Windows.Media.Brushes]::White
                $b.BorderThickness = New-Object System.Windows.Thickness(2)
            } else {
                $b.BorderThickness = New-Object System.Windows.Thickness(0)
            }

            # State lives in WPF Tag properties (no closures / loop variables):
            # swatch.Tag = its hex; panel.Tag = currently chosen hex for that section.
            $b.Tag = $hex
            $b.Add_MouseLeftButtonDown({
                param($sender, $e)
                try {
                    $panel = $sender.Parent
                    $panel.Tag = "$($sender.Tag)"
                    foreach ($other in $panel.Children) {
                        $other.BorderThickness = New-Object System.Windows.Thickness(0)
                    }
                    $sender.BorderBrush = [System.Windows.Media.Brushes]::White
                    $sender.BorderThickness = New-Object System.Windows.Thickness(2)
                } catch { Write-AppError $_.Exception }
            })

            $bordersList += $b
            $parentPanel.Children.Add($b) | Out-Null
        }
    }

    # Load initial values (Never automatically re-enable disabled sessions)
    if ($pData.antigravity -and $null -ne $pData.antigravity.enabled) {
        $chkAnti.IsChecked = [bool]$pData.antigravity.enabled
    } else {
        $chkAnti.IsChecked = $false
    }

    if ($pData.claude_pro -and $null -ne $pData.claude_pro.enabled) {
        $chkClaudePro.IsChecked = [bool]$pData.claude_pro.enabled
        $txtClaudeProToken.Password = "$($pData.claude_pro.token)"
    } else {
        $chkClaudePro.IsChecked = $false
    }
    
    if ($pData.chatgpt_subscription -and $null -ne $pData.chatgpt_subscription.enabled) {
        $chkChatGPT.IsChecked = [bool]$pData.chatgpt_subscription.enabled
        $txtChatGPTToken.Password = "$($pData.chatgpt_subscription.token)"
    } else {
        $chkChatGPT.IsChecked = $false
    }

    if ($pData.cursor -and $null -ne $pData.cursor.enabled) {
        $chkCursor.IsChecked = [bool]$pData.cursor.enabled
        $txtCursorToken.Password = "$($pData.cursor.token)"
    } else {
        $chkCursor.IsChecked = $false
    }

    if ($pData.github_copilot -and $null -ne $pData.github_copilot.enabled) {
        $chkCopilot.IsChecked = [bool]$pData.github_copilot.enabled
        $txtCopilotToken.Password = "$($pData.github_copilot.token)"
    } else {
        $chkCopilot.IsChecked = $false
    }

    if ($pData.gemini -and $null -ne $pData.gemini.enabled) {
        $chkGemini.IsChecked = [bool]$pData.gemini.enabled
        $txtGeminiKey.Password = "$($pData.gemini.api_key)"
    } else {
        $chkGemini.IsChecked = $false
    }

    if ($pData.openai -and $null -ne $pData.openai.enabled) {
        $chkOpenAI.IsChecked = [bool]$pData.openai.enabled
        $txtOpenAIKey.Password = "$($pData.openai.api_key)"
    } else {
        $chkOpenAI.IsChecked = $false
    }

    if ($pData.anthropic -and $null -ne $pData.anthropic.enabled) {
        $chkClaude.IsChecked = [bool]$pData.anthropic.enabled
        $txtClaudeKey.Password = "$($pData.anthropic.api_key)"
    } else {
        $chkClaude.IsChecked = $false
    }

    $linkMap = @(
        @{ Ctrl = $linkAiStudio;      Url = "https://aistudio.google.com/app/apikey" },
        @{ Ctrl = $linkClaudeToken;   Url = "https://console.anthropic.com/settings/keys" },
        @{ Ctrl = $linkCursorToken;   Url = "https://www.cursor.com/settings" },
        @{ Ctrl = $linkCopilotToken;  Url = "https://github.com/settings/tokens" },
        @{ Ctrl = $linkOpenAIKeys;    Url = "https://platform.openai.com/api-keys" },
        @{ Ctrl = $linkAnthropicKeys; Url = "https://console.anthropic.com/settings/keys" }
    )
    foreach ($lm in $linkMap) {
        if ($lm.Ctrl) {
            $lm.Ctrl.Tag = $lm.Url
            $lm.Ctrl.Add_MouseLeftButtonUp({
                param($s, $e)
                if ($s.Tag) { try { [System.Diagnostics.Process]::Start("$($s.Tag)") } catch { Write-AppError $_.Exception } }
            })
        }
    }

    if ($btnCfgScan) {
        $btnCfgScan.Add_Click({
            $cfgWin.Close()
            Start-SubscriptionScan
        })
    }

    if ($btnCfgHud) {
        $btnCfgHud.Add_Click({
            if ($global:currentData -and $global:currentData.groups -and $global:currentData.groups.Count -gt 0) {
                Show-HudGaugeSelectionDialog $global:currentData
            } else {
                [System.Windows.MessageBox]::Show("Run 'Scan Subscriptions' or connect an API key first so AI Gauge detects active gauges.", "HUD Gauges", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information) | Out-Null
            }
        })
    }

    $apiTestState = @{
        Validated = @{ gemini = $false; openai = $false; anthropic = $false }
        TestedVal = @{ gemini = ""; openai = ""; anthropic = "" }
        Items     = @(
            @{ Prov = "gemini";    Box = $txtGeminiKey; Btn = $btnTestGemini;    Status = $txtGeminiStatus; Chk = $chkGemini },
            @{ Prov = "openai";    Box = $txtOpenAIKey; Btn = $btnTestOpenAI;    Status = $txtOpenAIStatus; Chk = $chkOpenAI },
            @{ Prov = "anthropic"; Box = $txtClaudeKey; Btn = $btnTestAnthropic; Status = $txtClaudeStatus; Chk = $chkClaude }
        )
    }

    foreach ($item in $apiTestState.Items) {
        $pName = $item.Prov
        $pObj = $pData.$pName
        if ($pObj -and $pObj.api_key_ok -eq $true -and "$($pObj.api_key)".Trim()) {
            $apiTestState.Validated[$pName] = $true
            $apiTestState.TestedVal[$pName] = "$($pObj.api_key)".Trim()
            $item.Btn.Content = "✓ OK"
            $item.Btn.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x10, 0x3A, 0x2A)))
            $item.Btn.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
            $item.Status.Text = "✓ OK — Valid API Key"
            $item.Status.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
            $item.Status.Visibility = [System.Windows.Visibility]::Visible
        }

        $ctx = @{
            Prov   = $pName
            Box    = $item.Box
            Btn    = $item.Btn
            Status = $item.Status
            Chk    = $item.Chk
            State  = $apiTestState
        }
        $item.Box.Tag = $ctx
        $item.Box.Add_PasswordChanged({
            param($s, $e)
            $c = $s.Tag
            $cur = $s.Password.Trim()
            if ($cur -ne $c.State.TestedVal[$c.Prov]) {
                $c.State.Validated[$c.Prov] = $false
                $c.Btn.Content = "Test"
                $c.Btn.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x32)))
                $c.Btn.Foreground = [System.Windows.Media.Brushes]::White
                $c.Status.Text = ""
                $c.Status.Visibility = [System.Windows.Visibility]::Collapsed
            }
        })

        $item.Btn.Tag = $ctx
        $item.Btn.Add_Click({
            param($s, $e)
            $c = $s.Tag
            $keyVal = $c.Box.Password.Trim()
            if (-not $keyVal) {
                $c.Status.Text = "⚠️ Enter an API key first"
                $c.Status.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF5, 0xA6, 0x23)))
                $c.Status.Visibility = [System.Windows.Visibility]::Visible
                return
            }
            $s.IsEnabled = $false
            $s.Content = "Loading..."
            $c.Status.Text = "Testing API key..."
            $c.Status.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x94, 0xA3, 0xB8)))
            $c.Status.Visibility = [System.Windows.Visibility]::Visible

            $res = Invoke-ProviderKeyTest $c.Prov $keyVal
            $s.IsEnabled = $true
            if ($res -and $res.ok -eq $true) {
                $c.State.Validated[$c.Prov] = $true
                $c.State.TestedVal[$c.Prov] = $keyVal
                $c.Chk.IsChecked = $true
                $s.Content = "✓ OK"
                $s.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x10, 0x3A, 0x2A)))
                $s.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
                $c.Status.Text = "✓ OK — Valid API Key"
                $c.Status.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
            } else {
                $c.State.Validated[$c.Prov] = $false
                $c.State.TestedVal[$c.Prov] = ""
                $s.Content = "Test"
                $s.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x32)))
                $s.Foreground = [System.Windows.Media.Brushes]::White
                $c.Status.Text = "✕ Invalid API Key or unauthorized"
                $c.Status.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xFF, 0x4D, 0x4F)))
            }
            $c.Status.Visibility = [System.Windows.Visibility]::Visible
        })
    }

    $btnSave.Tag = @{
        CfgWin       = $cfgWin
        SwatchPanels = $swatchPanels
        ApiTestState = $apiTestState
        ChkHudAutoHide = $chkHudAutoHide
        ChkHudShowOnActivity = $chkHudShowOnActivity
        ChkAnti      = $chkAnti
        ChkClaudePro = $chkClaudePro
        TxtClaudePro = $txtClaudeProToken
        ChkChatGPT   = $chkChatGPT
        TxtChatGPT   = $txtChatGPTToken
        ChkCursor    = $chkCursor
        TxtCursor    = $txtCursorToken
        ChkCopilot   = $chkCopilot
        TxtCopilot   = $txtCopilotToken
        ChkGemini    = $chkGemini
        TxtGemini    = $txtGeminiKey
        ChkOpenAI    = $chkOpenAI
        TxtOpenAI    = $txtOpenAIKey
        ChkClaude    = $chkClaude
        TxtClaude    = $txtClaudeKey
    }

    $btnSave.Add_Click({
        param($s, $e)
        $st = $s.Tag
        $s.IsEnabled = $false
        $s.Content = "Testing..."

        $anyNewlyValidated = $false
        foreach ($item in $st.ApiTestState.Items) {
            $p = $item.Prov
            $kv = $item.Box.Password.Trim()
            if ($kv -and (-not $st.ApiTestState.Validated[$p] -or $kv -ne $st.ApiTestState.TestedVal[$p])) {
                $item.Status.Text = "Testing API key..."
                $item.Status.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x94, 0xA3, 0xB8)))
                $item.Status.Visibility = [System.Windows.Visibility]::Visible
                $item.Btn.Content = "..."
                $res = Invoke-ProviderKeyTest $p $kv
                if ($res -and $res.ok -eq $true) {
                    $anyNewlyValidated = $true
                    $st.ApiTestState.Validated[$p] = $true
                    $st.ApiTestState.TestedVal[$p] = $kv
                    $item.Chk.IsChecked = $true
                    $item.Btn.Content = "✓ OK"
                    $item.Btn.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x10, 0x3A, 0x2A)))
                    $item.Btn.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
                    $item.Status.Text = "✓ OK — Valid API Key"
                    $item.Status.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
                } else {
                    $st.ApiTestState.Validated[$p] = $false
                    $st.ApiTestState.TestedVal[$p] = ""
                    $item.Btn.Content = "Test"
                    $item.Btn.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x32)))
                    $item.Btn.Foreground = [System.Windows.Media.Brushes]::White
                    $item.Status.Text = "✕ Invalid API Key or unauthorized"
                    $item.Status.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xFF, 0x4D, 0x4F)))
                }
            }
        }

        if ($anyNewlyValidated) {
            $s.Content = "✓ OK"
            Wait-WpfDelayMs 450
        }

        $colorsOut = @{}
        foreach ($k in $st.SwatchPanels.Keys) {
            $v = "$($st.SwatchPanels[$k].Tag)"
            if ($v) { $colorsOut[$k] = $v }
        }

        $gemKey = $st.TxtGemini.Password.Trim()
        $openKey = $st.TxtOpenAI.Password.Trim()
        $antKey = $st.TxtClaude.Password.Trim()

        $newCfg = @{
            providers = @{
                antigravity          = @{ enabled = [bool]$st.ChkAnti.IsChecked }
                claude_pro           = @{ enabled = [bool]$st.ChkClaudePro.IsChecked; token = $st.TxtClaudePro.Password.Trim() }
                chatgpt_subscription = @{ enabled = [bool]$st.ChkChatGPT.IsChecked; token = $st.TxtChatGPT.Password.Trim() }
                cursor               = @{ enabled = [bool]$st.ChkCursor.IsChecked; token = $st.TxtCursor.Password.Trim() }
                github_copilot       = @{ enabled = [bool]$st.ChkCopilot.IsChecked; token = $st.TxtCopilot.Password.Trim() }
                gemini               = @{ enabled = [bool]$st.ChkGemini.IsChecked; api_key = $gemKey; api_key_ok = [bool]($gemKey -and $st.ApiTestState.Validated["gemini"]) }
                openai               = @{ enabled = [bool]$st.ChkOpenAI.IsChecked; api_key = $openKey; api_key_ok = [bool]($openKey -and $st.ApiTestState.Validated["openai"]) }
                anthropic            = @{ enabled = [bool]$st.ChkClaude.IsChecked; api_key = $antKey; api_key_ok = [bool]($antKey -and $st.ApiTestState.Validated["anthropic"]) }
            }
            section_colors = $colorsOut
            refresh_interval_seconds = 30
            hidden_hud_gauges = @(Get-HiddenGauges)
            hud_auto_hide = [bool]$st.ChkHudAutoHide.IsChecked
            hud_show_on_activity = [bool]$st.ChkHudShowOnActivity.IsChecked
            onboarding_completed = $true
        }
        
        $jsonStr = $newCfg | ConvertTo-Json -Depth 5
        Write-Utf8NoBom $ConfigFile $jsonStr
        try {
            $acl = Get-Acl -Path $ConfigFile
            $acl.SetAccessRuleProtection($true, $false)
            $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user, "FullControl", "Allow")
            $acl.AddAccessRule($rule)
            Set-Acl -Path $ConfigFile -AclObject $acl
        } catch {}
        $st.CfgWin.Close()
        # Repaint immediately with the new colors (cockpit + HUD), then fetch fresh data
        try { Redraw-All } catch { Write-AppError $_.Exception }
        try { Apply-HudAutoHidePolicy } catch {}
        Refresh-Data
    })
    
    $btnCancel.Add_Click({
        $cfgWin.Close()
    })
    
    $cfgWin.ShowDialog() | Out-Null
}

function Refresh-Data {
    if ($global:quotaFetch) { return }
    $btnRefresh.Content = "Refreshing..."
    $btnRefresh.IsEnabled = $false
    Start-QuotaFetch $true
}

# Called on the UI thread when a quota fetch (async) finishes.
function Redraw-All {
    if ($global:currentData) {
        Render-UI $global:currentData
        if ($global:isHudMode) { Render-HUD $global:currentData }
        Apply-HudAutoHidePolicy
    }
}

function Complete-QuotaFetch ($newData) {
    $wasScan = $global:lastFetchWasScan
    $global:lastFetchWasScan = $false
    $global:lastQuotaFetchAt = Get-Date

    $targetPoll = Get-EffectivePollSeconds $newData
    if ($targetPoll -ne $global:currentPollSeconds -and $timer) {
        $global:currentPollSeconds = $targetPoll
        $timer.Interval = [TimeSpan]::FromSeconds($targetPoll)
    }

    $hasGroups = ($newData -and $newData.groups -and $newData.groups.Count -gt 0)
    $nodeMissing = ($newData -and $newData.node_missing)

    if ($wasScan) {
        $global:scanEmptyNotice = (-not $hasGroups -and -not $nodeMissing)
    } elseif ($hasGroups) {
        $global:scanEmptyNotice = $false
    }

    Render-UI $newData
    if ($global:isHudMode) {
        $window.Width = $global:HudWidth
        $window.Height = Get-HudHeight $newData
        Render-HUD $newData
    }
    if ($newData) {
        $cfAnn = $newData.announcement
        $cfAnnIsAd = ($cfAnn -and "$($cfAnn.type)" -eq "publicidade")
        $cfAdPromo = if ($newData.promo) { $newData.promo } elseif ($cfAnnIsAd) { $cfAnn } else { $null }
        if ($cfAdPromo) { Show-PromoToast $cfAdPromo }
    }
    $btnRefresh.Content = "↻ Refresh"
    $btnRefresh.IsEnabled = $true

    if ($wasScan) {
        $global:initialLoad = $false
        if ($hasGroups -and -not $nodeMissing) {
            Show-HudGaugeSelectionDialog $newData
        }
        return
    }

    # First run: ask which gauges to keep in the HUD Bar as soon as subscriptions are detected.
    if ($global:initialLoad) {
        $global:initialLoad = $false
        if (-not $nodeMissing -and $hasGroups) {
            $cfg = Load-CurrentConfig
            if (-not $cfg -or $cfg.onboarding_completed -ne $true) {
                Show-HudGaugeSelectionDialog $newData
            }
        }
    }
}

# Event Listeners
$btnRefresh.Add_Click({ Refresh-Data })
$btnSettings.Add_Click({ Show-SettingsDialog })

$txtHudBrand = $window.FindName("TxtHudBrand")
if ($txtHudBrand) {
    $txtHudBrand.Add_MouseLeftButtonUp({
        param($s, $e)
        if ($e.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
            $mid = ""
            if (Test-Path $DeviceIdFile) { $mid = (Get-Content $DeviceIdFile -Raw).Trim() }
            $dUrl = if ($mid) { "https://ai-gauge.vh2c.com.br/donate?mid=$mid" } else { "https://ai-gauge.vh2c.com.br/donate" }
            [System.Diagnostics.Process]::Start($dUrl)
        }
    })
    $txtHudBrand.Add_MouseEnter({ $txtHudBrand.Foreground = [System.Windows.Media.Brushes]::White })
    $txtHudBrand.Add_MouseLeave({ $txtHudBrand.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x88, 0x88, 0x94))) })
}

if ($txtBrand) {
    $txtBrand.Add_MouseLeftButtonUp({
        param($s, $e)
        if ($e.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
            $mid = ""
            if (Test-Path $DeviceIdFile) { $mid = (Get-Content $DeviceIdFile -Raw).Trim() }
            $dUrl = if ($mid) { "https://ai-gauge.vh2c.com.br/donate?mid=$mid" } else { "https://ai-gauge.vh2c.com.br/donate" }
            [System.Diagnostics.Process]::Start($dUrl)
        }
    })
}

# Initial Load: runs after the window is rendered (never before, so dialogs can use it as Owner)
$txtAcc.Text = "Loading quotas..."
$window.Add_ContentRendered({
    if ($global:contentRenderedOnce) { return }
    $global:contentRenderedOnce = $true
    Start-QuotaFetch $false
})

# Keep the app alive on handler errors and log them instead of crashing
$window.Dispatcher.Add_UnhandledException({
    param($sender, $e)
    Write-AppError $e.Exception
    $e.Handled = $true
})

# Adaptive Auto-refresh Timer (30s active / 5 min idle) + Passive 10s Activity Probe
$global:currentPollSeconds = 30
$global:lastQuotaFetchAt = [DateTime]::MinValue
$global:activityFetch = $null

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
$timer.Add_Tick({ Refresh-Data })
$timer.Start()

$global:activityPoll = New-Object System.Windows.Threading.DispatcherTimer
$global:activityPoll.Interval = [TimeSpan]::FromMilliseconds(150)
$global:activityPoll.Add_Tick({
    $af = $global:activityFetch
    if (-not $af) { $global:activityPoll.Stop(); return }
    $timedOut = (((Get-Date) - $af.Started).TotalSeconds -gt 8)
    if (-not $af.Proc.HasExited -and -not $timedOut) { return }
    $global:activityPoll.Stop()
    $global:activityFetch = $null
    try {
        if (-not $af.Proc.HasExited) {
            $af.Proc.Kill()
        } else {
            $af.Proc.WaitForExit()
            if ($af.Proc.ExitCode -eq 0) {
                $json = $af.Out.Result
                if ($json -and $global:currentData) {
                    $act = $json | ConvertFrom-Json
                    if ($act) {
                        $prevFp = Get-ActivityFingerprint $global:currentData.activity
                        $nextFp = Get-ActivityFingerprint $act
                        if ($global:currentData.PSObject.Properties["activity"]) {
                            $global:currentData.activity = $act
                        } else {
                            Add-Member -InputObject $global:currentData -NotePropertyName "activity" -NotePropertyValue $act -Force
                        }
                        if ($global:currentData.PSObject.Properties["recommended_poll_seconds"]) {
                            $global:currentData.recommended_poll_seconds = $act.recommended_poll_seconds
                        } else {
                            Add-Member -InputObject $global:currentData -NotePropertyName "recommended_poll_seconds" -NotePropertyValue $act.recommended_poll_seconds -Force
                        }
                        $targetPoll = Get-EffectivePollSeconds $global:currentData
                        if ($targetPoll -ne $global:currentPollSeconds) {
                            $global:currentPollSeconds = $targetPoll
                            $timer.Interval = [TimeSpan]::FromSeconds($targetPoll)
                        }
                        if ($prevFp -ne $nextFp) {
                            Redraw-All
                        } else {
                            Apply-HudAutoHidePolicy
                        }
                        if ($act.transition_to_idle -or $act.transition_to_active) {
                            Refresh-Data
                        }
                    }
                }
            }
        }
    } catch {}
})

$global:activityTimer = New-Object System.Windows.Threading.DispatcherTimer
$global:activityTimer.Interval = [TimeSpan]::FromSeconds(10)
$global:activityTimer.Add_Tick({
    if ($DemoMode -or -not $NodeExe -or $global:quotaFetch -or $global:activityFetch -or -not $global:currentData) { return }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $NodeExe
        $psi.Arguments = "`"$EngineScript`" --activity-only"
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $proc = [System.Diagnostics.Process]::Start($psi)
        $global:activityFetch = @{
            Proc    = $proc
            Out     = $proc.StandardOutput.ReadToEndAsync()
            Err     = $proc.StandardError.ReadToEndAsync()
            Started = Get-Date
        }
        $global:activityPoll.Start()
    } catch {}
})
$global:activityTimer.Start()

$window.ShowDialog() | Out-Null
