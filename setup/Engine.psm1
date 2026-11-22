Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
# Select by the chosen application, never by leftover profile folders.
function Get-SettingsFolder($ProgramDir,$AppData,[string]$ProductVersion='') {
    $leaf=($ProgramDir.TrimEnd('\','/') -split '[\\/]')[-1]
    $beta=($leaf -match '(?i)\bbeta\b' -or $ProductVersion -match '(?i)\bbeta\b')
    Join-Path $AppData $(if($beta){'BambuStudioBeta'}else{'BambuStudio'})
}
function Read-Json($Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Write-Json($Path,$Value) {
    $parent = Split-Path $Path -Parent
    if (!(Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path,($Value | ConvertTo-Json -Depth 100),(New-Object Text.UTF8Encoding($false)))
}
function Get-Hash($Path) { if (Test-Path -LiteralPath $Path -PathType Leaf) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() } else { '' } }
function Join-Safe($Root,$Relative) {
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Relative))
    if (!$full.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid relative path in package.' }
    $full
}
function Get-Package($Root) {
    $m = Read-Json (Join-Path $Root 'setup/payload.json')
    foreach ($f in $m.files) {
        if ((Get-Hash (Join-Safe $Root $f.path)) -ne $f.sha256) { throw "Package damaged or incomplete: $($f.path). Extract the whole ZIP again." }
    }
    $m
}
function Get-BridgeState($Root,$BambuDir) {
    $dst = Join-Path $BambuDir 'bridge'; $server = Join-Path $dst 'server.js'
    if (!(Test-Path -LiteralPath $dst)) { return [pscustomobject]@{action='Install';version='Not installed';detail='Install bridge and startup task'} }
    if (!(Test-Path -LiteralPath $server) -or !(Test-Path -LiteralPath (Join-Path $dst 'package.json'))) { throw "Incomplete or unrecognized bridge directory: $dst. No files changed." }
    $pkg=Read-Json (Join-Path $dst 'package.json');$raw=Get-Content -LiteralPath $server -Raw
    if ($pkg.name -ne 'bambustudio-bridge' -or $raw -notmatch 'BRIDGE_VERSION\s*=\s*["'']([^"'']+)') { throw "The bridge directory is not a recognized BambuStudio bridge: $dst" }
    $version=$Matches[1];$m=Read-Json (Join-Path $Root 'setup/payload.json');$different=@()
    foreach ($f in $m.bridge) { if ($f.destination -notmatch '(\.js|\.html|\.css|\.png)$') { continue }; if ((Get-Hash (Join-Safe $dst $f.destination)) -ne $f.sha256) { $different += $f.destination } }
    $depsOk=$true;foreach($dep in $pkg.dependencies.PSObject.Properties.Name){if(!(Test-Path (Join-Path $dst ('node_modules/'+$dep+'/package.json')))){$depsOk=$false}}
    if (!$different.Count -and $depsOk) { return [pscustomobject]@{action='Keep';version=$version;detail='Current bridge files verified; leave bridge running'} }
    # Never downgrade an installed newer bridge. For older/modified builds, show the replacement in the plan and retain a full backup.
    $incoming=[regex]::Match($m.bridgeVersion,'^(\d+\.\d+\.\d+)(?:-u1\.(\d+))?')
    $installed=[regex]::Match($version,'^(\d+\.\d+\.\d+)(?:-u1\.(\d+))?')
    if (!$installed.Success) { throw "Cannot compare bridge version '$version'. No files changed." }
    if (([version]$installed.Groups[1].Value -gt [version]$incoming.Groups[1].Value) -or (([version]$installed.Groups[1].Value -eq [version]$incoming.Groups[1].Value) -and ([int]('0'+$installed.Groups[2].Value) -gt [int]('0'+$incoming.Groups[2].Value)))) {
        return [pscustomobject]@{action='Keep';version=$version;detail='Newer bridge retained; compatibility with this preview is unverified'}
    }
    [pscustomobject]@{action='Upgrade';version=$version;detail="Back up and replace bridge with $($m.bridgeVersion); includes any locally edited bridge code"}
}
function Get-InstalledSizes($ProfilesDir) {
    foreach($size in @('0.2','0.4','0.6','0.8')){if(Test-Path -LiteralPath (Join-Path $ProfilesDir "Snapmaker/machine/Snapmaker U1 ($size nozzle).json")){$size}}
}
function Get-ProfileRepairSizes($ProfilesDir) {
    $rp=Join-Path $ProfilesDir 'Snapmaker.json';if(!(Test-Path -LiteralPath $rp)){return};$reg=Read-Json $rp
    foreach($size in @(Get-InstalledSizes $ProfilesDir)){
        $name="Snapmaker U1 - $size mm";$machine=Read-Json (Join-Path $ProfilesDir "Snapmaker/machine/Snapmaker U1 ($size nozzle).json")
        if($machine.printer_model -ne $name -or !@($reg.machine_model_list | Where-Object name -eq $name).Count -or !(Test-Path -LiteralPath (Join-Path $ProfilesDir "Snapmaker/machine/$name.json"))){$size}
    }
}
function Test-ProfileRepair($ProfilesDir) { return (@(Get-ProfileRepairSizes $ProfilesDir).Count -gt 0) }
function Sync-Models($Root,$ProfilesDir,$Registry,$Ledger) {
    $source=Read-Json (Join-Path $Root 'Snapmaker.json')
    foreach($size in @('0.2','0.4','0.6','0.8')){
        $name="Snapmaker U1 - $size mm";$mp=Join-Path $ProfilesDir "Snapmaker/machine/Snapmaker U1 ($size nozzle).json"
        $entry=@($source.machine_model_list | Where-Object name -eq $name)[0];$dest=Join-Safe (Join-Path $ProfilesDir 'Snapmaker') $entry.sub_path
        if(@($Registry.machine_list | Where-Object name -eq "Snapmaker U1 ($size nozzle)").Count){
            $machine=Read-Json $mp
            # Migrate only display/model identity; preserve the user's settings.
            if($machine.printer_model -eq 'Snapmaker U1'){$machine.printer_model=$name;Write-Json $mp $machine}
            if(!(Test-Path -LiteralPath $dest)){Copy-Item -LiteralPath (Join-Path (Join-Path $Root 'Snapmaker') $entry.sub_path) -Destination $dest;$Ledger.files += [pscustomobject]@{path=$dest;sha256=(Get-Hash $dest)}}
            if(!@($Registry.machine_model_list | Where-Object name -eq $name).Count){$Registry.machine_model_list=@($Registry.machine_model_list)+$entry}
        }else{
            $Registry.machine_model_list=@($Registry.machine_model_list | Where-Object name -ne $name)
            if((Get-Hash $dest) -eq (Get-Hash (Join-Path (Join-Path $Root 'Snapmaker') $entry.sub_path))){if(Test-Path -LiteralPath $dest){Remove-Item -LiteralPath $dest -Force}}
        }
    }
    # The legacy descriptor stays on disk for inheritance compatibility, but is not a duplicate selection tile.
    $Registry.machine_model_list=@($Registry.machine_model_list | Where-Object name -ne 'Snapmaker U1')
}
function New-Backup($Paths,$BackupRoot) {
    $dest=Join-Path $BackupRoot ((Get-Date -Format 'yyyyMMdd-HHmmss-fff')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    $entries=@();$i=0
    foreach ($path in ($Paths | Select-Object -Unique)) {
        $exists=Test-Path -LiteralPath $path;$saved=Join-Path $dest ([string]$i)
        if ($exists) { Copy-Item -LiteralPath $path -Destination $saved -Recurse -Force }
        $entries += [pscustomobject]@{path=$path;existed=$exists;saved=$saved};$i++
    }
    Write-Json (Join-Path $dest 'restore.json') $entries
    $dest
}
function Restore-Backup($Backup) {
    foreach ($e in @(Read-Json (Join-Path $Backup 'restore.json'))) {
        if (Test-Path -LiteralPath $e.path) { Remove-Item -LiteralPath $e.path -Recurse -Force }
        if ($e.existed) { New-Item -ItemType Directory -Path (Split-Path $e.path -Parent) -Force | Out-Null; Copy-Item -LiteralPath $e.saved -Destination $e.path -Recurse -Force }
    }
}
function Set-Profiles($Root,$ProfilesDir,[string[]]$Sizes,$Ledger) {
    $all=Read-Json (Join-Path $Root 'Snapmaker.json');$new=Read-Json (Join-Path $Root 'tools/nozzle-profiles/provenance.json')
    $extra=@{};foreach ($e in $new.profiles) { $extra[$e.kind+'/'+$e.name+'.json']=$true }
    $registryPath=Join-Path $ProfilesDir 'Snapmaker.json'
    if (Test-Path -LiteralPath $registryPath) { $registry=Read-Json $registryPath } else { $registry=Read-Json (Join-Path $Root 'Snapmaker.json');foreach($kind in @('machine','process','filament')){$registry.($kind+'_list')=@()};$registry.machine_model_list=@($registry.machine_model_list | Where-Object name -eq 'Snapmaker U1') }
    $selected=@('0.4')+@($Sizes) # 0.4 is the shared inheritance base, always retained.
    foreach ($kind in @('machine','process','filament')) {
        $prop=$kind+'_list'
        foreach ($entry in $all.$prop) {
            if ($extra.ContainsKey($entry.sub_path)) {
                $preset=Read-Json (Join-Path (Join-Path $Root 'Snapmaker') $entry.sub_path)
                $size=if($kind -eq 'machine'){$preset.printer_variant}else{[regex]::Match($preset.compatible_printers[0],'\((0\.[268]) nozzle\)').Groups[1].Value}
                if ($selected -notcontains $size) { continue }
            }
            $target=Join-Safe (Join-Path $ProfilesDir 'Snapmaker') $entry.sub_path
            # Preserve pre-existing files, including custom edits. Only repair missing files.
            if (!(Test-Path -LiteralPath $target)) {
                New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
                Copy-Item -LiteralPath (Join-Path (Join-Path $Root 'Snapmaker') $entry.sub_path) -Destination $target
                if($entry.name -eq 'Snapmaker U1 (0.4 nozzle)'){$base=Read-Json $target;$base.default_filament_profile=@('Generic PLA @U1');Write-Json $target $base}
                $Ledger.files += [pscustomobject]@{path=$target;sha256=(Get-Hash $target)}
            }
            if (!@($registry.$prop | Where-Object name -eq $entry.name).Count) { $registry.$prop=@($registry.$prop)+$entry }
        }
    }
    # Copy the model and assets missing on fresh installs. Never overwrite custom bed images or model data.
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $Root 'Snapmaker') -Recurse -File)) {
        $rel=$f.FullName.Substring((Join-Path $Root 'Snapmaker').Length+1)
        if($f.Name -match '^Snapmaker U1 - 0\.[2468] mm\.json$'){continue}
        if ($rel -match '(^|[\\/])(filament|process)[\\/]' -or $extra.ContainsKey($rel.Replace('\','/'))) {continue}
        $target=Join-Safe (Join-Path $ProfilesDir 'Snapmaker') $rel
        if (!(Test-Path -LiteralPath $target)) {
            New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $f.FullName -Destination $target
            $Ledger.files += [pscustomobject]@{path=$target;sha256=(Get-Hash $target)}
        }
    }
    $modelPath=Join-Path $ProfilesDir 'Snapmaker/machine/Snapmaker U1.json';$model=Read-Json $modelPath
    $installed=@(Get-InstalledSizes $ProfilesDir)
    # The package model lists every size; advertise only machine presets actually registered at this target.
    $actual=@('0.4');foreach($size in @('0.2','0.6','0.8')){if(@($registry.machine_list | Where-Object name -eq "Snapmaker U1 ($size nozzle)").Count){$actual+=$size}}
    $model.nozzle_diameter='0.4';Write-Json $modelPath $model
    Sync-Models $Root $ProfilesDir $registry $Ledger
    Write-Json $registryPath $registry
    foreach($e in $Ledger.files){if($e.path -eq $modelPath){$e.sha256=Get-Hash $modelPath}}
}
function Remove-Profiles($Root,$ProfilesDir,[string[]]$Sizes,[switch]$All,$Ledger) {
    $rp=Join-Path $ProfilesDir 'Snapmaker.json';if(!(Test-Path -LiteralPath $rp)){return}
    $reg=Read-Json $rp;$package=Read-Json (Join-Path $Root 'setup/payload.json');$known=@{}
    foreach($f in $package.files){if($f.path.StartsWith('Snapmaker/')){$known[$f.path.Substring(10)]=$f.sha256}}
    $removed=@();$preserved=@()
    foreach($kind in @('machine','process','filament')){
        $prop=$kind+'_list';$keep=@()
        foreach($e in $reg.$prop){
            $target=Join-Safe (Join-Path $ProfilesDir 'Snapmaker') $e.sub_path
            $match=$All.IsPresent
            if(!$match){foreach($s in $Sizes){if($s -ne '0.4' -and $e.name -match ([regex]::Escape($s)+' nozzle')){$match=$true}}}
            if($match -and $known.ContainsKey($e.sub_path)){
                $hash=Get-Hash $target
                if(!$hash -or ($hash -eq $known[$e.sub_path] -or @($Ledger.files | Where-Object { $_.path -eq $target -and $_.sha256 -eq $hash }).Count -gt 0)){if($hash){Remove-Item -LiteralPath $target -Force};$removed+=$e.name;continue}
                $preserved+=$e.name
            }
            $keep+=$e
        }
        $reg.$prop=$keep
    }
    # Preserve ancestors needed by any surviving edited preset. Restore missing parents from the pre-removal package.
    $changed=$true
    while($changed){$changed=$false;foreach($kind in @('machine','process','filament')){
        $prop=$kind+'_list'
        foreach($e in @($reg.$prop)){
            $path=Join-Safe (Join-Path $ProfilesDir 'Snapmaker') $e.sub_path
            if(!(Test-Path -LiteralPath $path)){continue};$d=Read-Json $path
            if($d.PSObject.Properties['inherits'] -and $d.inherits){
                $parent="$kind/$($d.inherits).json";$dest=Join-Safe (Join-Path $ProfilesDir 'Snapmaker') $parent
                if(!(Test-Path -LiteralPath $dest) -and (Test-Path -LiteralPath (Join-Path (Join-Path $Root 'Snapmaker') $parent))){Copy-Item -LiteralPath (Join-Path (Join-Path $Root 'Snapmaker') $parent) -Destination $dest;$reg.$prop+= [pscustomobject]@{name=$d.inherits;sub_path=$parent};$changed=$true}
            }
        }
    }}
    $modelPath=Join-Path $ProfilesDir 'Snapmaker/machine/Snapmaker U1.json'
    if(Test-Path -LiteralPath $modelPath){$model=Read-Json $modelPath;$actual=@();foreach($s in @('0.2','0.4','0.6','0.8')){if(@($reg.machine_list | Where-Object name -eq "Snapmaker U1 ($s nozzle)").Count){$actual+=$s}};$model.nozzle_diameter='0.4';Write-Json $modelPath $model}
    Sync-Models $Root $ProfilesDir $reg $Ledger
    if($All -and !$reg.machine_list.Count -and !$reg.process_list.Count -and !$reg.filament_list.Count){
        # Only remove remaining known assets; leave unrelated/custom files in place.
        foreach($rel in $known.Keys){$p=Join-Safe (Join-Path $ProfilesDir 'Snapmaker') $rel;if((Get-Hash $p) -eq $known[$rel]){Remove-Item -LiteralPath $p -Force}}
        if(Test-Path -LiteralPath $modelPath){Remove-Item -LiteralPath $modelPath -Force}
        Remove-Item -LiteralPath $rp -Force
    } else {Write-Json $rp $reg}
    if($preserved.Count){Write-Output "Preserved $($preserved.Count) edited profiles in $ProfilesDir."}
}
Export-ModuleMember -Function *
