$ErrorActionPreference='Stop'
Import-Module "$PSScriptRoot/Engine.psm1" -Force
$root=Split-Path $PSScriptRoot -Parent
$temp=Join-Path ([IO.Path]::GetTempPath()) ('u1-setup-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp | Out-Null
$checks=0
function Assert($Condition,$Message){if(!$Condition){throw "FAIL: $Message"};$script:checks++}
try{
    $regular=Join-Path $temp 'BambuStudio';$beta=Join-Path $temp 'BambuStudioBeta'
    New-Item -ItemType Directory -Path (Join-Path $beta 'system') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $beta 'system/Snapmaker.json'),'{}')
    Assert ((Get-SettingsFolder 'C:\Program Files\Bambu Studio' $temp) -eq $regular) 'regular wins despite leftover Beta profiles'
    Assert ((Get-SettingsFolder 'C:\Program Files\Bambu Studio Beta' $temp) -eq $beta) 'Beta application uses Beta settings'
    Assert ((Get-SettingsFolder 'C:\Custom\Bambu' $temp '2.9.1.70-beta') -eq $beta) 'Beta executable metadata overrides neutral folder'
    Assert ((Get-SettingsFolder 'C:\Custom\Bambu' $temp '2.9.1.70') -eq $regular) 'regular executable uses regular settings'
    Assert ((Get-SettingsFolder 'C:\Program Files\Bambu Studio\' $temp) -eq $regular) 'trailing separator handled'
    Assert ((Get-SettingsFolder 'C:\Custom\Bambu' $temp) -eq $regular) 'unknown defaults to regular, manual override available'
    $m=Get-Package $root
    $profiles=Join-Path $temp 'profiles';$ledger=[pscustomobject]@{version='test';files=@()}
    Set-Profiles $root $profiles @('0.6') $ledger
    $reg=Read-Json (Join-Path $profiles 'Snapmaker.json')
    Assert (@($reg.machine_list | Where-Object name -eq 'Snapmaker U1 (0.6 nozzle)').Count -eq 1) '0.6 selected'
    Assert (@($reg.machine_list | Where-Object name -eq 'Snapmaker U1 (0.2 nozzle)').Count -eq 0) '0.2 not selected'
    Assert (!(Test-Path -LiteralPath (Join-Path $profiles 'Snapmaker/machine/Snapmaker U1 (0.8 nozzle).json'))) '0.8 file not installed'
    Assert ((Get-InstalledSizes $profiles) -join ',' -eq '0.4,0.6') 'model offers selected sizes only'
    Assert (@($reg.machine_model_list | Where-Object name -eq 'Snapmaker U1 - 0.6 mm').Count -eq 1) 'selected size has independent model'
    Assert (@($reg.machine_model_list | Where-Object name -eq 'Snapmaker U1 - 0.2 mm').Count -eq 0) 'unselected model not registered'
    $variant=Join-Path $profiles 'Snapmaker/machine/Snapmaker U1 (0.6 nozzle).json'
    $old=Read-Json $variant;$old.printer_model='Snapmaker U1';$old | Add-Member -NotePropertyName custom_test -NotePropertyValue 'preserve';Write-Json $variant $old
    Assert (Test-ProfileRepair $profiles) 'previous grouped profile flagged for repair'
    Set-Profiles $root $profiles @('0.6') $ledger
    Assert (!(Test-ProfileRepair $profiles)) 'grouped profile repaired'
    Assert ((Read-Json $variant).custom_test -eq 'preserve') 'repair keeps custom fields'
    Copy-Item -LiteralPath (Join-Path $root 'Snapmaker/machine/Snapmaker U1 (0.6 nozzle).json') -Destination $variant -Force
    $custom=Join-Path $profiles 'Snapmaker/process/0.20 Standard @Snapmaker U1.json'
    $d=Read-Json $custom;$d | Add-Member -NotePropertyName enable_support -NotePropertyValue '0' -Force;Write-Json $custom $d;$hash=Get-Hash $custom
    Set-Profiles $root $profiles @('0.2') $ledger
    Assert ((Get-Hash $custom) -eq $hash) 'custom base settings retained'
    Assert (((Get-InstalledSizes $profiles) -join ',') -eq '0.2,0.4,0.6') 'unchecked existing size retained'
    $before=Get-Hash (Join-Path $profiles 'Snapmaker.json')
    Set-Profiles $root $profiles @('0.2') $ledger
    Assert ((Get-Hash (Join-Path $profiles 'Snapmaker.json')) -eq $before) 'repeat install idempotent'
    $back=New-Backup @($profiles,(Join-Path $temp 'absent')) (Join-Path $temp 'backups')
    Remove-Profiles $root $profiles @('0.6') -Ledger $ledger
    Assert (!(Test-Path -LiteralPath (Join-Path $profiles 'Snapmaker/machine/Snapmaker U1 (0.6 nozzle).json'))) 'selected size removed'
    Assert ((Get-Hash $custom) -eq $hash) 'custom base retained after removal'
    New-Item -ItemType Directory -Path (Join-Path $temp 'absent')|Out-Null
    Restore-Backup $back
    Assert ((Get-Hash (Join-Path $profiles 'Snapmaker.json')) -eq $before) 'backup restores registry'
    Assert (!(Test-Path -LiteralPath (Join-Path $temp 'absent'))) 'rollback removes newly created target'
    $bambu=Join-Path $temp 'Bambu';New-Item -ItemType Directory -Path $bambu | Out-Null
    Assert ((Get-BridgeState $root $bambu).action -eq 'Install') 'fresh bridge install detected'
    foreach($f in $m.bridge){$dest=Join-Safe (Join-Path $bambu 'bridge') $f.destination;New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force|Out-Null;Copy-Item -LiteralPath (Join-Safe $root $f.path) -Destination $dest}
    foreach($dep in (Read-Json (Join-Path $bambu 'bridge/package.json')).dependencies.PSObject.Properties.Name){
        $dp=Join-Path $bambu ('bridge/node_modules/'+$dep)
        New-Item -ItemType Directory -Path $dp -Force|Out-Null
        [IO.File]::WriteAllText((Join-Path $dp 'package.json'),'{}')
    }
    Remove-Item -LiteralPath (Join-Path $bambu 'bridge/setup-watchdog.ps1')
    Assert ((Get-BridgeState $root $bambu).action -eq 'Keep') 'current bridge kept without new watchdog'
    $server=Join-Path $bambu 'bridge/server.js';$raw=Get-Content -LiteralPath $server -Raw
    foreach($v in @('5.48.0-u1.1','5.48.0-u1.2','5.48.0-u1.4-test.5','5.48.0')){[IO.File]::WriteAllText($server,$raw.Replace('5.48.0-u1.4-test.7',$v));Assert ((Get-BridgeState $root $bambu).action -eq 'Upgrade') "upgrade $v"}
    [IO.File]::WriteAllText($server,$raw.Replace('5.48.0-u1.4-test.7','5.48.0-u1.9'));Assert ((Get-BridgeState $root $bambu).action -eq 'Keep') 'newer bridge not downgraded'
    [IO.File]::WriteAllText($server,$raw+"`n// local edit");Assert ((Get-BridgeState $root $bambu).action -eq 'Upgrade') 'edited current bridge replacement disclosed'
    $bad=$false;try{Join-Safe $profiles '../escape'}catch{$bad=$true};Assert $bad 'path traversal rejected'
    Remove-Profiles $root $profiles @() -All -Ledger $ledger
    Assert ((Get-Hash $custom) -eq $hash) 'uninstall preserves edited base'
    Assert (Test-Path -LiteralPath (Join-Path $profiles 'Snapmaker/process/fdm_process_U1_0.20.json')) 'uninstall preserves inherited parent'
    $clean=Join-Path $temp 'clean';Set-Profiles $root $clean @('0.2','0.6','0.8') $ledger
    $all=Read-Json (Join-Path $clean 'Snapmaker.json')
    Assert (((Get-InstalledSizes $clean) -join ',') -eq '0.2,0.4,0.6,0.8') 'all four installed sizes tracked'
    foreach($size in @('0.2','0.4','0.6','0.8')){
        $name="Snapmaker U1 ($size nozzle)"
        $entry=@($all.machine_list | Where-Object name -eq $name)
        Assert ($entry.Count -eq 1) "unique registered machine $name"
        $machine=Read-Json (Join-Path $clean "Snapmaker/machine/$name.json")
        Assert (($machine.nozzle_diameter -join ",") -eq $size) "matching nozzle diameter $name"
        $model=@($all.machine_model_list | Where-Object name -eq $machine.printer_model)
        Assert ($model.Count -eq 1) "matching model registry $name"
        $profile=Join-Path $clean ('Snapmaker/process/'+$machine.default_print_profile+'.json')
        Assert (Test-Path -LiteralPath $profile) "matching default process $name"
    }
    Assert (!@($all.machine_model_list | Where-Object name -eq 'Snapmaker U1').Count) 'no duplicate legacy tile'
    $basePath=Join-Path $clean 'Snapmaker/machine/Snapmaker U1 (0.4 nozzle).json'
    $base=Read-Json $basePath;$base.printer_model='Snapmaker U1';$base | Add-Member -NotePropertyName custom_note -NotePropertyValue 'keep';Write-Json $basePath $base
    Assert (@(Get-ProfileRepairSizes $clean) -contains '0.4') 'legacy 0.4 flagged for repair'
    Set-Profiles $root $clean @('0.2','0.6','0.8') $ledger
    $base=Read-Json $basePath
    Assert ($base.printer_model -eq 'Snapmaker U1 - 0.4 mm') '0.4 model migrated'
    Assert ($base.custom_note -eq 'keep') '0.4 custom settings preserved'
    $base.PSObject.Properties.Remove('custom_note');Write-Json $basePath $base
    Remove-Profiles $root $clean @() -All -Ledger $ledger
    Assert (!(Test-Path -LiteralPath (Join-Path $clean 'Snapmaker.json'))) 'clean uninstall removes vendor registry'
    Write-Output "PASS: $checks engine checks (real temporary files; no Windows services changed)."
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
