@echo off
Set "POWERSHELL_PATH=C:\Program Files\PowerShell\7\pwsh.exe"
Set "SCRIPT_PATH=C:\Scripts\Separations\Main.ps1"

"%POWERSHELL_PATH%" -NoProfile -ExecutionPolicy Bypass -Command ". '%SCRIPT_PATH%'"

