Set WshShell = CreateObject("WScript.Shell")
Set Fso = CreateObject("Scripting.FileSystemObject")
ScriptDir = Fso.GetParentFolderName(WScript.ScriptFullName)
PsFile = ScriptDir & "\AIGauge.ps1"
If Not Fso.FileExists(PsFile) Then
    PsFile = ScriptDir & "\GeminiGauge.ps1"
End If
If Fso.FileExists(PsFile) Then
    cmd = "powershell.exe -ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File """ & PsFile & """"
    ret = WshShell.Run(cmd, 0, True)
    If ret <> 0 Then
        tempDir = WshShell.ExpandEnvironmentStrings("%TEMP%")
        logFile = tempDir & "\ai_gauge_error.log"
        If Fso.FileExists(logFile) Then
            Set f = Fso.OpenTextFile(logFile, 1)
            errText = f.ReadAll()
            f.Close
            If Len(Trim(errText)) > 0 Then
                MsgBox "AI Gauge failed to start:" & vbCrLf & vbCrLf & errText, 16, "AI Gauge"
            End If
        Else
            ' Re-run once to capture stderr if PowerShell failed before creating log
            cmdErr = "cmd.exe /c ""powershell.exe -ExecutionPolicy Bypass -NoProfile -File """"" & PsFile & """"" 2> """"" & logFile & """""""
            WshShell.Run cmdErr, 0, True
            If Fso.FileExists(logFile) Then
                Set f = Fso.OpenTextFile(logFile, 1)
                errText = f.ReadAll()
                f.Close
                If Len(Trim(errText)) > 0 Then
                    MsgBox "AI Gauge failed to start:" & vbCrLf & vbCrLf & errText, 16, "AI Gauge"
                End If
            End If
        End If
    End If
Else
    MsgBox "Startup file not found:" & vbCrLf & PsFile, 16, "AI Gauge"
End If
