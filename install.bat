@echo off
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0setup\Setup.ps1" -InitialMode 0
exit /b
