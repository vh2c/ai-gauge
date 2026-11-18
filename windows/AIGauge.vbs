Set WshShell = CreateObject("WScript.Shell")
Set Fso = CreateObject("Scripting.FileSystemObject")
ScriptDir = Fso.GetParentFolderName(WScript.ScriptFullName)
PsFile = ScriptDir & "\AIGauge.ps1"
If Not Fso.FileExists(PsFile) Then
    PsFile = ScriptDir & "\GeminiGauge.ps1"
End If
If Fso.FileExists(PsFile) Then
    WshShell.Run "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File """ & PsFile & """", 0, False
Else
    MsgBox "Startup file not found:" & vbCrLf & PsFile, 16, "AI Gauge"
End If
