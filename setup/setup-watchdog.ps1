# Windows PowerShell 5.1 compatible. No hard-coded Bambu installation path.
$launcher=Join-Path $env:APPDATA 'BambuStudio-Bridge\start-hidden.vbs'
if (!(Get-NetTCPConnection -LocalPort 13628 -State Listen -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $launcher)) {
    Start-Process wscript.exe -ArgumentList ('"'+$launcher+'"')
}
