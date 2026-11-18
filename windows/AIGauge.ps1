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

# Demo mode (--demo): fictitious accounts, isolated config, no Node, no telemetry.
$DemoMode = ($args -contains "--demo")

$ConfigDir = Join-Path $env:USERPROFILE ".config\UniversalAIQuota"
if ($DemoMode) { $ConfigDir = Join-Path $env:TEMP "AIGaugeDemo" }
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}
$ConfigFile = Join-Path $ConfigDir "config.json"
if ($DemoMode -and -not (Test-Path $ConfigFile)) {
    [IO.File]::WriteAllText($ConfigFile, '{"providers":{},"hidden_hud_gauges":[],"onboarding_completed":true}', [Text.Encoding]::UTF8)
}
$DeviceIdFile = Join-Path $ConfigDir "device_id"

# First run without config (e.g. installed via Setup.exe): detect installed AI tools and write a starter config.
function Initialize-DefaultConfig {
    if (Test-Path $ConfigFile) { return }
    try {
        $up = $env:USERPROFILE
        $hasClaude = (Test-Path (Join-Path $up ".claude")) -or [bool](Get-Command "claude.cmd" -ErrorAction SilentlyContinue) -or [bool](Get-Command "claude.exe" -ErrorAction SilentlyContinue)
        $hasChatGPT = (Test-Path (Join-Path $up ".codex\auth.json")) -or (Test-Path (Join-Path $env:APPDATA "ChatGPT"))
        $hasCursor = (Test-Path (Join-Path $env:LOCALAPPDATA "Programs\cursor")) -or (Test-Path (Join-Path $env:APPDATA "Cursor")) -or [bool](Get-Process "Cursor" -ErrorAction SilentlyContinue)
        $hasCopilot = (Test-Path (Join-Path $env:APPDATA "Code\User\globalStorage\github.copilot-chat")) -or [bool](Get-Command "gh.exe" -ErrorAction SilentlyContinue)
        $hasGemini = [bool]$env:GEMINI_API_KEY
        $cfg = @{
            providers = @{
                antigravity = @{ enabled = $true }
                claude_pro = @{ enabled = [bool]$hasClaude }
                chatgpt_subscription = @{ enabled = [bool]$hasChatGPT }
                cursor = @{ enabled = [bool]$hasCursor }
                github_copilot = @{ enabled = [bool]$hasCopilot }
                gemini = @{ enabled = [bool]$hasGemini; api_key = if ($env:GEMINI_API_KEY) { $env:GEMINI_API_KEY } else { "" } }
                openai = @{ enabled = [bool]$env:OPENAI_API_KEY; api_key = if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY } else { "" } }
                anthropic = @{ enabled = [bool]$env:ANTHROPIC_API_KEY; api_key = if ($env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY } else { "" } }
            }
            refresh_interval_seconds = 30
            hidden_hud_gauges = @()
            onboarding_completed = $true
        }
        [IO.File]::WriteAllText($ConfigFile, ($cfg | ConvertTo-Json -Depth 5), [Text.Encoding]::UTF8)
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

function Load-CurrentConfig {
    if (Test-Path $ConfigFile) {
        try { return (Get-Content $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json) } catch {}
    }
    return $null
}

function Get-ProviderKey ($groupName, $providerName) {
    $gn = "$groupName".ToLower()
    $pn = "$providerName".ToLower()
    if ($pn.Contains("cursor") -or $gn.Contains("cursor")) { return "cursor" }
    if ($pn.Contains("copilot") -or $gn.Contains("copilot") -or $pn.Contains("github")) { return "github_copilot" }
    if ($pn.Contains("chatgpt") -or $gn.Contains("chatgpt")) { return "chatgpt_subscription" }
    if (($pn.Contains("claude") -or $gn.Contains("claude")) -and -not $gn.Contains("claude and gpt")) { return "claude_pro" }
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
    if ($bn.ToLower().Contains("argon")) { return "Argon" }
    if ($bn.ToLower().Contains("gpt-4o")) { return "GPT-4o" }
    if ($bn.ToLower().Contains("o1")) { return "o1 Reasoning" }
    if ($bn.ToLower().Contains("gemini")) { return "Gemini" }
    if ($bn.ToLower().Contains("claude")) { return "Claude" }
    if ($gn.ToLower().Contains("gemini")) { return "Gemini" }
    if ($gn.ToLower().Contains("claude")) { return "Claude" }
    if ($gn.ToLower().Contains("chatgpt")) { return "ChatGPT" }
    if ($gn.ToLower().Contains("cursor")) { return "Cursor" }
    if ($gn.ToLower().Contains("copilot")) { return "Copilot" }
    
    $clean = $bn -replace '(?i)\b(Weekly|Limit|Remaining|Five|Hour|Hours|5h|3h|7d)\b', ''
    $clean = $clean.Trim()
    if ($clean.Length -gt 0) { return $clean }
    return $bn
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

function Start-QuotaFetch ($force = $false) {
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
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $NodeExe
        # --startup: the app was just opened, so the engine contacts the AI Gauge API once (version/announcements).
        # Later refreshes only read the local cache (the engine re-checks after 24h).
        $psi.Arguments = "`"$EngineScript`""
        if ($force) { $psi.Arguments += " --force" }
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
        Write-AppError $_.Exception
        Complete-QuotaFetch $null
    }
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
        Title="AI Gauge - Universal AI Quota Cockpit" Height="650" Width="480"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
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
    
    <Border Name="RootBorder" Background="#161619" BorderBrush="#2C2C34" BorderThickness="1" CornerRadius="12">
        <Grid>
            <!-- 1. FULL COCKPIT VIEW -->
            <Grid Name="CockpitView" Margin="16" Visibility="Visible">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                
                <!-- Custom Cockpit TitleBar -->
                <Grid Name="CockpitTitleBar" Grid.Row="0" Height="32" Background="Transparent" Margin="0,0,0,4">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Image Name="AppLogo" Width="18" Height="18" Margin="0,0,8,0" VerticalAlignment="Center"/>
                        <TextBlock Text="AI Gauge - Universal AI Quota Cockpit" Foreground="#B4B4BE" FontSize="12.5" FontWeight="SemiBold"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <Button Name="BtnMin" Content="—" Width="28" Height="24" Background="#24242C" Foreground="#9CA3AF" BorderBrush="#353542" BorderThickness="1" FontSize="11" FontWeight="Bold" Cursor="Hand" Margin="0,0,4,0"/>
                        <Button Name="BtnTopClose" Content="✕" Width="28" Height="24" Background="#24242C" Foreground="#9CA3AF" BorderBrush="#353542" BorderThickness="1" FontSize="11" FontWeight="Bold" Cursor="Hand"/>
                    </StackPanel>
                </Grid>
                
                <!-- Subtitle / Account Info -->
                <StackPanel Grid.Row="1" Margin="2,2,0,12">
                    <TextBlock Name="TxtAppName" Text="AI Gauge" Foreground="White" FontSize="21" FontWeight="Bold"/>
                    <TextBlock Name="TxtAccount" Text="Loading quotas..." Foreground="#E5E7EB" FontSize="13.5" Margin="0,4,0,0"/>
                    <TextBlock Name="TxtUpdated" Text="" Foreground="#888894" FontSize="11.5" Margin="0,3,0,0"/>
                    <Border Height="1" Background="#2C2C34" Margin="0,12,0,0"/>
                </StackPanel>
                
                <!-- Cards List -->
                <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                    <StackPanel Name="CardsPanel" Margin="0,0,4,0"/>
                </ScrollViewer>
                
                <!-- Cockpit Footer (4 equal-width buttons, like the Mac) -->
                <StackPanel Grid.Row="3" Margin="0,12,0,0">
                    <Grid>
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <Button Name="BtnRefresh" Grid.Column="0" Content="↻ Refresh" Height="34" Margin="0,0,6,0" Background="#F2F2F4" Foreground="#1C1C1E" BorderThickness="0" FontWeight="SemiBold" FontSize="12.5" Cursor="Hand"/>
                        <Button Name="BtnHud" Grid.Column="1" Content="⤢ HUD Bar" Height="34" Margin="0,0,6,0" Background="#F2F2F4" Foreground="#1C1C1E" BorderThickness="0" FontWeight="SemiBold" FontSize="12.5" Cursor="Hand"/>
                        <Button Name="BtnSettings" Grid.Column="2" Content="⚙ Settings" Height="34" Margin="0,0,6,0" Background="#F2F2F4" Foreground="#1C1C1E" BorderThickness="0" FontWeight="SemiBold" FontSize="12.5" Cursor="Hand"/>
                        <Button Name="BtnClose" Grid.Column="3" Content="✕ Close" Height="34" Background="#F2F2F4" Foreground="#1C1C1E" BorderThickness="0" FontWeight="SemiBold" FontSize="12.5" Cursor="Hand"/>
                    </Grid>
                    
                    <!-- Brand Link -->
                    <TextBlock Name="TxtBrand" Text="Developed by vh2c.com.br"
                               ToolTip="Support AI Gauge via Stripe Donation"
                               Foreground="#8A8A96" FontSize="12" FontWeight="SemiBold"
                               HorizontalAlignment="Center" Margin="0,10,0,0" Cursor="Hand"/>
                </StackPanel>
            </Grid>
            
            <!-- 2. COMPACT HUD BAR VIEW (Mac-identical aesthetic) -->
            <Border Name="HudView" Background="Transparent" Padding="6,8,6,6" Visibility="Collapsed" CornerRadius="14">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- HUD Top Controls (Mac-identical: borderless icons) -->
                    <Grid Grid.Row="0" Margin="2,0,2,6" Height="22">
                        <Button Name="BtnHudCockpit" Content="⤢" Width="24" Height="22" HorizontalAlignment="Left" ToolTip="Cockpit Mode (Ctrl+M)" Background="Transparent" Foreground="#A6A6AE" BorderThickness="0" FontSize="13" FontWeight="Bold" Cursor="Hand"/>
                        <Button Name="BtnHudMenu" Content="⋯" Width="24" Height="22" HorizontalAlignment="Center" ToolTip="Options" Background="Transparent" Foreground="#A6A6AE" BorderThickness="0" FontSize="15" FontWeight="Bold" Cursor="Hand"/>
                        <Button Name="BtnHudClose" Content="✕" Width="24" Height="22" HorizontalAlignment="Right" ToolTip="Close AI Gauge" Background="Transparent" Foreground="#A6A6AE" BorderThickness="0" FontSize="10.5" FontWeight="Bold" Cursor="Hand"/>
                    </Grid>
                    
                    <!-- HUD Tachometer Gauges List (Zero wide scrollbar, smooth wheel scroll) -->
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Hidden" HorizontalScrollBarVisibility="Disabled">
                        <StackPanel Name="HudCardsPanel" HorizontalAlignment="Center"/>
                    </ScrollViewer>
                    
                    <!-- HUD Footer (VH2C / Stripe Donation Link) -->
                    <Border Grid.Row="2" Margin="0,5,0,2">
                        <TextBlock Name="TxtHudBrand" Text="vh2c.com.br" Foreground="#888894" FontSize="9" FontWeight="SemiBold"
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
        $frame = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconFile)
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
$cardsPanel = $window.FindName("CardsPanel")
$btnRefresh = $window.FindName("BtnRefresh")
$btnHud = $window.FindName("BtnHud")
$btnSettings = $window.FindName("BtnSettings")
$btnClose = $window.FindName("BtnClose")
$txtBrand = $window.FindName("TxtBrand")

$hudView = $window.FindName("HudView")
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
$global:HudWidth = 124

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

function Get-HudHeight ($data) {
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $hidden = Get-HiddenGauges
    $sections = 0
    $items = 0
    if ($data -and $data.groups) {
        foreach ($g in $data.groups) {
            $n = @(Get-VisibleBuckets $g $hidden).Count
            if ($n -gt 0) { $sections++; $items += $n }
        }
    }
    if ($items -eq 0) { return 175 }
    $calc = 64 + ($sections * 35) + ($items * 122) - 10
    $maxH = [Math]::Min(780, $workArea.Height - 60)
    return [Math]::Min($maxH, [Math]::Max(160, $calc))
}

function Set-HudChrome ($hud) {
    if ($hud) {
        $rootBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(0xF0, 0x18, 0x18, 0x18)))
        $rootBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2A, 0x2A, 0x2E)))
        $rootBorder.CornerRadius = (New-Object System.Windows.CornerRadius(14))
    } else {
        $rootBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x16, 0x16, 0x19)))
        $rootBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2C, 0x2C, 0x34)))
        $rootBorder.CornerRadius = (New-Object System.Windows.CornerRadius(12))
    }
}

function Set-HudGaugeHidden ($key, $hide) {
    $cfg = Load-CurrentConfig
    if (-not $cfg) { return }
    $list = @(Get-HiddenGauges | Where-Object { $_ -ne $key })
    if ($hide) { $list += $key }
    $cfg | Add-Member -NotePropertyName "hidden_hud_gauges" -NotePropertyValue @($list) -Force
    Set-Content -Path $ConfigFile -Value ($cfg | ConvertTo-Json -Depth 6) -Encoding UTF8
    if ($global:isHudMode) {
        $window.Height = Get-HudHeight $global:currentData
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

    $miCockpit = New-Object System.Windows.Controls.MenuItem
    $miCockpit.Header = "Open full window"
    $miCockpit.Add_Click({ Toggle-HudMode })
    $menu.Items.Add($miCockpit) | Out-Null

    $menu.PlacementTarget = $btnHudMenu
    $menu.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Bottom
    $menu.IsOpen = $true
}

function Toggle-HudMode {
    $workArea = [System.Windows.SystemParameters]::WorkArea
    if ($global:isHudMode) {
        # Switch back to Cockpit Mode
        $global:isHudMode = $false
        $hudView.Visibility = [System.Windows.Visibility]::Collapsed
        $cockpitView.Visibility = [System.Windows.Visibility]::Visible
        
        Set-HudChrome $false
        $window.Title = "AI Gauge - Universal AI Quota Cockpit"
        $window.Topmost = $false
        $window.Width = 480
        $window.Height = 650
        if ($null -ne $global:prevLeft -and $null -ne $global:prevTop) {
            $window.Left = $global:prevLeft
            $window.Top = $global:prevTop
        } else {
            $window.Left = [Math]::Max(0, ($workArea.Width - 480) / 2)
            $window.Top = [Math]::Max(0, ($workArea.Height - 650) / 2)
        }
        
        Render-UI $global:currentData
    } else {
        # Switch to HUD Bar Mode
        $global:isHudMode = $true
        $global:prevLeft = $window.Left
        $global:prevTop = $window.Top
        
        $cockpitView.Visibility = [System.Windows.Visibility]::Collapsed
        $hudView.Visibility = [System.Windows.Visibility]::Visible
        
        Set-HudChrome $true
        $hudH = Get-HudHeight $global:currentData
        
        $window.Title = "AI Gauge HUD"
        $window.Topmost = $true
        $window.Width = $global:HudWidth
        $window.Height = $hudH
        $window.Left = $workArea.Right - ($global:HudWidth + 16)
        $window.Top = [Math]::Max(20, ($workArea.Height - $hudH) / 2)
        
        Render-HUD $global:currentData
    }
}

# Window Controls
$btnMin.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
$btnTopClose.Add_Click({ $window.Close() })
$btnClose.Add_Click({ $window.Close() })
$btnHud.Add_Click({ Toggle-HudMode })

$btnHudClose.Add_Click({ $window.Close() })
$btnHudCockpit.Add_Click({ Toggle-HudMode })
$btnHudMenu.Add_Click({ Show-HudMenu })

# Dragging Support
$cockpitTitleBar.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        try { $window.DragMove() } catch {}
    }
})

$window.Add_MouseLeftButtonDown({
    param($s, $e)
    if ($global:isHudMode -and $e.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        try { $window.DragMove() } catch {}
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
    $annBorder.CornerRadius = (New-Object System.Windows.CornerRadius(8))
    $annBorder.Padding = (New-Object System.Windows.Thickness(16, 12, 16, 14))
    $annBorder.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 12))

    $annStack = New-Object System.Windows.Controls.StackPanel

    $annHead = New-Object System.Windows.Controls.TextBlock
    $annHead.Text = if ($ann.title) { "$($ann.title)" } elseif ($isVersao) { "New Version Available" } else { "Notice" }
    $annHead.FontWeight = [System.Windows.FontWeights]::Bold
    $annHead.FontSize = 14
    $annHead.Foreground = $titleC
    $annStack.Children.Add($annHead) | Out-Null

    $annMsg = New-Object System.Windows.Controls.TextBlock
    $annMsg.Text = "$($ann.message)"
    $annMsg.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $annMsg.FontSize = 12.5
    $annMsg.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xD9, 0xD9, 0xD9)))
    $annMsg.Margin = (New-Object System.Windows.Thickness(0, 4, 0, 0))
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
        $btnAct.MinWidth = 190
        $btnAct.Height = 30
        $btnAct.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $btnAct.Margin = (New-Object System.Windows.Thickness(0, 10, 0, 0))
        $btnAct.Padding = (New-Object System.Windows.Thickness(18, 0, 18, 0))
        $btnAct.Background = $btnFill
        $btnAct.BorderBrush = $btnBorder
        $btnAct.BorderThickness = (New-Object System.Windows.Thickness(1))
        $btnAct.Foreground = $titleC
        $btnAct.FontWeight = [System.Windows.FontWeights]::Bold
        $btnAct.FontSize = 12.5
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

# Independent advertising toast (same card as the macOS "AI GAUGE - Advertising" window).
$global:promoShownAt = $null
$global:promoWindow = $null
$global:promoRemaining = 0
$global:promoTimer = $null

function Close-PromoToast {
    try { if ($global:promoTimer) { $global:promoTimer.Stop() } } catch {}
    try { if ($global:promoWindow) { $global:promoWindow.Close() } } catch {}
    $global:promoWindow = $null
}

$global:AppStartedAt = Get-Date
$global:promoPending = $false
$global:promoPendingAd = $null
$global:promoDelayTimer = $null

# Shows the ad at most once every 6h (also across restarts) and only 1 minute after the app opened.
function Show-PromoToast ($ann) {
    if (-not $ann -or $global:promoWindow -or $global:promoPending) { return }
    $promoFile = Join-Path $ConfigDir "promo_last_shown"

    $last = 0
    if ($global:promoShownAt) { $last = [int][double]::Parse((Get-Date $global:promoShownAt -UFormat %s)) }
    if (-not $DemoMode -and (Test-Path $promoFile)) {
        try { $last = [Math]::Max($last, [int]((Get-Content $promoFile -Raw).Trim())) } catch {}
    }
    $nowEpoch = [int][double]::Parse((Get-Date -UFormat %s))
    if ($last -gt 0 -and (($nowEpoch - $last) -lt 21600)) { return }

    $initial = if ($DemoMode) { 6 } else { 60 }
    $wait = [Math]::Max(0.2, $initial - ((Get-Date) - $global:AppStartedAt).TotalSeconds)
    $global:promoPending = $true
    $global:promoPendingAd = $ann
    $global:promoDelayTimer = New-Object System.Windows.Threading.DispatcherTimer
    $global:promoDelayTimer.Interval = [TimeSpan]::FromSeconds($wait)
    $global:promoDelayTimer.Add_Tick({
        $global:promoDelayTimer.Stop()
        $global:promoPending = $false
        $global:promoShownAt = Get-Date
        if (-not $DemoMode) {
            try { Set-Content -Path (Join-Path $ConfigDir "promo_last_shown") -Value ([int][double]::Parse((Get-Date -UFormat %s))) -Encoding UTF8 } catch {}
        }
        Show-PromoToastNow $global:promoPendingAd
    })
    $global:promoDelayTimer.Start()
}

function Show-PromoToastNow ($ann) {
    if (-not $ann -or $global:promoWindow) { return }
    try {
        [xml]$toastXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AI Gauge" Width="404" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="True"
        Background="Transparent" ShowInTaskbar="False" Topmost="True" ResizeMode="NoResize">
    <Window.Resources>
        <Style TargetType="Button">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="13" Opacity="1" Name="Bd">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsEnabled" Value="False"><Setter TargetName="Bd" Property="Opacity" Value="0.4"/></Trigger>
                            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Bd" Property="Opacity" Value="0.88"/></Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Margin="14" Background="#16171F" BorderBrush="#1AFFFFFF" BorderThickness="1" CornerRadius="24" Padding="18,14,18,18">
        <Border.Effect><DropShadowEffect BlurRadius="30" ShadowDepth="8" Opacity="0.6"/></Border.Effect>
        <StackPanel>
            <StackPanel Orientation="Horizontal" Height="20">
                <Image Name="PromoIcon" Width="16" Height="16"/>
                <TextBlock Text="AI GAUGE - ADVERTISING" Foreground="#94A3B8" FontSize="11.5" FontWeight="Bold" Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <Border Name="MediaBox" Height="185" CornerRadius="16" ClipToBounds="True" Background="#0E1015" Margin="0,12,0,0" Visibility="Collapsed">
                <Image Name="PromoImage" Stretch="UniformToFill"/>
            </Border>
            <TextBlock Name="PromoTitle" FontSize="19" FontWeight="Bold" Foreground="White" TextWrapping="Wrap" Margin="0,14,0,6"/>
            <TextBlock Name="PromoText" FontSize="13.5" Foreground="#94A3B8" TextWrapping="Wrap" MaxHeight="62" TextTrimming="CharacterEllipsis" Margin="0,0,0,16"/>
            <Grid>
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
                <Button Name="BtnLater" Grid.Column="0" Height="44" Margin="0,0,5,0" Content="Not now" Background="#14FFFFFF" BorderBrush="#14FFFFFF" BorderThickness="1" Foreground="#E2E8F0" FontSize="14" FontWeight="SemiBold"/>
                <Button Name="BtnPromo" Grid.Column="1" Height="44" Margin="5,0,0,0" Content="View Details" BorderThickness="0" Foreground="White" FontSize="14" FontWeight="SemiBold">
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
            if (Test-Path $iconFile) { $tw.FindName("PromoIcon").Source = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconFile) }
        } catch {}

        # Optional image (loaded asynchronously; the box stays hidden if it fails)
        $imgUrl = "$($ann.image_url)".Trim()
        if ($imgUrl) {
            if ($imgUrl.StartsWith("http://")) { $imgUrl = "https://" + $imgUrl.Substring(7) }
            try {
                $img = $tw.FindName("PromoImage")
                $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
                $bmp.BeginInit()
                $bmp.UriSource = New-Object System.Uri($imgUrl)
                $bmp.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
                $bmp.EndInit()
                $img.Source = $bmp
                if ("$($ann.image_fit)" -eq "contain") { $img.Stretch = [System.Windows.Media.Stretch]::Uniform }
                $sc = 1.0
                if ($ann.image_scale) { $sc = [double]$ann.image_scale }
                if ($sc -ne 1.0) {
                    $img.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
                    $img.RenderTransform = New-Object System.Windows.Media.ScaleTransform($sc, $sc)
                }
                $img.Add_ImageFailed({ param($s, $e) $s.Parent.Visibility = [System.Windows.Visibility]::Collapsed })
                $tw.FindName("MediaBox").Visibility = [System.Windows.Visibility]::Visible
            } catch { Write-AppError $_.Exception }
        }

        # Action button (only when the ad has a link)
        $btnPromo = $tw.FindName("BtnPromo")
        $btnLater = $tw.FindName("BtnLater")
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
                try { [System.Diagnostics.Process]::Start("$($s.Tag)") } catch { Write-AppError $_.Exception }
                Close-PromoToast
            })
        } else {
            $btnPromo.Visibility = [System.Windows.Visibility]::Collapsed
            $btnLater.Margin = New-Object System.Windows.Thickness(0)
            [System.Windows.Controls.Grid]::SetColumnSpan($btnLater, 2)
        }

        # "Not now" is locked for duracao_segundos (countdown), like on macOS
        $global:promoRemaining = if ($ann.duracao_segundos) { [int]$ann.duracao_segundos } else { 0 }
        $btnLater.Add_Click({ param($s, $e) if ($global:promoRemaining -le 0) { Close-PromoToast } })
        if ($global:promoRemaining -gt 0) {
            $btnLater.IsEnabled = $false
            $btnLater.Content = "Not now ($($global:promoRemaining)s)"
            $global:promoTimer = New-Object System.Windows.Threading.DispatcherTimer
            $global:promoTimer.Interval = [TimeSpan]::FromSeconds(1)
            $global:promoTimer.Add_Tick({
                $global:promoRemaining--
                $lb = $global:promoWindow.FindName("BtnLater")
                if ($global:promoRemaining -le 0) {
                    $global:promoTimer.Stop()
                    $lb.IsEnabled = $true
                    $lb.Content = "Not now"
                } else {
                    $lb.Content = "Not now ($($global:promoRemaining)s)"
                }
            })
            $global:promoTimer.Start()
        }

        $tw.Add_MouseLeftButtonDown({ param($s, $e) try { $s.DragMove() } catch {} })
        $tw.Add_Closed({ $global:promoWindow = $null })
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

        # 1. Title Row
        $tRow = New-Object System.Windows.Controls.StackPanel
        $tRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $tRow.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 6))
        
        $tIcon = New-Object System.Windows.Controls.TextBlock
        $tIcon.Text = "🤖"
        $tIcon.FontSize = 18
        $tIcon.Margin = (New-Object System.Windows.Thickness(0, 0, 8, 0))
        $tIcon.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $tRow.Children.Add($tIcon) | Out-Null
        
        $tTitle = New-Object System.Windows.Controls.TextBlock
        $tTitle.Text = "No AI Records Found"
        $tTitle.FontSize = 14
        $tTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $tTitle.Foreground = [System.Windows.Media.Brushes]::White
        $tTitle.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $tRow.Children.Add($tTitle) | Out-Null
        $emptyStack.Children.Add($tRow) | Out-Null
        
        # 2. Explanation
        $tDesc = New-Object System.Windows.Controls.TextBlock
        $tDesc.Text = "We did not find any local accounts or active sessions (Antigravity, Claude, ChatGPT, Cursor or Copilot) on this machine."
        $tDesc.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $tDesc.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xBB, 0xBB, 0xC4)))
        $tDesc.FontSize = 11
        $tDesc.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 12))
        $emptyStack.Children.Add($tDesc) | Out-Null
        
        # 3. Guidance Box (How to connect via APIs or Tokens)
        $guideBox = New-Object System.Windows.Controls.Border
        $guideBox.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x14, 0x14, 0x18)))
        $guideBox.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x25, 0x25, 0x30)))
        $guideBox.BorderThickness = (New-Object System.Windows.Thickness(1))
        $guideBox.CornerRadius = (New-Object System.Windows.CornerRadius(6))
        $guideBox.Padding = (New-Object System.Windows.Thickness(12, 10, 12, 10))
        $guideBox.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 14))
        
        $guideStack = New-Object System.Windows.Controls.StackPanel
        
        $gHead = New-Object System.Windows.Controls.TextBlock
        $gHead.Text = "How to route and monitor your quotas:"
        $gHead.FontWeight = [System.Windows.FontWeights]::Bold
        $gHead.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x8F, 0xBC, 0xFF)))
        $gHead.FontSize = 10.5
        $gHead.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 6))
        $guideStack.Children.Add($gHead) | Out-Null
        
        $item1 = New-Object System.Windows.Controls.TextBlock
        $item1.Text = "• Google Gemini (Recommended): Create a free key at Google AI Studio (takes 30 seconds and needs no IDE installed)."
        $item1.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $item1.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xCC, 0xCC, 0xD4)))
        $item1.FontSize = 10
        $item1.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 4))
        $guideStack.Children.Add($item1) | Out-Null
        
        $item2 = New-Object System.Windows.Controls.TextBlock
        $item2.Text = "• OpenAI & Anthropic: Add your sk-... API keys to monitor quotas and request limits."
        $item2.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $item2.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xCC, 0xCC, 0xD4)))
        $item2.FontSize = 10
        $item2.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 4))
        $guideStack.Children.Add($item2) | Out-Null
        
        $item3 = New-Object System.Windows.Controls.TextBlock
        $item3.Text = "• Session Tokens: Enter your Claude Pro, ChatGPT or Cursor subscription token if you subscribe to those services."
        $item3.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $item3.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xCC, 0xCC, 0xD4)))
        $item3.FontSize = 10
        $guideStack.Children.Add($item3) | Out-Null
        
        $guideBox.Child = $guideStack
        $emptyStack.Children.Add($guideBox) | Out-Null
        
        # 4. Action Buttons
        $btnStack = New-Object System.Windows.Controls.StackPanel
        
        $btnConfig = New-Object System.Windows.Controls.Button
        $btnConfig.Content = "⚙ Configure Providers and API Keys"
        $btnConfig.Height = 32
        $btnConfig.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
        $btnConfig.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x12, 0x12, 0x14)))
        $btnConfig.FontWeight = [System.Windows.FontWeights]::Bold
        $btnConfig.FontSize = 11.5
        $btnConfig.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnConfig.Add_Click({ Show-SettingsDialog })
        $btnStack.Children.Add($btnConfig) | Out-Null
        
        $btnStudio = New-Object System.Windows.Controls.Button
        $btnStudio.Content = "🔗 Get a Free Key at Google AI Studio (aistudio.google.com) ->"
        $btnStudio.Height = 28
        $btnStudio.Margin = (New-Object System.Windows.Thickness(0, 6, 0, 0))
        $btnStudio.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x22, 0x22, 0x2B)))
        $btnStudio.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x38, 0xBD, 0xF8)))
        $btnStudio.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x32, 0x32, 0x40)))
        $btnStudio.BorderThickness = (New-Object System.Windows.Thickness(1))
        $btnStudio.FontSize = 10
        $btnStudio.FontWeight = [System.Windows.FontWeights]::SemiBold
        $btnStudio.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnStudio.Add_Click({ [System.Diagnostics.Process]::Start("https://aistudio.google.com/app/apikey") })
        $btnStack.Children.Add($btnStudio) | Out-Null
        
        $emptyStack.Children.Add($btnStack) | Out-Null
        $emptyBorder.Child = $emptyStack
        $cardsPanel.Children.Add($emptyBorder) | Out-Null
        return
    }
    
    $cacheInfo = if ($data.from_cache) { "Cache" } elseif ($DemoMode) { "Demo" } else { "Live" }
    $txtAcc.Text = "$($data.account)  •  Plan $($data.plan)"
    $txtUpdated.Text = "Updated at $($data.updated_at) ($cacheInfo)"
    
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

        $card = New-Object System.Windows.Controls.Border
        $card.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1F, 0x1F, 0x22))
        $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2C, 0x2C, 0x33))
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(10)
        $card.Padding = New-Object System.Windows.Thickness(16, 12, 16, 14)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
        
        $cardStack = New-Object System.Windows.Controls.StackPanel

        # Card header INSIDE the card: group title (left) + provider badge (right)
        $headerGrid = New-Object System.Windows.Controls.Grid
        $hCol1 = New-Object System.Windows.Controls.ColumnDefinition; $hCol1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $hCol2 = New-Object System.Windows.Controls.ColumnDefinition; $hCol2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
        $headerGrid.ColumnDefinitions.Add($hCol1)
        $headerGrid.ColumnDefinitions.Add($hCol2)

        $gbTitle = New-Object System.Windows.Controls.TextBlock
        $gbTitle.Text = "$($g.name)"
        $gbTitle.Foreground = [System.Windows.Media.Brushes]::White
        $gbTitle.FontSize = 16
        $gbTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $gbTitle.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
        [System.Windows.Controls.Grid]::SetColumn($gbTitle, 0)
        $headerGrid.Children.Add($gbTitle) | Out-Null

        $tagBadge = New-Object System.Windows.Controls.TextBlock
        $tagBadge.Text = $badgeLabel
        $tagBadge.Foreground = $accentBrush
        $tagBadge.FontSize = 10.5
        $tagBadge.FontWeight = [System.Windows.FontWeights]::Bold
        $tagBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.Grid]::SetColumn($tagBadge, 1)
        $headerGrid.Children.Add($tagBadge) | Out-Null
        $cardStack.Children.Add($headerGrid) | Out-Null

        $hSep = New-Object System.Windows.Controls.Border
        $hSep.Height = 1
        $hSep.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2C, 0x2C, 0x33))
        $hSep.Margin = New-Object System.Windows.Thickness(0, 10, 0, 8)
        $cardStack.Children.Add($hSep) | Out-Null
        
        $idx = 0
        foreach ($b in $g.buckets) {
            if ($idx -gt 0) {
                $sep = New-Object System.Windows.Controls.Border
                $sep.Height = 1
                $sep.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x2E))
                $sep.Margin = New-Object System.Windows.Thickness(0, 8, 0, 8)
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
            $tbName.FontSize = 14
            $tbName.FontWeight = [System.Windows.FontWeights]::SemiBold
            $tbName.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $tbName.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            [System.Windows.Controls.Grid]::SetColumn($tbName, 0)
            $row.Children.Add($tbName) | Out-Null

            if ($b.reset_in) {
                $tbReset = New-Object System.Windows.Controls.TextBlock
                $tbReset.Text = if ($b.reset_in -eq "Now") { "Renews now" } elseif ($b.reset_in -eq "Active") { "Active" } elseif ($b.reset_in -eq "Outdated") { "Outdated - sign in again" } else { "Renews in $($b.reset_in)" }
                $tbReset.Foreground = if ($b.reset_in -eq "Outdated") { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xF5, 0xA6, 0x23)) } else { New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x8E, 0x8E, 0x9A)) }
                $tbReset.FontSize = 11
                $tbReset.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
                $tbReset.Margin = New-Object System.Windows.Thickness(10, 0, 12, 0)
                [System.Windows.Controls.Grid]::SetColumn($tbReset, 1)
                $row.Children.Add($tbReset) | Out-Null
            }
            
            $tbVal = New-Object System.Windows.Controls.TextBlock
            $tbVal.Text = "$pct%"
            $tbVal.Foreground = $statusBrush
            $tbVal.FontWeight = [System.Windows.FontWeights]::Bold
            $tbVal.FontSize = 18
            $tbVal.MinWidth = 56
            $tbVal.TextAlignment = [System.Windows.TextAlignment]::Right
            $tbVal.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            [System.Windows.Controls.Grid]::SetColumn($tbVal, 2)
            $row.Children.Add($tbVal) | Out-Null
            
            $cardStack.Children.Add($row) | Out-Null
            
            # Progress bar: two star columns, so it always fills the card width (flex)
            $pctClamped = [Math]::Min([Math]::Max($pct, 0), 100)
            $pbar = New-Object System.Windows.Controls.Grid
            $pbar.Height = 8
            $pbar.Margin = New-Object System.Windows.Thickness(0, 6, 0, 0)
            $pb1 = New-Object System.Windows.Controls.ColumnDefinition; $pb1.Width = New-Object System.Windows.GridLength($pctClamped, [System.Windows.GridUnitType]::Star)
            $pb2 = New-Object System.Windows.Controls.ColumnDefinition; $pb2.Width = New-Object System.Windows.GridLength((100 - $pctClamped), [System.Windows.GridUnitType]::Star)
            $pbar.ColumnDefinitions.Add($pb1)
            $pbar.ColumnDefinitions.Add($pb2)

            $pbarBg = New-Object System.Windows.Controls.Border
            $pbarBg.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2A, 0x2A, 0x30))
            $pbarBg.CornerRadius = New-Object System.Windows.CornerRadius(4)
            [System.Windows.Controls.Grid]::SetColumn($pbarBg, 0)
            [System.Windows.Controls.Grid]::SetColumnSpan($pbarBg, 2)
            $pbar.Children.Add($pbarBg) | Out-Null

            $pbarFill = New-Object System.Windows.Controls.Border
            $pbarFill.Background = $statusBrush
            $pbarFill.CornerRadius = New-Object System.Windows.CornerRadius(4)
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
    
    $hiddenKeys = Get-HiddenGauges
    foreach ($g in $data.groups) {
        $visibleBuckets = @(Get-VisibleBuckets $g $hiddenKeys)
        if ($visibleBuckets.Count -eq 0) { continue }
        
        $provKey = Get-ProviderKey $g.name $g.provider
        $accentHex = Get-GroupColorHex $g.name $g.provider
        $accentBrush = Convert-HexToBrush $accentHex
        
        $cleanTitle = $g.name
        if ($provKey -eq "claude_pro") { $cleanTitle = "Claude" }
        elseif ($provKey -eq "chatgpt_subscription") { $cleanTitle = "ChatGPT" }
        elseif ($provKey -eq "cursor") { $cleanTitle = "Cursor" }
        elseif ($provKey -eq "github_copilot") { $cleanTitle = "Copilot" }
        elseif ($provKey -eq "gemini") { $cleanTitle = "Gemini" }
        elseif ($provKey -eq "antigravity") { $cleanTitle = "Antigravity" }

        # Section Frame Container Grid
        $secGrid = New-Object System.Windows.Controls.Grid
        $secGrid.Width = 112
        $secGrid.Margin = New-Object System.Windows.Thickness(0, 0, 0, 10)
        $secGrid.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center

        # Outer Rounded Border (Emoldura toda a seção)
        $secBorder = New-Object System.Windows.Controls.Border
        $secBorder.BorderBrush = $accentBrush
        $secBorder.BorderThickness = New-Object System.Windows.Thickness(1.4)
        $secBorder.CornerRadius = New-Object System.Windows.CornerRadius(12)
        $secBorder.Margin = New-Object System.Windows.Thickness(0, 7, 0, 0)
        $secBorder.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(10, 255, 255, 255))

        # Stack inside the Section Frame
        $secStack = New-Object System.Windows.Controls.StackPanel
        $secStack.Margin = New-Object System.Windows.Thickness(0, 9, 0, 6)
        $secBorder.Child = $secStack
        $secGrid.Children.Add($secBorder) | Out-Null

        # Cut-out Title on Top Line (Design idêntico ao Mac)
        $titleBadge = New-Object System.Windows.Controls.Border
        $titleBadge.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x18, 0x18, 0x18))
        $titleBadge.Padding = New-Object System.Windows.Thickness(6, 0, 6, 0)
        $titleBadge.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $titleBadge.VerticalAlignment = [System.Windows.VerticalAlignment]::Top

        $titleTb = New-Object System.Windows.Controls.TextBlock
        $titleTb.Text = $cleanTitle
        $titleTb.Foreground = $accentBrush
        $titleTb.FontSize = 10.5
        $titleTb.FontWeight = [System.Windows.FontWeights]::SemiBold
        $titleBadge.Child = $titleTb
        $secGrid.Children.Add($titleBadge) | Out-Null

        foreach ($b in $visibleBuckets) {
            $pct = [int]$b.remaining_pct
            $statusBrush = Get-StatusBrush $pct $accentHex
            
            # Tachometer Gauge Item Container (fixed 100px tall, like the Mac 96pt item)
            $dialStack = New-Object System.Windows.Controls.StackPanel
            $dialStack.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $dialStack.Margin = New-Object System.Windows.Thickness(0)
            $dialStack.Width = 106
            $dialStack.Height = 122

            $cx = 48.0; $cy = 48.0; $ar = 33.0
            $dialGrid = New-Object System.Windows.Controls.Grid
            $dialGrid.Width = 96
            $dialGrid.Height = 96

            # Background circular tint
            $bgCircle = New-Object System.Windows.Shapes.Ellipse
            $bgCircle.Width = 66
            $bgCircle.Height = 66
            $bgCircle.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(180, 0x16, 0x16, 0x1A)))
            $bgCircle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $bgCircle.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $dialGrid.Children.Add($bgCircle) | Out-Null

            # Curved window label (e.g. WEEKLY / 5 HOURS) along the top of the dial
            $wLabel = (Get-BucketWindowLabel $b.name $b.id) -replace '\s+(LIMIT|CYCLE|REQUESTS)$', ''
            $labelR = 43.5
            $stepDeg = 6.9 / $labelR * 180.0 / [Math]::PI
            $startAng = -($wLabel.Length - 1) * $stepDeg / 2.0
            $labelBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xD0, 0xD0, 0xDA)))
            for ($ci = 0; $ci -lt $wLabel.Length; $ci++) {
                $ch = $wLabel.Substring($ci, 1)
                if ($ch -eq " ") { continue }
                $angDeg = $startAng + $ci * $stepDeg
                $angRad = $angDeg * [Math]::PI / 180.0
                $px = $cx + $labelR * [Math]::Sin($angRad)
                $py = $cy - $labelR * [Math]::Cos($angRad)
                $tbCh = New-Object System.Windows.Controls.TextBlock
                $tbCh.Text = $ch
                $tbCh.Width = 8
                $tbCh.Height = 10
                $tbCh.TextAlignment = [System.Windows.TextAlignment]::Center
                $tbCh.FontSize = 7.8
                $tbCh.FontWeight = [System.Windows.FontWeights]::Bold
                $tbCh.Foreground = $labelBrush
                $tbCh.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
                $tbCh.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
                $tbCh.Margin = New-Object System.Windows.Thickness(($px - 4), ($py - 5), 0, 0)
                $tbCh.RenderTransformOrigin = New-Object System.Windows.Point(0.5, 0.5)
                $tbCh.RenderTransform = New-Object System.Windows.Media.RotateTransform($angDeg)
                $dialGrid.Children.Add($tbCh) | Out-Null
            }

            # Track Arc (260° from 140° to 400°)
            $trackStr = Get-ArcGeometry $cx $cy $ar 140 260
            if ($trackStr) {
                $trackPath = New-Object System.Windows.Shapes.Path
                $trackPath.Data = [System.Windows.Media.Geometry]::Parse($trackStr)
                $trackPath.Stroke = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x27, 0x27, 0x30)))
                $trackPath.StrokeThickness = 5.5
                $trackPath.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
                $trackPath.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
                $dialGrid.Children.Add($trackPath) | Out-Null
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
                    $progPath.StrokeThickness = 5.5
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
                $needlePath.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(240, 245, 245, 250)))
                $dialGrid.Children.Add($needlePath) | Out-Null
            }

            # Center Hub Pin
            $hub = New-Object System.Windows.Shapes.Ellipse
            $hub.Width = 8
            $hub.Height = 8
            $hub.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x18, 0x18, 0x1C)))
            $hub.Stroke = $statusBrush
            $hub.StrokeThickness = 1.2
            $hub.Margin = New-Object System.Windows.Thickness(44, 44, 0, 0)
            $hub.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
            $hub.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
            $dialGrid.Children.Add($hub) | Out-Null

            # Center Percentage Text (sits in the gap at the bottom of the arc)
            $tbPct = New-Object System.Windows.Controls.TextBlock
            $tbPct.Text = "$pct%"
            $tbPct.Foreground = [System.Windows.Media.Brushes]::White
            $tbPct.FontSize = if ($pct -ge 100) { 11 } else { 12 }
            $tbPct.FontWeight = [System.Windows.FontWeights]::Bold
            $tbPct.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $tbPct.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
            $tbPct.Margin = New-Object System.Windows.Thickness(0, 62, 0, 0)
            $dialGrid.Children.Add($tbPct) | Out-Null

            $dialStack.Children.Add($dialGrid) | Out-Null
            
            # 3. Model Name Underneath (e.g. "Gemini", "Argon", "Claude")
            $mName = Get-BucketModelName $b.name $cleanTitle
            $tbMName = New-Object System.Windows.Controls.TextBlock
            $tbMName.Text = $mName
            $tbMName.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xE2, 0xE8, 0xF0)))
            $tbMName.FontSize = 10.5
            $tbMName.FontWeight = [System.Windows.FontWeights]::SemiBold
            $tbMName.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $tbMName.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $tbMName.MaxWidth = 102
            $tbMName.Margin = New-Object System.Windows.Thickness(0, -16, 0, 0)
            $dialStack.Children.Add($tbMName) | Out-Null
            
            # 4. Reset Countdown Underneath (e.g. "4d 1h", "4h 51m")
            $tbReset = New-Object System.Windows.Controls.TextBlock
            $tbReset.Text = if ($b.reset_in) { $b.reset_in } else { "Active" }
            $tbReset.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xA8, 0xA8, 0xB4)))
            $tbReset.FontSize = 9.5
            $tbReset.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $tbReset.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $tbReset.MaxWidth = 102
            $dialStack.Children.Add($tbReset) | Out-Null
            
            $secStack.Children.Add($dialStack) | Out-Null
        }
        
        $hudCardsPanel.Children.Add($secGrid) | Out-Null
    }
}

# 7. Settings Dialog with 6 Pastel Palette Swatches
function Show-SettingsDialog {
    [xml]$cfgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Settings - AI Gauge" Height="620" Width="460"
        WindowStartupLocation="CenterOwner" Background="#18181A" ResizeMode="NoResize">
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
            <TextBlock Text="Settings - AI Providers &amp; Pastel Colors" Foreground="#FFFFFF" FontSize="14" FontWeight="Bold"/>
            <TextBlock Text="Enable providers, credentials and customize section colors:" Foreground="#888888" FontSize="10.5" Margin="0,3,0,0"/>
        </StackPanel>
        
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel Name="SettingsStack" Margin="0,0,6,0">
                <!-- Antigravity -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkAnti" Content="Antigravity" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelAnti" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <TextBlock Text="Detects IDE quotas while running or via headless probe." Foreground="#777777" FontSize="9.5" Margin="20,4,0,0"/>
                    </StackPanel>
                </Border>
                
                <!-- Claude -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkClaudePro" Content="Claude" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelClaude" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtClaudeProToken" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="OAuth Session Token (auto-detected if logged in)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- ChatGPT -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkChatGPT" Content="ChatGPT" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelChatGPT" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtChatGPTToken" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="Session / Access Token (3h window &amp; weekly o1 quota)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- Cursor -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkCursor" Content="Cursor" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelCursor" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtCursorToken" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="Cursor Session Token (optional if logged in Cursor)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- Copilot -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkCopilot" Content="Copilot" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelCopilot" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtCopilotToken" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="GitHub Personal Access Token (optional)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- Google Gemini -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkGemini" Content="Google Gemini" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelGemini" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtGeminiKey" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Name="LinkAiStudio" Text="Get free API key at Google AI Studio (aistudio.google.com) ->" Foreground="#38BDF8" FontSize="9.5" Cursor="Hand"/>
                    </StackPanel>
                </Border>
                
                <!-- OpenAI -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkOpenAI" Content="OpenAI" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelOpenAI" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtOpenAIKey" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="OpenAI API Key (sk-...)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- Anthropic -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkClaude" Content="Anthropic" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelAnthropic" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <PasswordBox Name="TxtClaudeKey" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="Anthropic API Key (sk-ant-...)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </ScrollViewer>
        
        <Grid Grid.Row="2" Margin="0,12,0,0">
            <Button Name="BtnSave" Content="Save &amp; Refresh" Width="130" Height="28" HorizontalAlignment="Left" Background="#00E699" Foreground="#121214" FontWeight="Bold" Cursor="Hand"/>
            <Button Name="BtnCancel" Content="Cancel" Width="80" Height="28" HorizontalAlignment="Right" Background="#282830" Foreground="#E5E7EB" BorderBrush="#3A3A46" BorderThickness="1" Cursor="Hand"/>
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
    $chkChatGPT = $cfgWin.FindName("ChkChatGPT")
    $txtChatGPTToken = $cfgWin.FindName("TxtChatGPTToken")
    $chkCursor = $cfgWin.FindName("ChkCursor")
    $txtCursorToken = $cfgWin.FindName("TxtCursorToken")
    $chkCopilot = $cfgWin.FindName("ChkCopilot")
    $txtCopilotToken = $cfgWin.FindName("TxtCopilotToken")
    $chkGemini = $cfgWin.FindName("ChkGemini")
    $txtGeminiKey = $cfgWin.FindName("TxtGeminiKey")
    $linkAiStudio = $cfgWin.FindName("LinkAiStudio")
    $chkOpenAI = $cfgWin.FindName("ChkOpenAI")
    $txtOpenAIKey = $cfgWin.FindName("TxtOpenAIKey")
    $chkClaude = $cfgWin.FindName("ChkClaude")
    $txtClaudeKey = $cfgWin.FindName("TxtClaudeKey")
    
    $pAnti = $cfgWin.FindName("ColorPanelAnti")
    $pClaude = $cfgWin.FindName("ColorPanelClaude")
    $pChatGPT = $cfgWin.FindName("ColorPanelChatGPT")
    $pCursor = $cfgWin.FindName("ColorPanelCursor")
    $pCopilot = $cfgWin.FindName("ColorPanelCopilot")
    $pGemini = $cfgWin.FindName("ColorPanelGemini")
    $pOpenAI = $cfgWin.FindName("ColorPanelOpenAI")
    $pAnthropic = $cfgWin.FindName("ColorPanelAnthropic")
    
    $btnSave = $cfgWin.FindName("BtnSave")
    $btnCancel = $cfgWin.FindName("BtnCancel")

    $currentCfg = Load-CurrentConfig
    $pData = if ($currentCfg -and $currentCfg.providers) { $currentCfg.providers } else { @{} }
    $sColors = if ($currentCfg -and $currentCfg.section_colors) { $currentCfg.section_colors } else { @{} }

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

    $linkAiStudio.Add_MouseDown({
        [System.Diagnostics.Process]::Start("https://aistudio.google.com/app/apikey")
    })

    $btnSave.Add_Click({
        $colorsOut = @{}
        foreach ($k in $swatchPanels.Keys) {
            $v = "$($swatchPanels[$k].Tag)"
            if ($v) { $colorsOut[$k] = $v }
        }
        $newCfg = @{
            providers = @{
                antigravity          = @{ enabled = [bool]$chkAnti.IsChecked }
                claude_pro           = @{ enabled = [bool]$chkClaudePro.IsChecked; token = $txtClaudeProToken.Password.Trim() }
                chatgpt_subscription = @{ enabled = [bool]$chkChatGPT.IsChecked; token = $txtChatGPTToken.Password.Trim() }
                cursor               = @{ enabled = [bool]$chkCursor.IsChecked; token = $txtCursorToken.Password.Trim() }
                github_copilot       = @{ enabled = [bool]$chkCopilot.IsChecked; token = $txtCopilotToken.Password.Trim() }
                gemini               = @{ enabled = [bool]$chkGemini.IsChecked; api_key = $txtGeminiKey.Password.Trim() }
                openai               = @{ enabled = [bool]$chkOpenAI.IsChecked; api_key = $txtOpenAIKey.Password.Trim() }
                anthropic            = @{ enabled = [bool]$chkClaude.IsChecked; api_key = $txtClaudeKey.Password.Trim() }
            }
            section_colors = $colorsOut
            refresh_interval_seconds = 30
            hidden_hud_gauges = @(Get-HiddenGauges)
            onboarding_completed = $true
        }
        
        $jsonStr = $newCfg | ConvertTo-Json -Depth 5
        Set-Content -Path $ConfigFile -Value $jsonStr -Encoding UTF8
        try {
            $acl = Get-Acl -Path $ConfigFile
            $acl.SetAccessRuleProtection($true, $false)
            $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($user, "FullControl", "Allow")
            $acl.AddAccessRule($rule)
            Set-Acl -Path $ConfigFile -AclObject $acl
        } catch {}
        $cfgWin.Close()
        # Repaint immediately with the new colors (cockpit + HUD), then fetch fresh data
        try { Redraw-All } catch { Write-AppError $_.Exception }
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
    }
}

function Complete-QuotaFetch ($newData) {
    Render-UI $newData
    if ($global:isHudMode) {
        $window.Width = $global:HudWidth
        $window.Height = Get-HudHeight $newData
        Render-HUD $newData
    }
    $btnRefresh.Content = "↻ Refresh"
    $btnRefresh.IsEnabled = $true

    # First run: open the settings dialog only after the main window is on screen.
    if ($global:initialLoad) {
        $global:initialLoad = $false
        $nodeMissing = ($newData -and $newData.node_missing)
        if (-not $nodeMissing) {
            if ((-not $newData) -or $newData.needs_setup -or (-not $newData.groups) -or $newData.groups.Count -eq 0) {
                Show-SettingsDialog
            }
        }
    }
}

# Event Listeners
$btnRefresh.Add_Click({ Refresh-Data })
$btnSettings.Add_Click({ Show-SettingsDialog })

$txtHudBrand = $window.FindName("TxtHudBrand")
if ($txtHudBrand) {
    $txtHudBrand.Add_MouseDown({
        $mid = ""
        if (Test-Path $DeviceIdFile) {
            $mid = (Get-Content $DeviceIdFile -Raw).Trim()
        }
        $dUrl = if ($mid) { "https://ai-gauge.vh2c.com.br/donate?mid=$mid" } else { "https://ai-gauge.vh2c.com.br/donate" }
        [System.Diagnostics.Process]::Start($dUrl)
    })
    $txtHudBrand.Add_MouseEnter({ $txtHudBrand.Foreground = [System.Windows.Media.Brushes]::White })
    $txtHudBrand.Add_MouseLeave({ $txtHudBrand.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x88, 0x88, 0x94))) })
}

$txtBrand.Add_MouseDown({
    $mid = ""
    if (Test-Path $DeviceIdFile) {
        $mid = (Get-Content $DeviceIdFile -Raw).Trim()
    }
    $dUrl = if ($mid) { "https://ai-gauge.vh2c.com.br/donate?mid=$mid" } else { "https://ai-gauge.vh2c.com.br/donate" }
    [System.Diagnostics.Process]::Start($dUrl)
})

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

# Auto-refresh Timer (30s)
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
$timer.Add_Tick({ Refresh-Data })
$timer.Start()

$window.ShowDialog() | Out-Null
