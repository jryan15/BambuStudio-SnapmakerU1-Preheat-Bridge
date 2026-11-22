# Actual transaction/file operations; Windows services/processes deliberately mocked.
$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/Engine.psm1" -Force
Import-Module "$PSScriptRoot/Windows.psm1" -Force
$r=Split-Path $PSScriptRoot -Parent
$t=Join-Path ([IO.Path]::GetTempPath()) ('u1-transaction-'+[guid]::NewGuid().ToString('N'))
$oldApp=$env:APPDATA;$env:APPDATA=Join-Path $t 'appdata'
$global:U1TestRoot=$t;$global:U1StopCount=0;$global:U1StartFail=$false
$module=Get-Module Windows
& $module {
    function script:Get-WindowsBridgeState($Root,$BambuDir) {Get-BridgeState $Root $BambuDir}
    function script:Get-StartupPath {Join-Path $global:U1TestRoot 'startup'}
    function script:Get-Process {param($Name,$ErrorAction) @()}
    function script:Assert-BridgeOwnership($BridgeDir) {}
    function script:Get-ScheduledTask {param($TaskName,$ErrorAction) $null}
    function script:Unregister-ScheduledTask {param($TaskName,$Confirm,$ErrorAction)}
    function script:Stop-OwnedBridge($BridgeDir) {$global:U1StopCount++}
    function script:Start-NewBridge($BridgeDir,$Node,$StateDir) {if($global:U1StartFail){throw 'Simulated startup failure'}}
    function script:Stage-Bridge($Root,$BridgeDir) {
        $s=$BridgeDir+'.stage-test';New-Item -ItemType Directory -Path $s -Force|Out-Null
        foreach($f in (Read-Json (Join-Path $Root 'setup/payload.json')).bridge){$p=Join-Safe $s $f.destination;New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force|Out-Null;Copy-Item -LiteralPath (Join-Safe $Root $f.path) -Destination $p}
        foreach($dep in (Read-Json (Join-Path $s 'package.json')).dependencies.PSObject.Properties.Name){$p=Join-Path $s ('node_modules/'+$dep);New-Item -ItemType Directory -Path $p -Force|Out-Null;[IO.File]::WriteAllText((Join-Path $p 'package.json'),'{}')}
        [pscustomobject]@{path=$s;node='mock-node.exe'}
    }
}
try{
    $b=Join-Path $t 'Bambu';$c=Join-Path $t 'config';New-Item -ItemType Directory -Path (Join-Path $b 'resources/profiles') -Force|Out-Null
    Invoke-Setup $r $b $c @('0.6') Install {} | Out-Null
    if($global:U1StopCount -ne 1){throw 'Install must take exclusive ownership once'}
    if((Get-BridgeState $r $b).action -ne 'Keep'){throw 'Fresh bridge not current'}
    Invoke-Setup $r $b $c @('0.2') Install {} | Out-Null
    if($global:U1StopCount -ne 1){throw 'Profile-only install stopped the current bridge'}
    $server=Join-Path $b 'bridge/server.js';$raw=Get-Content -LiteralPath $server -Raw;[IO.File]::WriteAllText($server,$raw.Replace('5.48.0-u1.4-test.7','5.48.0-u1.2'));$hash=Get-Hash $server
    $registry=Get-Hash (Join-Path $c 'system/Snapmaker.json')
    $global:U1StartFail=$true;$failed=$false
    try{Invoke-Setup $r $b $c @('0.8') Install {} | Out-Null}catch{$failed=$true}
    if(!$failed){throw 'Startup failure should abort'}
    if((Get-Hash $server) -ne $hash){throw 'Rollback did not restore previous bridge'}
    if((Get-Hash (Join-Path $c 'system/Snapmaker.json')) -ne $registry){throw 'Rollback did not restore profile registry'}
    if(Test-Path (Join-Path $c 'system/Snapmaker/machine/Snapmaker U1 (0.8 nozzle).json')){throw 'Rollback left newly installed profile'}
    $global:U1StartFail=$false
    Invoke-Setup $r $b $c @('0.8') Install {} | Out-Null
    if((Get-BridgeState $r $b).action -ne 'Keep'){throw 'Old bridge upgrade failed'}
    Invoke-Setup $r $b $c @('0.6') Remove {} | Out-Null
    if((Get-InstalledSizes (Join-Path $c 'system')) -contains '0.6'){throw 'Remove did not remove size'}
    Invoke-Setup $r $b $c @() Uninstall {} | Out-Null
    if(Test-Path (Join-Path $b 'bridge')){throw 'Uninstall left bridge'}
    if(Test-Path (Join-Path $c 'system/Snapmaker.json')){throw 'Uninstall left registry'}
    if(!(Test-Path (Join-Path $env:APPDATA 'BambuStudio-Bridge/setup-backups'))){throw 'Uninstall removed backups'}
    'PASS: transaction scenarios: fresh install, current bridge untouched, failed-upgrade rollback, old-version upgrade, selected removal, complete uninstall.'
}finally{$env:APPDATA=$oldApp;Remove-Item -LiteralPath $t -Recurse -Force}
