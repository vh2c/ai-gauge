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
        [System.Windows.MessageBox]::Show("Ocorreu um erro ao executar o AI Gauge:`n`n$($_.Exception.Message)`n`nArquivo de log salvo em:`n$logPath", "AI Gauge - Erro", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    } catch {}
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir
$EngineScript = Join-Path $ScriptDir "core\engine.js"
if (-not (Test-Path $EngineScript)) {
    $EngineScript = Join-Path $RepoDir "core\engine.js"
}

$ConfigDir = Join-Path $env:USERPROFILE ".config\UniversalAIQuota"
if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}
$ConfigFile = Join-Path $ConfigDir "config.json"
$DeviceIdFile = Join-Path $ConfigDir "device_id"

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

# 2. Telemetry Heartbeat (Anonymous, Throttled, Opt-out supported)
function Send-TelemetryHeartbeat {
    try {
        if (Test-Path $ConfigFile) {
            try {
                $rawCfg = Get-Content $ConfigFile -Raw | ConvertFrom-Json
                if ($rawCfg.telemetry -eq $false -or $rawCfg.telemetry_enabled -eq $false) {
                    return
                }
            } catch {}
        }

        $stampFile = Join-Path $ConfigDir ".last_ping"
        $now = [int][double]::Parse((Get-Date -UFormat %s))
        if (Test-Path $stampFile) {
            try {
                $last = [int](Get-Content $stampFile -Raw).Trim()
                if ($now - $last -lt 21600) {
                    return
                }
            } catch {}
        }

        $machineId = ""
        if (Test-Path $DeviceIdFile) {
            $machineId = (Get-Content $DeviceIdFile -Raw).Trim()
        }
        if (-not $machineId) {
            $machineId = [guid]::NewGuid().ToString("N")
            Set-Content -Path $DeviceIdFile -Value $machineId -Encoding UTF8
        }

        $payload = @{
            app = "ai-gauge"
            version = "1.1.0"
            os = "Windows"
            arch = $env:PROCESSOR_ARCHITECTURE
            machine_id = $machineId
            timestamp = $now
        } | ConvertTo-Json

        Start-Job -ScriptBlock {
            param($body, $sFile, $tNow)
            try {
                $endpoint = "https://ai-gauge.vh2c.com.br/api/telemetry"
                $res = Invoke-RestMethod -Uri $endpoint -Method Post -Body $body -ContentType "application/json" -TimeoutSec 3 -ErrorAction SilentlyContinue
                if ($res) {
                    Set-Content -Path $sFile -Value $tNow -Encoding UTF8 -Force
                }
            } catch {}
        } -ArgumentList $payload, $stampFile, $now | Out-Null
    } catch {}
}

Send-TelemetryHeartbeat

# 3. Find Node binary
function Find-NodeBinary {
    $cmd = Get-Command "node.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $localNode = Join-Path $ScriptDir "bin\node.exe"
    if (Test-Path $localNode) { return $localNode }
    return $null
}

$NodeExe = Find-NodeBinary

function Get-QuotaData ($force = $false) {
    if (-not $NodeExe) {
        return @{
            account = "Node.js não detectado"
            plan = "Requer Instalação"
            updated_at = (Get-Date -Format "HH:mm:ss")
            groups = @()
            node_missing = $true
        }
    }
    try {
        $argsList = @($EngineScript)
        if ($force) { $argsList += "--force" }
        $json = & $NodeExe $argsList 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) {
            return ($json | ConvertFrom-Json)
        }
    } catch {}
    return $null
}

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
                        <TextBlock Text="AI Gauge" Foreground="#00E699" FontSize="13.5" FontWeight="Bold"/>
                        <TextBlock Text=" • Universal AI Quota Cockpit" Foreground="#9CA3AF" FontSize="12.5" FontWeight="SemiBold"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                        <Button Name="BtnMin" Content="—" Width="28" Height="24" Background="#24242C" Foreground="#9CA3AF" BorderBrush="#353542" BorderThickness="1" FontSize="11" FontWeight="Bold" Cursor="Hand" Margin="0,0,4,0"/>
                        <Button Name="BtnTopClose" Content="✕" Width="28" Height="24" Background="#24242C" Foreground="#9CA3AF" BorderBrush="#353542" BorderThickness="1" FontSize="11" FontWeight="Bold" Cursor="Hand"/>
                    </StackPanel>
                </Grid>
                
                <!-- Subtitle / Account Info -->
                <TextBlock Name="TxtAccount" Grid.Row="1" Text="Loading quotas..." Foreground="#888894" FontSize="11" Margin="2,0,0,10"/>
                
                <!-- Cards List -->
                <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto">
                    <StackPanel Name="CardsPanel" Margin="0,0,4,0"/>
                </ScrollViewer>
                
                <!-- Cockpit Footer -->
                <StackPanel Grid.Row="3" Margin="0,12,0,0">
                    <Grid>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                            <Button Name="BtnRefresh" Content="↻ Refresh" Height="28" Padding="12,0,12,0" Background="#25252D" Foreground="#E5E7EB" BorderBrush="#3B3B48" BorderThickness="1" FontWeight="SemiBold" FontSize="11" Cursor="Hand" Margin="0,0,6,0"/>
                            <Button Name="BtnHud" Content="⤢ HUD Bar" Height="28" Padding="12,0,12,0" Background="#25252D" Foreground="#E5E7EB" BorderBrush="#3B3B48" BorderThickness="1" FontWeight="SemiBold" FontSize="11" Cursor="Hand" Margin="0,0,6,0"/>
                            <Button Name="BtnSettings" Content="⚙ Settings" Height="28" Padding="12,0,12,0" Background="#25252D" Foreground="#E5E7EB" BorderBrush="#3B3B48" BorderThickness="1" FontWeight="SemiBold" FontSize="11" Cursor="Hand"/>
                        </StackPanel>
                        
                        <Button Name="BtnClose" Content="✕ Close" Height="28" Padding="14,0,14,0" HorizontalAlignment="Right" Background="#25252D" Foreground="#E5E7EB" BorderBrush="#3B3B48" BorderThickness="1" FontWeight="SemiBold" FontSize="11" Cursor="Hand"/>
                    </Grid>
                    
                    <!-- Brand Link -->
                    <TextBlock Name="TxtBrand" Text="⚡ AI Gauge • Developed by vh2c.com.br"
                               ToolTip="Support AI Gauge via Stripe Donation"
                               Foreground="#38BDF8" FontSize="10.5" FontWeight="SemiBold"
                               HorizontalAlignment="Center" Margin="0,10,0,0" Cursor="Hand"/>
                </StackPanel>
            </Grid>
            
            <!-- 2. COMPACT HUD BAR VIEW (Mac-identical aesthetic) -->
            <Border Name="HudView" Background="#141417" Padding="6,8,6,6" Visibility="Collapsed" CornerRadius="12">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- HUD Top Controls -->
                    <Grid Grid.Row="0" Margin="0,0,0,6">
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                            <Button Name="BtnHudCockpit" Content="⤢" Width="24" Height="22" ToolTip="Cockpit Mode" Background="#202026" Foreground="#9CA3AF" BorderBrush="#2D2D38" BorderThickness="1" FontSize="11" FontWeight="Bold" Cursor="Hand" Margin="0,0,3,0"/>
                            <Button Name="BtnHudSettings" Content="⚙" Width="24" Height="22" ToolTip="Settings" Background="#202026" Foreground="#9CA3AF" BorderBrush="#2D2D38" BorderThickness="1" FontSize="10" FontWeight="Bold" Cursor="Hand" Margin="0,0,3,0"/>
                            <Button Name="BtnHudRefresh" Content="↻" Width="24" Height="22" ToolTip="Refresh" Background="#202026" Foreground="#9CA3AF" BorderBrush="#2D2D38" BorderThickness="1" FontSize="11" FontWeight="Bold" Cursor="Hand" Margin="0,0,3,0"/>
                            <Button Name="BtnHudClose" Content="✕" Width="24" Height="22" ToolTip="Close AI Gauge" Background="#202026" Foreground="#9CA3AF" BorderBrush="#2D2D38" BorderThickness="1" FontSize="9.5" FontWeight="Bold" Cursor="Hand"/>
                        </StackPanel>
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
$btnHudSettings = $window.FindName("BtnHudSettings")
$btnHudRefresh = $window.FindName("BtnHudRefresh")

$global:isHudMode = $false
$global:currentData = $null
$global:prevLeft = $null
$global:prevTop = $null

function Toggle-HudMode {
    $workArea = [System.Windows.SystemParameters]::WorkArea
    if ($global:isHudMode) {
        # Switch back to Cockpit Mode
        $global:isHudMode = $false
        $hudView.Visibility = [System.Windows.Visibility]::Collapsed
        $cockpitView.Visibility = [System.Windows.Visibility]::Visible
        
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
        
        $totalBuckets = 0
        $sectionCount = 0
        if ($global:currentData -and $global:currentData.groups) {
            foreach ($g in $global:currentData.groups) {
                if ($g.buckets -and $g.buckets.Count -gt 0) {
                    $sectionCount++
                    $totalBuckets += $g.buckets.Count
                }
            }
        }
        
        if ($totalBuckets -eq 0) {
            $hudH = 175
        } else {
            $calcH = 34 + ($sectionCount * 22) + ($totalBuckets * 86) + (($sectionCount - 1) * 10) + 26
            $maxH = [Math]::Min(780, $workArea.Height - 60)
            $hudH = [Math]::Min($maxH, [Math]::Max(160, $calcH))
        }
        
        $window.Title = "AI Gauge HUD"
        $window.Topmost = $true
        $window.Width = 118
        $window.Height = $hudH
        $window.Left = $workArea.Right - 134
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
$btnHudSettings.Add_Click({ Show-SettingsDialog })
$btnHudRefresh.Add_Click({ Refresh-Data })

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

# 5. Render Full Cockpit UI
function Render-UI ($data) {
    $global:currentData = $data
    $cardsPanel.Children.Clear()
    
    $hasGroups = ($data -and $data.groups -and $data.groups.Count -gt 0)
    
    # ----------------- EMPTY STATE (ONBOARDING) -----------------
    if (-not $hasGroups) {
        $txtAcc.Text = "Nenhuma conta ou quota de IA detectada localmente"
        
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
            $txtAcc.Text = "Node.js não foi encontrado no sistema"
            $tIconNode = New-Object System.Windows.Controls.TextBlock
            $tIconNode.Text = "⚠️"
            $tIconNode.FontSize = 18
            $tIconNode.Margin = (New-Object System.Windows.Thickness(0, 0, 8, 0))
            
            $tTitleNode = New-Object System.Windows.Controls.TextBlock
            $tTitleNode.Text = "Node.js Necessário"
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
            $tDescNode.Text = "O AI Gauge precisa do Node.js (v18+) para agregar as cotas em segundo plano. Clique no botão abaixo para baixar gratuitamente:"
            $tDescNode.TextWrapping = [System.Windows.TextWrapping]::Wrap
            $tDescNode.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xBB, 0xBB, 0xC4)))
            $tDescNode.FontSize = 11
            $tDescNode.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 14))
            $emptyStack.Children.Add($tDescNode) | Out-Null
            
            $btnNode = New-Object System.Windows.Controls.Button
            $btnNode.Content = "⬇ Baixar Node.js Oficial (nodejs.org)"
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
        $tTitle.Text = "Nenhum Registro de IA Encontrado"
        $tTitle.FontSize = 14
        $tTitle.FontWeight = [System.Windows.FontWeights]::Bold
        $tTitle.Foreground = [System.Windows.Media.Brushes]::White
        $tTitle.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $tRow.Children.Add($tTitle) | Out-Null
        $emptyStack.Children.Add($tRow) | Out-Null
        
        # 2. Explanation
        $tDesc = New-Object System.Windows.Controls.TextBlock
        $tDesc.Text = "Não encontramos contas ou sessões ativas locais (Antigravity, Claude, ChatGPT, Cursor ou Copilot) nesta máquina."
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
        $gHead.Text = "Como direcionar e monitorar suas cotas:"
        $gHead.FontWeight = [System.Windows.FontWeights]::Bold
        $gHead.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x8F, 0xBC, 0xFF)))
        $gHead.FontSize = 10.5
        $gHead.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 6))
        $guideStack.Children.Add($gHead) | Out-Null
        
        $item1 = New-Object System.Windows.Controls.TextBlock
        $item1.Text = "• Google Gemini (Recomendado): Crie uma chave gratuita no Google AI Studio (leva 30 segundos e não exige IDE instalada)."
        $item1.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $item1.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xCC, 0xCC, 0xD4)))
        $item1.FontSize = 10
        $item1.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 4))
        $guideStack.Children.Add($item1) | Out-Null
        
        $item2 = New-Object System.Windows.Controls.TextBlock
        $item2.Text = "• OpenAI & Anthropic: Adicione suas chaves de API sk-... para monitorar cotas e limites de requisição."
        $item2.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $item2.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xCC, 0xCC, 0xD4)))
        $item2.FontSize = 10
        $item2.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 4))
        $guideStack.Children.Add($item2) | Out-Null
        
        $item3 = New-Object System.Windows.Controls.TextBlock
        $item3.Text = "• Tokens de Sessão: Insira seu token de assinatura do Claude Pro, ChatGPT ou Cursor se assinar tais serviços."
        $item3.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $item3.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xCC, 0xCC, 0xD4)))
        $item3.FontSize = 10
        $guideStack.Children.Add($item3) | Out-Null
        
        $guideBox.Child = $guideStack
        $emptyStack.Children.Add($guideBox) | Out-Null
        
        # 4. Action Buttons
        $btnStack = New-Object System.Windows.Controls.StackPanel
        
        $btnConfig = New-Object System.Windows.Controls.Button
        $btnConfig.Content = "⚙ Configurar Provedores e Chaves de API"
        $btnConfig.Height = 32
        $btnConfig.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xE6, 0x99)))
        $btnConfig.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x12, 0x12, 0x14)))
        $btnConfig.FontWeight = [System.Windows.FontWeights]::Bold
        $btnConfig.FontSize = 11.5
        $btnConfig.Cursor = [System.Windows.Input.Cursors]::Hand
        $btnConfig.Add_Click({ Show-SettingsDialog })
        $btnStack.Children.Add($btnConfig) | Out-Null
        
        $btnStudio = New-Object System.Windows.Controls.Button
        $btnStudio.Content = "🔗 Obter Chave Gratuita no Google AI Studio (aistudio.google.com) ->"
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
    
    $cacheInfo = if ($data.from_cache) { " (Cache)" } else { " (Live)" }
    $txtAcc.Text = "$($data.account) | Plan $($data.plan) | Updated at $($data.updated_at)$cacheInfo"
    
    # ----------------- UPDATE BANNER -----------------
    if ($data.update -and $data.update.update_available) {
        $upBorder = New-Object System.Windows.Controls.Border
        $upBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(40, 0, 0xE6, 0x99)))
        $upBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0, 0xE6, 0x99)))
        $upBorder.BorderThickness = (New-Object System.Windows.Thickness(1))
        $upBorder.CornerRadius = (New-Object System.Windows.CornerRadius(6))
        $upBorder.Padding = (New-Object System.Windows.Thickness(10, 8, 10, 8))
        $upBorder.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 10))
        
        $upDock = New-Object System.Windows.Controls.DockPanel
        
        $btnDl = New-Object System.Windows.Controls.Button
        $btnDl.Content = "Download"
        $btnDl.Padding = (New-Object System.Windows.Thickness(12, 3, 12, 3))
        $btnDl.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0, 0xE6, 0x99)))
        $btnDl.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x12, 0x12, 0x12)))
        $btnDl.FontWeight = [System.Windows.FontWeights]::Bold
        [System.Windows.Controls.DockPanel]::SetDock($btnDl, [System.Windows.Controls.Dock]::Right)
        $dlUrl = if ($data.update.download_url) { $data.update.download_url } else { "https://github.com/vh2c/gemini-gauge/releases/latest" }
        $btnDl.Add_Click({ [System.Diagnostics.Process]::Start($dlUrl) })
        $upDock.Children.Add($btnDl) | Out-Null
        
        $upTxt = New-Object System.Windows.Controls.TextBlock
        $upTxt.Text = "New release v$($data.update.latest_version) available"
        $upTxt.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0, 0xE6, 0x99)))
        $upTxt.FontWeight = [System.Windows.FontWeights]::Bold
        $upTxt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $upDock.Children.Add($upTxt) | Out-Null
        
        $upBorder.Child = $upDock
        $cardsPanel.Children.Add($upBorder) | Out-Null
    }

    # ----------------- ANNOUNCEMENT / DONATION -----------------
    if ($data.announcement -and $data.announcement.message) {
        $annBorder = New-Object System.Windows.Controls.Border
        $annBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(40, 0x38, 0xBD, 0xF8)))
        $annBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x38, 0xBD, 0xF8)))
        $annBorder.BorderThickness = (New-Object System.Windows.Thickness(1))
        $annBorder.CornerRadius = (New-Object System.Windows.CornerRadius(6))
        $annBorder.Padding = (New-Object System.Windows.Thickness(12, 8, 12, 8))
        $annBorder.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 10))
        
        $annStack = New-Object System.Windows.Controls.StackPanel
        
        $badgeText = if ($data.announcement.badge) { "$($data.announcement.badge)" -replace '[^\x20-\x7E]', '' } else { "PRO" }
        if (-not $badgeText.Trim()) { $badgeText = "PRO" }
        
        $annHead = New-Object System.Windows.Controls.TextBlock
        $annHead.Text = "[$badgeText] $($data.announcement.title)"
        $annHead.FontWeight = [System.Windows.FontWeights]::Bold
        $annHead.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x38, 0xBD, 0xF8)))
        $annStack.Children.Add($annHead) | Out-Null
        
        $annMsg = New-Object System.Windows.Controls.TextBlock
        $annMsg.Text = "$($data.announcement.message)"
        $annMsg.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $annMsg.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xCC, 0xCC, 0xCC)))
        $annMsg.Margin = (New-Object System.Windows.Thickness(0, 2, 0, 4))
        $annStack.Children.Add($annMsg) | Out-Null
        
        if ($data.announcement.action_label -and $data.announcement.action_url) {
            $actLabel = "$($data.announcement.action_label)" -replace '→', '->'
            if (-not ($actLabel.Contains("->") -or $actLabel.Contains(">"))) {
                $actLabel = "$actLabel ->"
            }
            $btnAct = New-Object System.Windows.Controls.Button
            $btnAct.Content = $actLabel
            $btnAct.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
            $btnAct.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x00, 0xC9, 0xFF)))
            $btnAct.Background = [System.Windows.Media.Brushes]::Transparent
            $btnAct.BorderThickness = (New-Object System.Windows.Thickness(0))
            $btnAct.Cursor = [System.Windows.Input.Cursors]::Hand
            $actUrl = $data.announcement.action_url
            $btnAct.Add_Click({ [System.Diagnostics.Process]::Start($actUrl) })
            $annStack.Children.Add($btnAct) | Out-Null
        }
        
        $annBorder.Child = $annStack
        $cardsPanel.Children.Add($annBorder) | Out-Null
    }

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
        
        # Header Row
        $headerGrid = New-Object System.Windows.Controls.Grid
        $headerGrid.Margin = New-Object System.Windows.Thickness(0, 8, 0, 4)
        $hCol1 = New-Object System.Windows.Controls.ColumnDefinition; $hCol1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $hCol2 = New-Object System.Windows.Controls.ColumnDefinition; $hCol2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
        $headerGrid.ColumnDefinitions.Add($hCol1)
        $headerGrid.ColumnDefinitions.Add($hCol2)
        
        $gbTitle = New-Object System.Windows.Controls.TextBlock
        $gbTitle.Text = ($cleanTitle).ToUpper()
        $gbTitle.Foreground = [System.Windows.Media.Brushes]::White
        $gbTitle.FontSize = 11
        $gbTitle.FontWeight = [System.Windows.FontWeights]::Bold
        [System.Windows.Controls.Grid]::SetColumn($gbTitle, 0)
        $headerGrid.Children.Add($gbTitle) | Out-Null
        
        $tagBadge = New-Object System.Windows.Controls.TextBlock
        $tagBadge.Text = ($provKey).ToUpper()
        $tagBadge.Foreground = $accentBrush
        $tagBadge.FontSize = 9.5
        $tagBadge.FontWeight = [System.Windows.FontWeights]::Bold
        [System.Windows.Controls.Grid]::SetColumn($tagBadge, 1)
        $headerGrid.Children.Add($tagBadge) | Out-Null
        
        $cardsPanel.Children.Add($headerGrid) | Out-Null
        
        $card = New-Object System.Windows.Controls.Border
        $card.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1F, 0x1F, 0x22))
        $card.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x2C, 0x2C, 0x33))
        $card.BorderThickness = New-Object System.Windows.Thickness(1)
        $card.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $card.Padding = New-Object System.Windows.Thickness(14, 10, 14, 10)
        $card.Margin = New-Object System.Windows.Thickness(0, 0, 0, 8)
        
        $cardStack = New-Object System.Windows.Controls.StackPanel
        
        $idx = 0
        foreach ($b in $g.buckets) {
            if ($idx -gt 0) {
                $sep = New-Object System.Windows.Controls.Separator
                $sep.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x2E))
                $sep.Margin = New-Object System.Windows.Thickness(0, 6, 0, 6)
                $cardStack.Children.Add($sep) | Out-Null
            }
            
            $row = New-Object System.Windows.Controls.Grid
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
            $row.ColumnDefinitions.Add($c1)
            $row.ColumnDefinitions.Add($c2)
            
            $tbName = New-Object System.Windows.Controls.TextBlock
            $tbName.Text = $b.name
            $tbName.Foreground = [System.Windows.Media.Brushes]::White
            $tbName.FontSize = 11.5
            [System.Windows.Controls.Grid]::SetColumn($tbName, 0)
            $row.Children.Add($tbName) | Out-Null
            
            $pct = [int]$b.remaining_pct
            $resetStr = if ($b.reset_in) { " | $($b.reset_in)" } else { "" }
            $tbVal = New-Object System.Windows.Controls.TextBlock
            $tbVal.Text = "$pct%$resetStr"
            $tbVal.Foreground = Get-StatusBrush $pct $accentHex
            $tbVal.FontWeight = [System.Windows.FontWeights]::Bold
            $tbVal.FontSize = 11.5
            [System.Windows.Controls.Grid]::SetColumn($tbVal, 1)
            $row.Children.Add($tbVal) | Out-Null
            
            $cardStack.Children.Add($row) | Out-Null
            
            # Progress Bar
            $pbarBg = New-Object System.Windows.Controls.Border
            $pbarBg.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x2E))
            $pbarBg.Height = 6
            $pbarBg.CornerRadius = New-Object System.Windows.CornerRadius(3)
            $pbarBg.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
            
            $pbarFill = New-Object System.Windows.Controls.Border
            $pbarFill.Background = Get-StatusBrush $pct $accentHex
            $pbarFill.Height = 6
            $pbarFill.CornerRadius = New-Object System.Windows.CornerRadius(3)
            $pbarFill.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
            $pbarFill.Width = [Math]::Max(6, (380 * ($pct / 100.0)))
            
            $pbarBg.Child = $pbarFill
            $cardStack.Children.Add($pbarBg) | Out-Null
            
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
        $card.Width = 104
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
        $t1.Text = "SEM COTAS"
        $t1.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x8F, 0xBC, 0xFF)))
        $t1.FontSize = 8.5
        $t1.FontWeight = [System.Windows.FontWeights]::Bold
        $t1.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $t1.Margin = (New-Object System.Windows.Thickness(0, 4, 0, 2))
        $cardStack.Children.Add($t1) | Out-Null
        
        $t2 = New-Object System.Windows.Controls.TextBlock
        $t2.Text = "Clique para configurar contas ou tokens."
        $t2.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $t2.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x94, 0xA3, 0xB8)))
        $t2.FontSize = 8
        $t2.TextAlignment = [System.Windows.TextAlignment]::Center
        $cardStack.Children.Add($t2) | Out-Null
        
        $card.Child = $cardStack
        $hudCardsPanel.Children.Add($card) | Out-Null
        return
    }
    
    foreach ($g in $data.groups) {
        if (-not $g.buckets -or $g.buckets.Count -eq 0) { continue }
        
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
        $secGrid.Width = 104
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
        $titleBadge.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x14, 0x14, 0x17))
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

        foreach ($b in $g.buckets) {
            $pct = [int]$b.remaining_pct
            $statusBrush = Get-StatusBrush $pct $accentHex
            
            # Tachometer Gauge Item Container (Floating, no individual box)
            $dialStack = New-Object System.Windows.Controls.StackPanel
            $dialStack.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $dialStack.Margin = New-Object System.Windows.Thickness(0, 4, 0, 6)
            $dialStack.Width = 92
            
            # 1. Top Window Label (e.g. "WEEKLY LIMIT", "5 HOURS LIMIT")
            $wLabel = Get-BucketWindowLabel $b.name $b.id
            $tbWLabel = New-Object System.Windows.Controls.TextBlock
            $tbWLabel.Text = $wLabel
            $tbWLabel.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x76, 0x76, 0x82)))
            $tbWLabel.FontSize = 7.2
            $tbWLabel.FontWeight = [System.Windows.FontWeights]::SemiBold
            $tbWLabel.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $dialStack.Children.Add($tbWLabel) | Out-Null
            
            # 2. Tachometer Circular Dial Grid (64x52)
            $dialGrid = New-Object System.Windows.Controls.Grid
            $dialGrid.Width = 64
            $dialGrid.Height = 52
            $dialGrid.Margin = New-Object System.Windows.Thickness(0, 1, 0, 1)
            
            # Background circular shadow / tint
            $bgCircle = New-Object System.Windows.Shapes.Ellipse
            $bgCircle.Width = 44
            $bgCircle.Height = 44
            $bgCircle.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(180, 0x16, 0x16, 0x1A)))
            $bgCircle.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $bgCircle.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $dialGrid.Children.Add($bgCircle) | Out-Null
            
            # Track Arc (260° from 140° to 400°)
            $trackStr = Get-ArcGeometry 32 26 20 140 260
            if ($trackStr) {
                $trackPath = New-Object System.Windows.Shapes.Path
                $trackPath.Data = [System.Windows.Media.Geometry]::Parse($trackStr)
                $trackPath.Stroke = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x27, 0x27, 0x30)))
                $trackPath.StrokeThickness = 4.2
                $trackPath.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
                $trackPath.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
                $dialGrid.Children.Add($trackPath) | Out-Null
            }
            
            # Active Progress Arc
            $sweep = ($pct / 100.0) * 260.0
            if ($sweep -gt 260.0) { $sweep = 260.0 }
            if ($sweep -ge 1.0) {
                $progStr = Get-ArcGeometry 32 26 20 140 $sweep
                if ($progStr) {
                    $progPath = New-Object System.Windows.Shapes.Path
                    $progPath.Data = [System.Windows.Media.Geometry]::Parse($progStr)
                    $progPath.Stroke = $statusBrush
                    $progPath.StrokeThickness = 4.2
                    $progPath.StrokeStartLineCap = [System.Windows.Media.PenLineCap]::Round
                    $progPath.StrokeEndLineCap = [System.Windows.Media.PenLineCap]::Round
                    $dialGrid.Children.Add($progPath) | Out-Null
                }
            }
            
            # Needle Pointer (Apontador idêntico ao velocímetro do Mac)
            $needleStr = Get-NeedleGeometry 32 26 20 $pct 140 260
            if ($needleStr) {
                $needlePath = New-Object System.Windows.Shapes.Path
                $needlePath.Data = [System.Windows.Media.Geometry]::Parse($needleStr)
                $needlePath.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(240, 245, 245, 250)))
                $dialGrid.Children.Add($needlePath) | Out-Null
            }
            
            # Center Hub Pin (Pino central)
            $hub = New-Object System.Windows.Shapes.Ellipse
            $hub.Width = 6.5
            $hub.Height = 6.5
            $hub.Fill = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x18, 0x18, 0x1C)))
            $hub.Stroke = $statusBrush
            $hub.StrokeThickness = 1.2
            $hub.Margin = New-Object System.Windows.Thickness(28.75, 22.75, 0, 0)
            $hub.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
            $hub.VerticalAlignment = [System.Windows.VerticalAlignment]::Top
            $dialGrid.Children.Add($hub) | Out-Null
            
            # Center Percentage Text
            $tbPct = New-Object System.Windows.Controls.TextBlock
            $tbPct.Text = "$pct%"
            $tbPct.Foreground = [System.Windows.Media.Brushes]::White
            $tbPct.FontSize = if ($pct -ge 100) { 9.5 } else { 10 }
            $tbPct.FontWeight = [System.Windows.FontWeights]::Bold
            $tbPct.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $tbPct.Margin = New-Object System.Windows.Thickness(0, 32, 0, 0)
            $dialGrid.Children.Add($tbPct) | Out-Null
            
            $dialStack.Children.Add($dialGrid) | Out-Null
            
            # 3. Model Name Underneath (e.g. "Gemini", "Argon", "Claude")
            $mName = Get-BucketModelName $b.name $cleanTitle
            $tbMName = New-Object System.Windows.Controls.TextBlock
            $tbMName.Text = $mName
            $tbMName.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0xE2, 0xE8, 0xF0)))
            $tbMName.FontSize = 9.2
            $tbMName.FontWeight = [System.Windows.FontWeights]::SemiBold
            $tbMName.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $tbMName.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $tbMName.MaxWidth = 88
            $dialStack.Children.Add($tbMName) | Out-Null
            
            # 4. Reset Countdown Underneath (e.g. "4d 1h", "4h 51m")
            $tbReset = New-Object System.Windows.Controls.TextBlock
            $tbReset.Text = if ($b.reset_in) { $b.reset_in } else { "Ativo" }
            $tbReset.Foreground = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x8E, 0x8E, 0x9A)))
            $tbReset.FontSize = 8
            $tbReset.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
            $tbReset.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $tbReset.MaxWidth = 88
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
    $cfgWin.Owner = $window
    
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

            $currentSec = $secKey
            $currentHex = $hex
            $allBorders = $bordersList

            $b.Add_MouseLeftButtonDown({
                param($sender, $e)
                $chosenColors[$currentSec] = $currentHex
                foreach ($other in $allBorders) {
                    $other.BorderThickness = New-Object System.Windows.Thickness(0)
                }
                $sender.BorderBrush = [System.Windows.Media.Brushes]::White
                $sender.BorderThickness = New-Object System.Windows.Thickness(2)
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
            section_colors = $chosenColors
            refresh_interval_seconds = 30
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
        Refresh-Data
    })
    
    $btnCancel.Add_Click({
        $cfgWin.Close()
    })
    
    $cfgWin.ShowDialog() | Out-Null
}

function Refresh-Data {
    $btnRefresh.Content = "Refreshing..."
    $btnRefresh.IsEnabled = $false
    $window.Dispatcher.Invoke([Action]{}, "Background")
    
    $newData = Get-QuotaData -force $true
    Render-UI $newData
    if ($global:isHudMode) {
        $totalBuckets = 0
        $sectionCount = 0
        if ($newData -and $newData.groups) {
            foreach ($g in $newData.groups) {
                if ($g.buckets -and $g.buckets.Count -gt 0) {
                    $sectionCount++
                    $totalBuckets += $g.buckets.Count
                }
            }
        }
        $workArea = [System.Windows.SystemParameters]::WorkArea
        if ($totalBuckets -eq 0) {
            $hudH = 175
        } else {
            $calcH = 34 + ($sectionCount * 22) + ($totalBuckets * 86) + (($sectionCount - 1) * 10) + 26
            $maxH = [Math]::Min(780, $workArea.Height - 60)
            $hudH = [Math]::Min($maxH, [Math]::Max(160, $calcH))
        }
        $window.Width = 118
        $window.Height = $hudH
        Render-HUD $newData
    }
    $btnRefresh.Content = "↻ Refresh"
    $btnRefresh.IsEnabled = $true
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

# Initial Load
$quota = Get-QuotaData
Render-UI $quota
if ($quota) {
    if ($quota.needs_setup -or -not $quota.groups -or $quota.groups.Count -eq 0) {
        Show-SettingsDialog
    }
} else {
    Show-SettingsDialog
}

# Auto-refresh Timer (30s)
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(30)
$timer.Add_Tick({ Refresh-Data })
$timer.Start()

$window.ShowDialog() | Out-Null
