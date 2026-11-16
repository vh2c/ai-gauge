<#
.SYNOPSIS
    AI Gauge - Windows Edition (PowerShell + WPF)
    Developed by VH2C • https://vh2c.com.br
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Web

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

# 1. Curated Pastel Theme
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
    @{ Name = "Azul Céu";  Hex = "#8FBCFF" },
    @{ Name = "Menta";     Hex = "#8AE39A" },
    @{ Name = "Coral";     Hex = "#FF5265" },
    @{ Name = "Terracota"; Hex = "#D78C68" },
    @{ Name = "Lavanda";   Hex = "#C084FC" },
    @{ Name = "Ciano";     Hex = "#67E8F9" },
    @{ Name = "Rosa";      Hex = "#F472B6" },
    @{ Name = "Pêssego";   Hex = "#FDBA74" },
    @{ Name = "Amarelo";   Hex = "#FDE047" },
    @{ Name = "Prata";     Hex = "#E2E8F0" }
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
        try { return (Get-Content $ConfigFile -Raw | ConvertFrom-Json) } catch {}
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

# 2. Telemetry Heartbeat
function Send-TelemetryHeartbeat {
    try {
        $machineId = ""
        if (Test-Path $DeviceIdFile) {
            $machineId = (Get-Content $DeviceIdFile -Raw).Trim()
        }
        if (-not $machineId) {
            $machineId = [guid]::NewGuid().ToString("N")
            Set-Content -Path $DeviceIdFile -Value $machineId -Encoding UTF8
        }

        $payload = @{
            app = "gemini-gauge"
            version = "1.1.0"
            os = "Windows"
            arch = $env:PROCESSOR_ARCHITECTURE
            machine_id = $machineId
            timestamp = [int][double]::Parse((Get-Date -UFormat %s))
        } | ConvertTo-Json

        Start-Job -ScriptBlock {
            param($body)
            try {
                $endpoint = "https://ai-gauge.vh2c.com.br/api/telemetry"
                Invoke-RestMethod -Uri $endpoint -Method Post -Body $body -ContentType "application/json" -TimeoutSec 3 -ErrorAction SilentlyContinue
            } catch {}
        } -ArgumentList $payload | Out-Null
    } catch {}
}

Send-TelemetryHeartbeat

# 3. Find Node binary
function Find-NodeBinary {
    $cmd = Get-Command "node.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $localNode = Join-Path $ScriptDir "bin\node.exe"
    if (Test-Path $localNode) { return $localNode }
    return "node"
}

$NodeExe = Find-NodeBinary

function Get-QuotaData ($force = $false) {
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

# 4. Main Cockpit Window XAML
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AI Gauge - Universal AI Quota Cockpit" Height="640" Width="470"
        WindowStartupLocation="CenterScreen" Background="#181818" ResizeMode="CanMinimize">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- Header -->
        <StackPanel Grid.Row="0" Margin="0,0,0,14">
            <StackPanel Orientation="Horizontal">
                <TextBlock Text="⚡ AI Gauge" Foreground="#00E699" FontSize="15" FontWeight="Bold"/>
                <TextBlock Text=" • Universal AI Quota Cockpit" Foreground="#EEEEEE" FontSize="14" FontWeight="SemiBold"/>
            </StackPanel>
            <TextBlock Name="TxtAccount" Text="Carregando cotas..." Foreground="#888888" FontSize="11" Margin="0,4,0,0"/>
        </StackPanel>
        
        <!-- Cards List -->
        <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
            <StackPanel Name="CardsPanel" Margin="0,0,6,0"/>
        </ScrollViewer>
        
        <!-- Footer -->
        <StackPanel Grid.Row="2" Margin="0,14,0,0">
            <!-- Row 1: Action Buttons -->
            <Grid>
                <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
                    <Button Name="BtnRefresh" Content="↻ Atualizar" Width="84" Height="28" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold" Margin="0,0,6,0" Cursor="Hand"/>
                    <Button Name="BtnHud" Content="⤢ Barra HUD" Width="92" Height="28" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold" Margin="0,0,6,0" Cursor="Hand"/>
                    <Button Name="BtnSettings" Content="⚙ Configurar" Width="92" Height="28" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold" Cursor="Hand"/>
                </StackPanel>
                
                <Button Name="BtnClose" Content="✕ Fechar" Width="68" Height="28" HorizontalAlignment="Right" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold" Cursor="Hand"/>
            </Grid>
            
            <!-- Row 2: Brand Link -->
            <TextBlock Name="TxtBrand" Text="⚡ AI Gauge  •  Desenvolvido por vh2c.com.br"
                       Foreground="#38BDF8" FontSize="10.5" FontWeight="SemiBold"
                       HorizontalAlignment="Center" Margin="0,10,0,0" Cursor="Hand"/>
        </StackPanel>
    </Grid>
</Window>
"@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# Set Window Icon
$iconFile = Join-Path $ScriptDir "icon.ico"
if (-not (Test-Path $iconFile)) {
    $iconFile = Join-Path $RepoDir "assets\icon.ico"
}
if (Test-Path $iconFile) {
    try {
        $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create($iconFile)
    } catch {}
}

$txtAcc = $window.FindName("TxtAccount")
$cardsPanel = $window.FindName("CardsPanel")
$btnRefresh = $window.FindName("BtnRefresh")
$btnHud = $window.FindName("BtnHud")
$btnSettings = $window.FindName("BtnSettings")
$btnClose = $window.FindName("BtnClose")
$txtBrand = $window.FindName("TxtBrand")

# 5. Floating HUD Window XAML
[xml]$hudXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="AI Gauge HUD" Width="246" Height="560"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ResizeMode="NoResize" ShowInTaskbar="True">
    <Border Background="#F2141416" BorderBrush="#2C2C34" BorderThickness="1" CornerRadius="10" Padding="12">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>
            
            <!-- HUD Header -->
            <Grid Grid.Row="0" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                
                <StackPanel Grid.Column="0" VerticalAlignment="Center">
                    <StackPanel Orientation="Horizontal">
                        <TextBlock Text="⚡ AI Gauge" Foreground="#00E699" FontSize="12.5" FontWeight="Bold"/>
                        <TextBlock Text=" HUD" Foreground="#FFFFFF" FontSize="12.5" FontWeight="Bold"/>
                    </StackPanel>
                    <TextBlock Name="TxtHudSubtitle" Text="Modo Barra Lateral" Foreground="#888888" FontSize="9.5" Margin="0,2,0,0"/>
                </StackPanel>
                
                <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                    <Button Name="BtnHudCockpit" Content="⤢ Cockpit" Height="22" Padding="6,1,6,1" Background="#2A2A32" Foreground="#E2E8F0" BorderBrush="#3C3C46" FontSize="10" FontWeight="SemiBold" Cursor="Hand" Margin="0,0,4,0"/>
                    <Button Name="BtnHudClose" Content="✕" Width="22" Height="22" Background="#2A2A32" Foreground="#888888" BorderBrush="#3C3C46" FontSize="10" FontWeight="Bold" Cursor="Hand"/>
                </StackPanel>
            </Grid>
            
            <!-- HUD Gauge List -->
            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                <StackPanel Name="HudCardsPanel" Margin="0,0,2,0"/>
            </ScrollViewer>
            
            <!-- HUD Footer -->
            <TextBlock Grid.Row="2" Text="⚡ Arraste para mover • Ctrl+M" Foreground="#555555" FontSize="9" HorizontalAlignment="Center" Margin="0,8,0,0"/>
        </Grid>
    </Border>
</Window>
"@

$hudReader = (New-Object System.Xml.XmlNodeReader $hudXaml)
$hudWindow = [System.Windows.Markup.XamlReader]::Load($hudReader)

# Position HUD Window near top right
try {
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $hudWindow.Left = $workArea.Right - 262
    $hudWindow.Top = 32
} catch {}

$txtHudSubtitle = $hudWindow.FindName("TxtHudSubtitle")
$hudCardsPanel = $hudWindow.FindName("HudCardsPanel")
$btnHudCockpit = $hudWindow.FindName("BtnHudCockpit")
$btnHudClose = $hudWindow.FindName("BtnHudClose")

# Allow dragging the HUD window from anywhere
$hudWindow.Add_MouseLeftButtonDown({
    try { $hudWindow.DragMove() } catch {}
})

$global:isHudMode = $false
$global:currentData = $null

function Toggle-HudMode {
    if ($global:isHudMode) {
        $global:isHudMode = $false
        $hudWindow.Hide()
        $window.Show()
        $window.Activate()
    } else {
        $global:isHudMode = $true
        $window.Hide()
        if ($global:currentData) {
            Render-HUD $global:currentData
        }
        $hudWindow.Show()
        $hudWindow.Activate()
    }
}

$btnHud.Add_Click({ Toggle-HudMode })
$btnHudCockpit.Add_Click({ Toggle-HudMode })
$btnHudClose.Add_Click({
    $hudWindow.Close()
    $window.Close()
})

# Hotkey Ctrl+M on both windows
$hotkeyHandler = {
    param($sender, $e)
    if ($e.Key -eq [System.Windows.Input.Key]::M -and ([System.Windows.Input.Keyboard]::Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
        Toggle-HudMode
    }
}
$window.Add_KeyDown($hotkeyHandler)
$hudWindow.Add_KeyDown($hotkeyHandler)

# 6. Render Full Cockpit UI
function Render-UI ($data) {
    $global:currentData = $data
    if (-not $data) {
        $txtAcc.Text = "Nenhum provedor ativo ou conectado. Clique em Configurar."
        return
    }
    
    $cacheInfo = if ($data.from_cache) { " (Cache)" } else { " (Tempo real)" }
    $txtAcc.Text = "$($data.account) • Plano $($data.plan) • Atualizado às $($data.updated_at)$cacheInfo"
    $cardsPanel.Children.Clear()
    
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
        $btnDl.Content = "Baixar"
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

    # ----------------- ANNOUNCEMENT / FREE VS PRO -----------------
    if ($data.announcement -and $data.announcement.message) {
        $annBorder = New-Object System.Windows.Controls.Border
        $annBorder.Background = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(40, 0x38, 0xBD, 0xF8)))
        $annBorder.BorderBrush = (New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x38, 0xBD, 0xF8)))
        $annBorder.BorderThickness = (New-Object System.Windows.Thickness(1))
        $annBorder.CornerRadius = (New-Object System.Windows.CornerRadius(6))
        $annBorder.Padding = (New-Object System.Windows.Thickness(12, 8, 12, 8))
        $annBorder.Margin = (New-Object System.Windows.Thickness(0, 0, 0, 10))
        
        $annStack = New-Object System.Windows.Controls.StackPanel
        $annHead = New-Object System.Windows.Controls.TextBlock
        $annHead.Text = "[$($data.announcement.badge)] $($data.announcement.title)"
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
            $btnAct = New-Object System.Windows.Controls.Button
            $btnAct.Content = "$($data.announcement.action_label) →"
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
        
        # Clean section title
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
            $resetStr = if ($b.reset_in) { " • $($b.reset_in)" } else { "" }
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

# 7. Render HUD UI (Compact Floating View)
function Render-HUD ($data) {
    if (-not $data) { return }
    $hudCardsPanel.Children.Clear()
    $txtHudSubtitle.Text = "Atualizado às $($data.updated_at)"
    
    foreach ($g in $data.groups) {
        $provKey = Get-ProviderKey $g.name $g.provider
        $accentHex = Get-GroupColorHex $g.name $g.provider
        $accentBrush = Convert-HexToBrush $accentHex
        
        $cleanTitle = $g.name
        if ($provKey -eq "claude_pro") { $cleanTitle = "Claude" }
        elseif ($provKey -eq "chatgpt_subscription") { $cleanTitle = "ChatGPT" }
        elseif ($provKey -eq "cursor") { $cleanTitle = "Cursor" }
        elseif ($provKey -eq "github_copilot") { $cleanTitle = "Copilot" }
        elseif ($provKey -eq "gemini") { $cleanTitle = "Gemini" }
        
        $secHeader = New-Object System.Windows.Controls.TextBlock
        $secHeader.Text = ($cleanTitle).ToUpper()
        $secHeader.Foreground = $accentBrush
        $secHeader.FontSize = 9.5
        $secHeader.FontWeight = [System.Windows.FontWeights]::Bold
        $secHeader.Margin = New-Object System.Windows.Thickness(0, 8, 0, 3)
        $hudCardsPanel.Children.Add($secHeader) | Out-Null
        
        $hudCard = New-Object System.Windows.Controls.Border
        $hudCard.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x1B, 0x1B, 0x1E))
        $hudCard.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x30))
        $hudCard.BorderThickness = New-Object System.Windows.Thickness(1)
        $hudCard.CornerRadius = New-Object System.Windows.CornerRadius(6)
        $hudCard.Padding = New-Object System.Windows.Thickness(8, 6, 8, 6)
        $hudCard.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
        
        $hudStack = New-Object System.Windows.Controls.StackPanel
        
        $bIdx = 0
        foreach ($b in $g.buckets) {
            if ($bIdx -gt 0) {
                $sep = New-Object System.Windows.Controls.Separator
                $sep.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x24, 0x24, 0x2A))
                $sep.Margin = New-Object System.Windows.Thickness(0, 4, 0, 4)
                $hudStack.Children.Add($sep) | Out-Null
            }
            
            $row = New-Object System.Windows.Controls.Grid
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Auto)
            $row.ColumnDefinitions.Add($c1)
            $row.ColumnDefinitions.Add($c2)
            
            $tbName = New-Object System.Windows.Controls.TextBlock
            $tbName.Text = $b.name
            $tbName.Foreground = [System.Windows.Media.Brushes]::White
            $tbName.FontSize = 10
            [System.Windows.Controls.Grid]::SetColumn($tbName, 0)
            $row.Children.Add($tbName) | Out-Null
            
            $pct = [int]$b.remaining_pct
            $tbVal = New-Object System.Windows.Controls.TextBlock
            $tbVal.Text = "$pct%"
            $tbVal.Foreground = Get-StatusBrush $pct $accentHex
            $tbVal.FontWeight = [System.Windows.FontWeights]::Bold
            $tbVal.FontSize = 10
            [System.Windows.Controls.Grid]::SetColumn($tbVal, 1)
            $row.Children.Add($tbVal) | Out-Null
            
            $hudStack.Children.Add($row) | Out-Null
            
            # HUD Progress bar
            $pbarBg = New-Object System.Windows.Controls.Border
            $pbarBg.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x28, 0x28, 0x30))
            $pbarBg.Height = 5
            $pbarBg.CornerRadius = New-Object System.Windows.CornerRadius(2.5)
            $pbarBg.Margin = New-Object System.Windows.Thickness(0, 3, 0, 2)
            
            $pbarFill = New-Object System.Windows.Controls.Border
            $pbarFill.Background = Get-StatusBrush $pct $accentHex
            $pbarFill.Height = 5
            $pbarFill.CornerRadius = New-Object System.Windows.CornerRadius(2.5)
            $pbarFill.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Left
            $pbarFill.Width = [Math]::Max(4, (196 * ($pct / 100.0)))
            
            $pbarBg.Child = $pbarFill
            $hudStack.Children.Add($pbarBg) | Out-Null
            
            $bIdx++
        }
        
        $hudCard.Child = $hudStack
        $hudCardsPanel.Children.Add($hudCard) | Out-Null
    }
}

# 8. Settings Dialog with Pastel Palette Selection
function Show-SettingsDialog {
    [xml]$cfgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Configurações - AI Gauge" Height="620" Width="460"
        WindowStartupLocation="CenterOwner" Background="#181818" ResizeMode="NoResize">
    <Grid Margin="18">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <StackPanel Grid.Row="0" Margin="0,0,0,12">
            <TextBlock Text="⚙️ Configurar Provedores de IA &amp; Cores Pastel" Foreground="#FFFFFF" FontSize="14" FontWeight="Bold"/>
            <TextBlock Text="Ative os provedores, insira suas credenciais e personalize as cores:" Foreground="#888888" FontSize="10.5" Margin="0,3,0,0"/>
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
                        <TextBlock Text="💡 Detecta cotas do IDE em execução ou via sonda headless." Foreground="#777777" FontSize="9.5" Margin="20,4,0,0"/>
                    </StackPanel>
                </Border>
                
                <!-- Claude -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkClaudePro" Content="Claude" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelClaude" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <TextBox Name="TxtClaudeProToken" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="💡 Token OAuth da assinatura Claude (detectado automaticamente no Keychain)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- ChatGPT -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkChatGPT" Content="ChatGPT" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelChatGPT" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <TextBox Name="TxtChatGPTToken" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="💡 Token de Acesso / Sessão do ChatGPT (janela de 3h e cota semanal o1)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- Cursor -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkCursor" Content="Cursor" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelCursor" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <TextBox Name="TxtCursorToken" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="💡 Token de Sessão do Cursor (opcional se logado no Cursor)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- Copilot -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkCopilot" Content="Copilot" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelCopilot" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <TextBox Name="TxtCopilotToken" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="💡 GitHub Personal Access Token para Copilot (opcional)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- Google Gemini -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkGemini" Content="Google Gemini" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelGemini" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <TextBox Name="TxtGeminiKey" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Name="LinkAiStudio" Text="Obter chave gratuita no Google AI Studio (aistudio.google.com) ↗" Foreground="#38BDF8" FontSize="9.5" Cursor="Hand"/>
                    </StackPanel>
                </Border>
                
                <!-- OpenAI -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkOpenAI" Content="OpenAI" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelOpenAI" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <TextBox Name="TxtOpenAIKey" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="💡 Chave de API OpenAI (sk-...)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
                
                <!-- Anthropic -->
                <Border Background="#1F1F22" BorderBrush="#2C2C33" BorderThickness="1" CornerRadius="6" Padding="10" Margin="0,0,0,8">
                    <StackPanel>
                        <Grid>
                            <CheckBox Name="ChkClaude" Content="Anthropic" Foreground="#FFFFFF" FontWeight="Bold" VerticalAlignment="Center"/>
                            <StackPanel Name="ColorPanelAnthropic" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center"/>
                        </Grid>
                        <TextBox Name="TxtClaudeKey" Height="24" Background="#141416" Foreground="#FFFFFF" BorderBrush="#333338" Margin="0,6,0,4"/>
                        <TextBlock Text="💡 Chave de API Anthropic (sk-ant-...)" Foreground="#777777" FontSize="9.5"/>
                    </StackPanel>
                </Border>
            </StackPanel>
        </ScrollViewer>
        
        <Grid Grid.Row="2" Margin="0,12,0,0">
            <Button Name="BtnSave" Content="Salvar e Atualizar" Width="130" Height="28" HorizontalAlignment="Left" Background="#EEEEF0" Foreground="#181818" FontWeight="Bold" Cursor="Hand"/>
            <Button Name="BtnCancel" Content="Cancelar" Width="80" Height="28" HorizontalAlignment="Right" Background="#333333" Foreground="#FFFFFF" Cursor="Hand"/>
        </Grid>
    </Grid>
</Window>
"@

    $cfgReader = (New-Object System.Xml.XmlNodeReader $cfgXaml)
    $cfgWin = [System.Windows.Markup.XamlReader]::Load($cfgReader)
    $cfgWin.Owner = $window
    
    $chkAnti = $cfgWin.FindName("ChkAnti")
    $pnlAnti = $cfgWin.FindName("ColorPanelAnti")
    
    $chkClaudePro = $cfgWin.FindName("ChkClaudePro")
    $txtClaudePro = $cfgWin.FindName("TxtClaudeProToken")
    $pnlClaude = $cfgWin.FindName("ColorPanelClaude")
    
    $chkChatGPT = $cfgWin.FindName("ChkChatGPT")
    $txtChatGPT = $cfgWin.FindName("TxtChatGPTToken")
    $pnlChatGPT = $cfgWin.FindName("ColorPanelChatGPT")
    
    $chkCursor = $cfgWin.FindName("ChkCursor")
    $txtCursor = $cfgWin.FindName("TxtCursorToken")
    $pnlCursor = $cfgWin.FindName("ColorPanelCursor")
    
    $chkCopilot = $cfgWin.FindName("ChkCopilot")
    $txtCopilot = $cfgWin.FindName("TxtCopilotToken")
    $pnlCopilot = $cfgWin.FindName("ColorPanelCopilot")
    
    $chkGemini = $cfgWin.FindName("ChkGemini")
    $txtGemini = $cfgWin.FindName("TxtGeminiKey")
    $linkAiStudio = $cfgWin.FindName("LinkAiStudio")
    $pnlGemini = $cfgWin.FindName("ColorPanelGemini")
    
    $chkOpenAI = $cfgWin.FindName("ChkOpenAI")
    $txtOpenAI = $cfgWin.FindName("TxtOpenAIKey")
    $pnlOpenAI = $cfgWin.FindName("ColorPanelOpenAI")
    
    $chkClaude = $cfgWin.FindName("ChkClaude")
    $txtClaude = $cfgWin.FindName("TxtClaudeKey")
    $pnlAnthropic = $cfgWin.FindName("ColorPanelAnthropic")
    
    $btnSave = $cfgWin.FindName("BtnSave")
    $btnCancel = $cfgWin.FindName("BtnCancel")
    
    # Load current configuration
    $currentCfg = Load-CurrentConfig
    $selectedColors = @{}
    foreach ($k in $PastelDefaults.Keys) {
        if ($currentCfg -and $currentCfg.section_colors -and $currentCfg.section_colors.$k) {
            $selectedColors[$k] = "$($currentCfg.section_colors.$k)"
        } else {
            $selectedColors[$k] = $PastelDefaults[$k]
        }
    }
    
    # Helper to build pastel color swatch picker for each provider
    function Build-SwatchPicker ($panel, $providerKey) {
        $panel.Children.Clear()
        
        $lbl = New-Object System.Windows.Controls.TextBlock
        $lbl.Text = "Cor:"
        $lbl.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromRgb(0x99, 0x99, 0x99))
        $lbl.FontSize = 10
        $lbl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $lbl.Margin = New-Object System.Windows.Thickness(0, 0, 5, 0)
        $panel.Children.Add($lbl) | Out-Null
        
        $swatches = @()
        foreach ($p in $PastelPalette) {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Width = 14
            $btn.Height = 14
            $btn.Margin = New-Object System.Windows.Thickness(1.5, 0, 1.5, 0)
            $btn.Background = Convert-HexToBrush $p.Hex
            $btn.Cursor = [System.Windows.Input.Cursors]::Hand
            $btn.ToolTip = "$($p.Name) ($($p.Hex))"
            $btn.Tag = $p.Hex
            
            $curHex = $selectedColors[$providerKey]
            if ($p.Hex.ToUpper() -eq $curHex.ToUpper()) {
                $btn.BorderBrush = [System.Windows.Media.Brushes]::White
                $btn.BorderThickness = New-Object System.Windows.Thickness(2)
            } else {
                $btn.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(60, 0, 0, 0))
                $btn.BorderThickness = New-Object System.Windows.Thickness(1)
            }
            
            $swatches += $btn
            $panel.Children.Add($btn) | Out-Null
        }
        
        foreach ($b in $swatches) {
            $clickedHex = $b.Tag
            $b.Add_Click({
                $selectedColors[$providerKey] = $clickedHex
                foreach ($sw in $swatches) {
                    if ($sw.Tag.ToUpper() -eq $clickedHex.ToUpper()) {
                        $sw.BorderBrush = [System.Windows.Media.Brushes]::White
                        $sw.BorderThickness = New-Object System.Windows.Thickness(2)
                    } else {
                        $sw.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.Color]::FromArgb(60, 0, 0, 0))
                        $sw.BorderThickness = New-Object System.Windows.Thickness(1)
                    }
                }
            })
        }
    }
    
    Build-SwatchPicker $pnlAnti "antigravity"
    Build-SwatchPicker $pnlClaude "claude_pro"
    Build-SwatchPicker $pnlChatGPT "chatgpt_subscription"
    Build-SwatchPicker $pnlCursor "cursor"
    Build-SwatchPicker $pnlCopilot "github_copilot"
    Build-SwatchPicker $pnlGemini "gemini"
    Build-SwatchPicker $pnlOpenAI "openai"
    Build-SwatchPicker $pnlAnthropic "anthropic"
    
    if ($currentCfg -and $currentCfg.providers) {
        $chkAnti.IsChecked = ($currentCfg.providers.antigravity.enabled -ne $false)
        $chkClaudePro.IsChecked = ($currentCfg.providers.claude_pro.enabled -ne $false)
        $txtClaudePro.Text = "$($currentCfg.providers.claude_pro.token)"
        $chkChatGPT.IsChecked = ($currentCfg.providers.chatgpt_subscription.enabled -ne $false)
        $txtChatGPT.Text = "$($currentCfg.providers.chatgpt_subscription.token)"
        $chkCursor.IsChecked = ($currentCfg.providers.cursor.enabled -ne $false)
        $txtCursor.Text = "$($currentCfg.providers.cursor.token)"
        $chkCopilot.IsChecked = ($currentCfg.providers.github_copilot.enabled -ne $false)
        $txtCopilot.Text = "$($currentCfg.providers.github_copilot.token)"
        $chkGemini.IsChecked = [bool]($currentCfg.providers.gemini.enabled)
        $txtGemini.Text = "$($currentCfg.providers.gemini.api_key)"
        $chkOpenAI.IsChecked = [bool]($currentCfg.providers.openai.enabled)
        $txtOpenAI.Text = "$($currentCfg.providers.openai.api_key)"
        $chkClaude.IsChecked = [bool]($currentCfg.providers.anthropic.enabled)
        $txtClaude.Text = "$($currentCfg.providers.anthropic.api_key)"
    } else {
        $chkAnti.IsChecked = $true
        $chkClaudePro.IsChecked = $true
        $chkChatGPT.IsChecked = $true
        $chkCursor.IsChecked = $true
        $chkCopilot.IsChecked = $true
    }
    
    $linkAiStudio.Add_MouseDown({
        [System.Diagnostics.Process]::Start("https://aistudio.google.com/app/apikey")
    })
    
    $btnSave.Add_Click({
        $newCfg = @{
            providers = @{
                antigravity = @{
                    enabled = [bool]$chkAnti.IsChecked
                }
                claude_pro = @{
                    enabled = [bool]$chkClaudePro.IsChecked
                    token = $txtClaudePro.Text.Trim()
                }
                chatgpt_subscription = @{
                    enabled = [bool]$chkChatGPT.IsChecked
                    token = $txtChatGPT.Text.Trim()
                }
                cursor = @{
                    enabled = [bool]$chkCursor.IsChecked
                    token = $txtCursor.Text.Trim()
                }
                github_copilot = @{
                    enabled = [bool]$chkCopilot.IsChecked
                    token = $txtCopilot.Text.Trim()
                }
                gemini = @{
                    enabled = [bool]$chkGemini.IsChecked
                    api_key = $txtGemini.Text.Trim()
                }
                openai = @{
                    enabled = [bool]$chkOpenAI.IsChecked
                    api_key = $txtOpenAI.Text.Trim()
                }
                anthropic = @{
                    enabled = [bool]$chkClaude.IsChecked
                    api_key = $txtClaude.Text.Trim()
                }
            }
            section_colors = $selectedColors
            refresh_interval_seconds = 30
        }
        $newCfg | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFile -Encoding UTF8
        $cfgWin.Close()
        Refresh-Data
    })
    
    $btnCancel.Add_Click({
        $cfgWin.Close()
    })
    
    $cfgWin.ShowDialog() | Out-Null
}

function Refresh-Data {
    $btnRefresh.Content = "Atualizando..."
    $btnRefresh.IsEnabled = $false
    $window.Dispatcher.Invoke([Action]{}, "Background")
    
    $newData = Get-QuotaData -force $true
    if ($newData) {
        Render-UI $newData
        if ($global:isHudMode) {
            Render-HUD $newData
        }
    }
    $btnRefresh.Content = "↻ Atualizar"
    $btnRefresh.IsEnabled = $true
}

# Event Listeners
$btnRefresh.Add_Click({ Refresh-Data })
$btnSettings.Add_Click({ Show-SettingsDialog })
$btnClose.Add_Click({
    $hudWindow.Close()
    $window.Close()
})
$txtBrand.Add_MouseDown({
    [System.Diagnostics.Process]::Start("https://vh2c.com.br")
})

# Initial Load
$quota = Get-QuotaData
if ($quota) {
    Render-UI $quota
    if ($quota.needs_setup -or -not $quota.groups) {
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
