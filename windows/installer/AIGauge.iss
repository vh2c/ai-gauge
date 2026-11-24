; AI Gauge - Windows Setup (Inno Setup 6)
; Build:  ISCC.exe /DMyAppVersion=1.3.3 windows\installer\AIGauge.iss
; Needs windows\bin\node.exe (see windows\installer\fetch-node.ps1). Output: dist\AI-Gauge-Setup.exe

#ifndef MyAppVersion
  #define MyAppVersion "1.3.3"
#endif

[Setup]
AppId={{8E3F2B1C-5D4A-4B7E-9C21-A6F0D1E7B3C9}
AppName=AI Gauge
AppVersion={#MyAppVersion}
AppPublisher=VH2C
AppPublisherURL=https://vh2c.com.br
AppSupportURL=https://vh2c.com.br
DefaultDirName={localappdata}\AIGauge
DisableProgramGroupPage=yes
DisableDirPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename=AI-Gauge-Setup
SetupIconFile=..\icon.ico
UninstallDisplayIcon={app}\icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a Desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "..\AIGauge.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\AIGauge.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\get-ai-gauge.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\icon.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\bin\node.exe"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "..\..\core\*"; DestDir: "{app}\core"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\config.example.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\AI Gauge"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\AIGauge.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\icon.ico"
Name: "{autodesktop}\AI Gauge"; Filename: "{sys}\wscript.exe"; Parameters: """{app}\AIGauge.vbs"""; WorkingDir: "{app}"; IconFilename: "{app}\icon.ico"; Tasks: desktopicon

[InstallDelete]
; Leftovers from the older script-based installer (...\GeminiGauge) and its shortcuts
Type: filesandordirs; Name: "{localappdata}\GeminiGauge"
Type: files; Name: "{userdesktop}\Gemini Gauge.lnk"
Type: files; Name: "{userdesktop}\Antigravity Quota Hub.lnk"
Type: files; Name: "{userdesktop}\Universal AI Quota.lnk"
Type: files; Name: "{userprograms}\Gemini Gauge.lnk"
Type: files; Name: "{userprograms}\Antigravity Quota Hub.lnk"
Type: files; Name: "{userprograms}\Universal AI Quota.lnk"
Type: files; Name: "{userprograms}\Desinstalar AI Gauge.lnk"
Type: files; Name: "{userprograms}\Uninstall AI Gauge.lnk"
; Clean previous files in the install folder (user settings live in ~\.config and are kept)
Type: filesandordirs; Name: "{app}\core"
Type: files; Name: "{app}\*.ps1"
Type: files; Name: "{app}\*.bat"
Type: files; Name: "{app}\GeminiGauge.vbs"
Type: files; Name: "{app}\AntigravityQuotaHub.vbs"

[Registry]
; Remove the "Apps installed" entry created by the older install.ps1 (Setup registers its own)
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\AIGauge"; Flags: deletekey

[Run]
Filename: "{sys}\wscript.exe"; Parameters: """{app}\AIGauge.vbs"""; Description: "Launch AI Gauge"; Flags: nowait postinstall skipifsilent

[Code]
procedure StopRunningGauge();
var
  ResultCode: Integer;
begin
  Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq ''powershell.exe'' -or $_.Name -eq ''wscript.exe'' -or $_.Name -eq ''node.exe'') -and $_.ProcessId -ne $PID -and ($_.CommandLine -match ''AIGauge|GeminiGauge|AntigravityQuotaHub'' -or $_.ExecutablePath -like ''*AIGauge*'' -or $_.ExecutablePath -like ''*GeminiGauge*'') } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopRunningGauge();
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopRunningGauge();
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    if MsgBox('Also remove your settings (accounts, tokens and colors)?' + #13#10 + 'Choose "No" to keep them in case you reinstall later.',
              mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      DelTree(ExpandConstant('{userprofile}\.config\UniversalAIQuota'), True, True, True);
  end;
end;
