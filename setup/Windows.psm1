Import-Module (Join-Path $PSScriptRoot 'Engine.psm1') -Force -DisableNameChecking
$ErrorActionPreference='Stop'
function Get-StartupPath { [Environment]::GetFolderPath('Startup') }
function Get-WindowsBridgeState($Root,$BambuDir) {
    $state=Get-BridgeState $Root $BambuDir
    if($state.action -eq 'Keep' -and $state.version -eq (Read-Json (Join-Path $Root 'setup/payload.json')).bridgeVersion){
        try{
            Assert-BridgeOwnership (Join-Path $BambuDir 'bridge')
            $reply=Invoke-RestMethod 'http://127.0.0.1:13628/api/bridge/config' -TimeoutSec 2
            if($reply.version -ne $state.version){throw 'Loaded bridge version differs from installed files.'}
        }catch{
            $state.action='Upgrade';$state.detail='Installed files are current, but the running bridge could not be verified. Back up and repair bridge/startup.'
        }
    }
    $state
}
function Get-BridgeProcesses($BridgeDir) {
    $server=[IO.Path]::GetFullPath((Join-Path $BridgeDir 'server.js'))
    @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" | Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($server,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
}
function Assert-BridgeOwnership($BridgeDir) {
    $ours=@(Get-BridgeProcesses $BridgeDir | ForEach-Object ProcessId)
    $connections=@(Get-NetTCPConnection -LocalPort 13628 -State Listen -ErrorAction SilentlyContinue)
    foreach($c in $connections){if($ours -notcontains $c.OwningProcess){throw 'Port 13628 belongs to another installation or process. Select its Bambu folder; nothing was stopped.'}}
    $task=Get-ScheduledTask -TaskName 'BambuStudio Bridge Watchdog' -ErrorAction SilentlyContinue
    if($task){foreach($a in $task.Actions){if($a.Arguments -and $a.Arguments.IndexOf($BridgeDir,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'The watchdog belongs to another Bambu installation. Select that installation before changing the bridge.'}}}
}
function Stop-OwnedBridge($BridgeDir) {
    Assert-BridgeOwnership $BridgeDir
    $task=Get-ScheduledTask -TaskName 'BambuStudio Bridge Watchdog' -ErrorAction SilentlyContinue
    if($task){Disable-ScheduledTask -InputObject $task | Out-Null;Stop-ScheduledTask -InputObject $task}
    foreach($p in @(Get-BridgeProcesses $BridgeDir)){Stop-Process -Id $p.ProcessId -Force}
    for($i=0;$i -lt 20;$i++){if(!@(Get-BridgeProcesses $BridgeDir).Count){return};Start-Sleep -Milliseconds 100}
    throw 'Could not stop the selected bridge.'
}
function Stage-Bridge($Root,$BridgeDir) {
    $stage=$BridgeDir+'.stage-'+[guid]::NewGuid().ToString('N')
    New-Item -ItemType Directory -Path $stage | Out-Null
    try{
        $m=Read-Json (Join-Path $Root 'setup/payload.json')
        foreach($f in $m.bridge){$dest=Join-Safe $stage $f.destination;New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null;Copy-Item -LiteralPath (Join-Safe $Root $f.path) -Destination $dest}
        $node=$null
        foreach($candidate in @((Join-Path $BridgeDir 'node-runtime/node.exe'),"$env:ProgramFiles\nodejs\node.exe", "$env:LOCALAPPDATA\Programs\nodejs\node.exe")){
            if((Test-Path -LiteralPath $candidate) -and (Test-Path -LiteralPath (Join-Path (Split-Path $candidate -Parent) 'npm.cmd'))){$v=& $candidate --version;if($v -match '^v(\d+)' -and [int]$Matches[1] -ge 22){$node=$candidate;break}}
        }
        if(!$node){
            $arch=if($env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){'arm64'}else{'x64'}
            [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
            $url='https://nodejs.org/dist/latest-v22.x/'
            $checks=(Invoke-WebRequest ($url+'SHASUMS256.txt') -UseBasicParsing).Content
            $line=@($checks -split "`n" | Where-Object { $_ -match ('\snode-v22\.\d+\.\d+-win-'+$arch+'\.zip\s*$') })
            if($line.Count -ne 1){throw 'Could not obtain Node download checksum.'}
            $name=($line[0].Trim() -split '\s+')[1];$zip=Join-Path $stage $name
            Invoke-WebRequest ($url+$name) -OutFile $zip -UseBasicParsing
            if((Get-Hash $zip) -ne ($line[0] -split '\s+')[0]){throw 'Node download checksum failed.'}
            Expand-Archive -LiteralPath $zip -DestinationPath $stage
            Move-Item -LiteralPath (Join-Path $stage ([IO.Path]::GetFileNameWithoutExtension($name))) -Destination (Join-Path $stage 'node-runtime')
            Remove-Item -LiteralPath $zip;$node=Join-Path $stage 'node-runtime/node.exe'
        } elseif($node.StartsWith($BridgeDir,[StringComparison]::OrdinalIgnoreCase)){
            Copy-Item -LiteralPath (Split-Path $node -Parent) -Destination (Join-Path $stage 'node-runtime') -Recurse
            $node=Join-Path $stage 'node-runtime/node.exe'
        }
        if(Test-Path -LiteralPath (Join-Path $BridgeDir 'workspace')){Copy-Item -LiteralPath (Join-Path $BridgeDir 'workspace') -Destination $stage -Recurse -Force}
        Push-Location $stage
        try{
            $savedPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
            & (Join-Path (Split-Path $node -Parent) 'npm.cmd') ci --omit=dev --ignore-scripts --no-audit --no-fund 2>&1 | Out-Host
            $code=$LASTEXITCODE;$ErrorActionPreference=$savedPreference
            if($code -ne 0){throw 'Dependency installation failed; the running bridge has not been touched.'}
        }finally{$ErrorActionPreference='Stop';Pop-Location}
        [pscustomobject]@{path=$stage;node=$node.Replace($stage,$BridgeDir)}
    }catch{if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force};throw}
}
function Start-NewBridge($BridgeDir,$Node,$StateDir) {
    New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
    $launcher=Join-Path $StateDir 'start-hidden.vbs'
    $server=Join-Path $BridgeDir 'server.js'
    $text='Set s = CreateObject("WScript.Shell")'+"`r`n"+'s.Run """'+$Node+'"" ""'+$server+'""", 0, False'
    [IO.File]::WriteAllText($launcher,$text,[Text.Encoding]::Unicode)
    $shell=New-Object -ComObject WScript.Shell
    $link=$shell.CreateShortcut((Join-Path (Get-StartupPath) 'BambuStudio Bridge.lnk'))
    $link.TargetPath=Join-Path $env:WINDIR 'System32/wscript.exe';$link.Arguments='"'+$launcher+'"';$link.WorkingDirectory=$BridgeDir;$link.Save()
    Start-Process -FilePath $Node -ArgumentList ('"'+$server+'"') -WindowStyle Hidden -WorkingDirectory $BridgeDir
    $ready=$false
    for($i=0;$i -lt 30;$i++){
        Start-Sleep -Milliseconds 500
        try{$reply=Invoke-RestMethod 'http://127.0.0.1:13628/api/bridge/config' -TimeoutSec 2;if($reply.version -eq (Read-Json (Join-Path $BridgeDir 'package.json')).version){Assert-BridgeOwnership $BridgeDir;$ready=$true;break}}catch{}
    }
    if(!$ready){throw 'The new bridge failed its startup/version check.'}
    $action=New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $BridgeDir 'setup-watchdog.ps1')+'"')
    $trigger=New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes 2)
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
    $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType S4U -RunLevel Limited
    Register-ScheduledTask -TaskName 'BambuStudio Bridge Watchdog' -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
}
function Invoke-Setup($Root,$BambuDir,$ConfigDir,[string[]]$Sizes,$Mode,[scriptblock]$Log) {
    $m=Get-Package $Root
    if(!(Test-Path -LiteralPath (Join-Path $BambuDir 'resources/profiles'))){throw 'Select the Bambu Studio program folder containing resources/profiles.'}
    if(Get-Process -Name 'bambustudio','bambu-studio' -ErrorAction SilentlyContinue){throw 'Close Bambu Studio first.'}
    $bridgeDir=Join-Path $BambuDir 'bridge';$stateDir=Join-Path $env:APPDATA 'BambuStudio-Bridge'
    $ledgerPath=Join-Path $stateDir 'setup-installed.json'
    if(Test-Path -LiteralPath $ledgerPath){$ledger=Read-Json $ledgerPath}else{$ledger=[pscustomobject]@{version=$m.version;files=@()}}
    $state=Get-WindowsBridgeState $Root $BambuDir;$changeBridge=($Mode -eq 'Uninstall' -or ($Mode -eq 'Install' -and $state.action -ne 'Keep'))
    $targets=@((Join-Path $BambuDir 'resources/profiles'),(Join-Path $ConfigDir 'system'))
    $paths=@($ledgerPath)
    foreach($t in $targets){$paths+=Join-Path $t 'Snapmaker';$paths+=Join-Path $t 'Snapmaker.json'}
    $stage=$null;$backup=$null;$taskXml=$null;$bridgeStopped=$false;$bridgeExisted=Test-Path -LiteralPath $bridgeDir
    $startup=Join-Path (Get-StartupPath) 'BambuStudio Bridge.lnk';$launcher=Join-Path $stateDir 'start-hidden.vbs'
    if($changeBridge){
        Assert-BridgeOwnership $bridgeDir
        $paths+=@($bridgeDir,$startup,$launcher)
        $task=Get-ScheduledTask -TaskName 'BambuStudio Bridge Watchdog' -ErrorAction SilentlyContinue
        if($task){$taskXml=Export-ScheduledTask -TaskName 'BambuStudio Bridge Watchdog'}
    }
    try{
        if($Mode -eq 'Install' -and $changeBridge){& $Log 'Preparing bridge and dependencies before stopping anything...';$stage=Stage-Bridge $Root $bridgeDir}
        & $Log 'Backing up affected files...'
        $backup=New-Backup $paths (Join-Path $stateDir 'setup-backups')
        if($taskXml){[IO.File]::WriteAllText((Join-Path $backup 'watchdog.xml'),$taskXml)}
        if($changeBridge){$bridgeStopped=$true;Stop-OwnedBridge $bridgeDir}
        foreach($t in $targets){
            if($Mode -eq 'Install'){Set-Profiles $Root $t $Sizes $ledger}
            elseif($Mode -eq 'Remove'){Remove-Profiles $Root $t $Sizes -Ledger $ledger | ForEach-Object { & $Log $_ }}
            else{Remove-Profiles $Root $t @() -All -Ledger $ledger | ForEach-Object { & $Log $_ }}
        }
        if($changeBridge){
            if(Test-Path -LiteralPath $bridgeDir){Remove-Item -LiteralPath $bridgeDir -Recurse -Force}
            if($Mode -eq 'Install'){
                Move-Item -LiteralPath $stage.path -Destination $bridgeDir
                & $Log 'Starting and checking the updated bridge...';Start-NewBridge $bridgeDir $stage.node $stateDir
            }else{
                Unregister-ScheduledTask -TaskName 'BambuStudio Bridge Watchdog' -Confirm:$false -ErrorAction SilentlyContinue
                foreach($p in @($startup,$launcher)){if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force}}
            }
        }
        $ledger.version=$m.version;$ledger.files=@($ledger.files | Where-Object { Test-Path -LiteralPath $_.path } | Sort-Object path -Unique)
        Write-Json $ledgerPath $ledger
        & $Log "SUCCESS. Backup: $backup"
        if($Mode -eq 'Install' -and !$changeBridge){& $Log 'The existing bridge was left untouched.'}
        & $Log 'Custom user presets and printer connection settings were retained. Reopen Bambu Studio.'
        $backup
    }catch{
        $errorText=$_.Exception.Message
        if($backup){
            try{
                if($bridgeStopped){Stop-OwnedBridge $bridgeDir}
                Restore-Backup $backup
                if($bridgeStopped){
                    Unregister-ScheduledTask -TaskName 'BambuStudio Bridge Watchdog' -Confirm:$false -ErrorAction SilentlyContinue
                    if($taskXml){Register-ScheduledTask -TaskName 'BambuStudio Bridge Watchdog' -Xml $taskXml -Force | Out-Null}
                    if($bridgeExisted -and (Test-Path -LiteralPath $launcher)){Start-Process wscript.exe -ArgumentList ('"'+$launcher+'"')}
                }
                & $Log "Failed; previous files restored. Backup: $backup"
            }catch{& $Log "Automatic restore could not finish. Keep this backup: $backup. $($_.Exception.Message)"}
        }
        throw $errorText
    }finally{if($stage -and (Test-Path -LiteralPath $stage.path)){Remove-Item -LiteralPath $stage.path -Recurse -Force}}
}
Export-ModuleMember -Function *
