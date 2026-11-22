# Additive profile-only preview. Does not stop or modify the bridge.
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$backup = $null
$changed = $false
function Write-Json($Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), (New-Object Text.UTF8Encoding($false)))
}
try {
    if (Get-Process -Name 'bambu-studio','BambuStudio' -ErrorAction SilentlyContinue) { throw 'Close Bambu Studio before adding profiles.' }
    $candidates = @('BambuStudio','BambuStudioBeta' | ForEach-Object { Join-Path $env:APPDATA $_ } | Where-Object { Test-Path (Join-Path $_ 'system\Snapmaker.json') })
    if ($candidates.Count -eq 0) { throw 'No existing Snapmaker profile installation found. Install the full bridge package first.' }
    if ($candidates.Count -eq 1) { $config = $candidates[0] }
    else {
        for ($i=0; $i -lt $candidates.Count; $i++) { Write-Host ("{0}: {1}" -f ($i+1), $candidates[$i]) }
        $choice = 0
        if (-not [int]::TryParse((Read-Host 'Choose the Bambu installation to update'), [ref]$choice) -or $choice -lt 1 -or $choice -gt $candidates.Count) { throw 'No valid installation selected.' }
        $config = $candidates[$choice-1]
    }
    $system = Join-Path $config 'system'
    $vendor = Join-Path $system 'Snapmaker'
    $registryPath = Join-Path $system 'Snapmaker.json'
    $modelPath = Join-Path $vendor 'machine\Snapmaker U1.json'
    $registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $model = Get-Content -LiteralPath $modelPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'provenance.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($entry in $plan.profiles) {
        $relative = $entry.kind + '/' + $entry.name + '.json'
        $source = Join-Path (Join-Path $root 'Snapmaker') $relative
        $payload = Get-Content -LiteralPath $source -Raw -Encoding UTF8 | ConvertFrom-Json
        $parent = Join-Path (Join-Path $vendor $entry.kind) ($payload.inherits + '.json')
        if (-not (Test-Path -LiteralPath $parent)) { throw ('Required base preset missing: ' + $payload.inherits) }
        $target = Join-Path $vendor $relative
        if ((Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $source).Hash) { throw ('An edited preview preset already exists: ' + $entry.name + '. Save it under a new name first.') }
    }
    $backup = Join-Path $config ('nozzle-profile-backups\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Copy-Item -LiteralPath $vendor -Destination (Join-Path $backup 'Snapmaker') -Recurse
    Copy-Item -LiteralPath $registryPath -Destination (Join-Path $backup 'Snapmaker.json')
    $changed = $true
    foreach ($entry in $plan.profiles) {
        $relative = $entry.kind + '/' + $entry.name + '.json'
        Copy-Item -LiteralPath (Join-Path (Join-Path $root 'Snapmaker') $relative) -Destination (Join-Path $vendor $relative) -Force
        $property = $entry.kind + '_list'
        if (-not (@($registry.$property | Where-Object { $_.name -eq $entry.name }).Count)) {
            $registry.$property = @($registry.$property) + [pscustomobject]@{ name=$entry.name; sub_path=$relative }
        }
    }
    $model.nozzle_diameter = '0.2;0.4;0.6;0.8'
    Write-Json $modelPath $model
    Write-Json $registryPath $registry
    $changed = $false
    Write-Host 'SUCCESS: Nozzle preview profiles added. Reopen Bambu Studio and enable the nozzle sizes in printer selection.' -ForegroundColor Green
    Write-Host 'The existing 0.4 profile and bridge were not replaced. New sizes require slicing and print validation.'
    Write-Host "Backup: $backup"
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($changed -and $backup) {
        try {
            Remove-Item -LiteralPath $vendor -Recurse -Force
            Copy-Item -LiteralPath (Join-Path $backup 'Snapmaker') -Destination $vendor -Recurse
            Copy-Item -LiteralPath (Join-Path $backup 'Snapmaker.json') -Destination $registryPath -Force
            Write-Host 'Original profiles restored.'
        } catch { Write-Host "Restore the Snapmaker folder and Snapmaker.json from $backup into $system" -ForegroundColor Red }
    }
    exit 1
}
