param([string]$OriginalSid,[int]$InitialMode=0)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
trap { [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Setup stopped') | Out-Null; exit 1 }
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if($OriginalSid -and $OriginalSid -ne $identity.User.Value){[Windows.Forms.MessageBox]::Show('Run setup using the same Windows account that uses Bambu Studio. Different administrator credentials would target the wrong settings.','Account mismatch') | Out-Null;exit 1}
if(!(New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    try{Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -OriginalSid "'+$identity.User.Value+'" -InitialMode '+$InitialMode)}catch{[Windows.Forms.MessageBox]::Show('Setup was cancelled. No changes were made.') | Out-Null};exit
}
$root=Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'Engine.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Windows.psm1') -Force -DisableNameChecking
try{$manifest=Get-Package $root}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Package error')|Out-Null;exit 1}
$script:program=@("$env:ProgramFiles\Bambu Studio","$env:ProgramFiles\Bambu Studio Beta","${env:ProgramFiles(x86)}\Bambu Studio") | Where-Object {Test-Path -LiteralPath (Join-Path $_ 'resources/profiles')} | Select-Object -First 1
if(!$script:program){$script:program="$env:ProgramFiles\Bambu Studio"}
function Get-ApplicationSettingsFolder($ProgramDir) {
    $version=''
    foreach($name in @('bambu-studio.exe','bambustudio.exe')){
        $exe=Join-Path $ProgramDir $name
        if(Test-Path -LiteralPath $exe){$version=[string](Get-Item -LiteralPath $exe).VersionInfo.ProductVersion;break}
    }
    Get-SettingsFolder $ProgramDir $env:APPDATA $version
}
$script:config=Get-ApplicationSettingsFolder $script:program
$script:mode=$InitialMode;$script:busy=$false;$script:state=$null;$script:installed=@();$script:log='';$script:checking=$false;$script:repair=$false;$script:repairSizes=@()
function New-Window($Title,$Width,$Height){
    $f=New-Object Windows.Forms.Form;$f.Text=$Title;$f.Font=New-Object Drawing.Font('Segoe UI',10)
    $f.AutoScaleDimensions=New-Object Drawing.SizeF(96,96);$f.AutoScaleMode='Dpi'
    $f.ClientSize=New-Object Drawing.Size($Width,$Height);$f.StartPosition='CenterParent';$f.FormBorderStyle='FixedDialog';$f.MaximizeBox=$false
    $f
}
function Add-Label($Parent,$Text,$X,$Y,$Width,$Height){
    $c=New-Object Windows.Forms.Label;$c.UseMnemonic=$false;$c.Text=$Text;$c.SetBounds($X,$Y,$Width,$Height);$Parent.Controls.Add($c);$c
}
function Add-Button($Parent,$Text,$X,$Y,$Width){
    $c=New-Object Windows.Forms.Button;$c.Text=$Text;$c.SetBounds($X,$Y,$Width,36);$Parent.Controls.Add($c);$c
}
function Add-Link($Parent,$Text,$X,$Y,$Width){
    $c=New-Object Windows.Forms.LinkLabel;$c.Text=$Text;$c.SetBounds($X,$Y,$Width,26);$Parent.Controls.Add($c);$c
}
$form=New-Window ('Snapmaker U1 Setup - '+$manifest.version) 680 470
$form.StartPosition='CenterScreen';$form.BackColor=[Drawing.Color]::White
$title=Add-Label $form 'Snapmaker U1' 24 18 440 34
$title.Font=New-Object Drawing.Font('Segoe UI',18,[Drawing.FontStyle]::Bold)
$target=Add-Label $form '' 456 26 200 24;$target.TextAlign='MiddleRight';$target.ForeColor=[Drawing.Color]::DimGray
$null=Add-Label $form 'Installation' 24 75 95 26
$action=New-Object Windows.Forms.ComboBox;$action.DropDownStyle='DropDownList';$action.SetBounds(126,72,530,28);$form.Controls.Add($action)
[void]$action.Items.AddRange(@('Install / Update','Remove nozzle profiles','Uninstall add-on'));$action.SelectedIndex=$script:mode
$null=Add-Label $form 'Program folder' 24 117 100 26
$path=New-Object Windows.Forms.TextBox;$path.Text=$script:program;$path.SetBounds(126,114,440,28);$form.Controls.Add($path)
$browse=Add-Button $form 'Browse' 574 111 82;$browse.Height=32
$null=Add-Label $form 'Settings folder' 24 159 100 26
$cfg=New-Object Windows.Forms.ComboBox;$cfg.DropDownStyle='DropDownList';$cfg.SetBounds(126,156,530,28);$form.Controls.Add($cfg)
foreach($n in @('BambuStudio','BambuStudioBeta')){[void]$cfg.Items.Add((Join-Path $env:APPDATA $n))};$cfg.SelectedItem=$script:config
$heading=Add-Label $form 'Nozzle profiles' 24 205 632 26
$heading.Font=New-Object Drawing.Font('Segoe UI',11,[Drawing.FontStyle]::Bold)
$checks=@{};$badges=@{};$cards=@{};$x=24
foreach($size in @('0.2','0.4','0.6','0.8')){
    $card=New-Object Windows.Forms.Panel;$card.SetBounds($x,239,149,70);$card.BackColor=[Drawing.Color]::FromArgb(245,247,249);$form.Controls.Add($card);$cards[$size]=$card
    $c=New-Object Windows.Forms.CheckBox;$c.Text="$size mm";$c.SetBounds(12,10,125,27);$c.Font=New-Object Drawing.Font('Segoe UI',11);$card.Controls.Add($c);$checks[$size]=$c
    $badges[$size]=Add-Label $card '' 32 39 112 22;$badges[$size].Font=New-Object Drawing.Font('Segoe UI',9);$badges[$size].ForeColor=[Drawing.Color]::DimGray
    $x+=161
}
$uninstallNote=Add-Label $form "Removes the bridge and unmodified nozzle profiles.`r`nYour custom presets, connection settings and backups stay." 24 218 632 90
$uninstallNote.Visible=$false
$status=Add-Label $form 'Checking your installation...' 24 328 632 36
$status.ForeColor=[Drawing.Color]::FromArgb(35,105,65);$status.AutoEllipsis=$true
$hint=Add-Label $form 'Settings are preserved. Changes are backed up.' 24 366 632 26
$hint.Font=New-Object Drawing.Font('Segoe UI',9);$hint.ForeColor=[Drawing.Color]::DimGray
$progress=New-Object Windows.Forms.ProgressBar;$progress.SetBounds(24,399,632,3);$progress.Style='Marquee';$progress.Visible=$false;$form.Controls.Add($progress)
$details=Add-Link $form 'Details' 24 425 80
$apply=Add-Button $form 'Please wait...' 456 415 200;$apply.Enabled=$false
$apply.FlatStyle='Flat';$apply.FlatAppearance.BorderSize=0;$apply.BackColor=[Drawing.Color]::FromArgb(24,115,74);$apply.ForeColor=[Drawing.Color]::White
function Update-Choices {
    if($script:checking -or $script:busy){return}
    $heading.Visible=($script:mode -ne 2)
    $uninstallNote.Visible=($script:mode -eq 2)
    foreach($card in $cards.Values){$card.Visible=($script:mode -ne 2)}
    foreach($s in $checks.Keys){
        $checks[$s].Visible=($script:mode -ne 2);$badges[$s].Visible=($script:mode -ne 2)
        if($script:mode -eq 0){
            $present=$script:installed -contains $s
            $checks[$s].Enabled=(!$present -and $s -ne '0.4')
            if($present -or $s -eq '0.4'){$checks[$s].Checked=$true}
            $badges[$s].Text=if($script:repairSizes -contains $s){'Needs repair'}elseif($present){'Installed'}elseif($s -eq '0.4'){'Included'}else{''}
        }else{
            $checks[$s].Enabled=($script:installed -contains $s -and $s -ne '0.4')
            if(!$checks[$s].Enabled){$checks[$s].Checked=$false}
            $badges[$s].Text=if($s -eq '0.4'){'Kept as base'}elseif($script:installed -contains $s){'Installed'}else{'Not installed'}
        }
    }
    $selected=@($checks.Keys | Where-Object {$checks[$_].Checked -and $script:installed -notcontains $_})
    if(!$script:state){$apply.Enabled=$false;$apply.Text='Check settings';return}
    $apply.Enabled=$true
    if($script:mode -eq 0){
        $title.Text='Snapmaker U1';$heading.Text='Nozzle profiles to add'
        $hint.Text='Settings are preserved. Changes are backed up.'
        if($script:state.action -eq 'Keep'){$apply.Text='Add selected profiles';if(!$selected.Count){$apply.Text='Already installed';$apply.Enabled=$false;if($script:repair){$apply.Text='Repair nozzle choices';$apply.Enabled=$true}}}
        elseif($script:state.action -eq 'Install'){$apply.Text='Install'}else{$apply.Text=if($script:repair){'Update and repair'}else{'Update bridge'}}
    }elseif($script:mode -eq 1){
        $title.Text='Remove nozzle profiles';$heading.Text='Choose nozzle sizes to remove'
        $hint.Text='The bridge and 0.4 mm base stay installed.';$apply.Text='Remove selected'
        $apply.Enabled=(@($checks.Keys | Where-Object {$checks[$_].Checked -and $_ -ne '0.4'}).Count -gt 0)
    }else{
        $title.Text='Uninstall Snapmaker add-on';$apply.Text='Uninstall'
        $hint.Text='You will confirm before anything is removed.'
    }
}
function Refresh-Plan {
    $script:checking=$true;$apply.Enabled=$false;$progress.Visible=$true
    $status.ForeColor=[Drawing.Color]::DimGray;$status.Text='Checking your installation...'
    $target.Text=if($script:config -like '*BambuStudioBeta'){'Bambu Studio Beta'}else{'Bambu Studio'}
    $form.Refresh()
    try{
        if(!(Test-Path -LiteralPath (Join-Path $script:program 'resources/profiles'))){throw 'Bambu Studio was not found. Choose its program folder above.'}
        $script:state=Get-WindowsBridgeState $root $script:program
        $script:installed=@(Get-InstalledSizes (Join-Path $script:config 'system'))
        $script:repairSizes=@(Get-ProfileRepairSizes (Join-Path $script:config 'system'))+@(Get-ProfileRepairSizes (Join-Path $script:program 'resources/profiles'));$script:repair=($script:repairSizes.Count -gt 0)
        $status.ForeColor=[Drawing.Color]::FromArgb(35,105,65)
        $status.Text=if($script:mode -eq 2){'Your settings and backups will be kept.'}elseif($script:mode -eq 1){'Only the selected profiles will be removed.'}elseif($script:state.action -eq 'Keep'){"Bridge $($script:state.version) is up to date."}elseif($script:state.action -eq 'Install'){'Bridge will be installed automatically.'}else{"Bridge $($script:state.version) -> $($manifest.bridgeVersion)."}
        $script:log += "Checked $(Get-Date -Format 'HH:mm:ss'): $($script:state.detail)`r`n"
    }catch{$script:state=$null;$status.ForeColor=[Drawing.Color]::Firebrick;$status.Text=$_.Exception.Message;$script:log+=$_.Exception.Message+"`r`n"}
    finally{$progress.Visible=$false;$script:checking=$false;Update-Choices}
}
foreach($c in $checks.Values){$c.Add_CheckedChanged({Update-Choices})}
function Apply-Selection {
    if($script:busy -or $script:checking){return}
    $changed=($script:mode -ne $action.SelectedIndex -or $script:config -ne [string]$cfg.SelectedItem -or $script:program -ne $path.Text.Trim())
    if(!$changed){return}
    $programChanged=($script:program -ne $path.Text.Trim())
    $script:program=$path.Text.Trim();$script:mode=$action.SelectedIndex
    $script:checking=$true
    if($programChanged){$cfg.SelectedItem=Get-ApplicationSettingsFolder $script:program}
    $script:config=[string]$cfg.SelectedItem
    $script:checking=$false
    $script:checking=$true;foreach($c in $checks.Values){$c.Checked=$false};$script:checking=$false
    Refresh-Plan
}
$browse.Add_Click({
    $picker=New-Object Windows.Forms.FolderBrowserDialog;$picker.SelectedPath=$path.Text
    if($picker.ShowDialog($form) -eq 'OK'){$path.Text=$picker.SelectedPath;Apply-Selection};$picker.Dispose()
})
$path.Add_Leave({Apply-Selection})
$path.Add_KeyDown({param($sender,$e)if($e.KeyCode -eq 'Enter'){$e.SuppressKeyPress=$true;Apply-Selection}})
$cfg.Add_SelectedIndexChanged({Apply-Selection})
$action.Add_SelectedIndexChanged({Apply-Selection})
$details.Add_LinkClicked({
    $d=New-Window 'Setup details' 680 420
    $box=New-Object Windows.Forms.TextBox;$box.Multiline=$true;$box.ReadOnly=$true;$box.ScrollBars='Both';$box.WordWrap=$false;$box.SetBounds(16,16,648,345)
    $box.Text="Program: $script:program`r`nSettings: $script:config`r`n`r`n"+$script:log;$d.Controls.Add($box)
    $close=Add-Button $d 'Close' 554 371 110;$close.DialogResult='OK';[void]$d.ShowDialog($form);$d.Dispose()
})
$logger={param($message)$script:log += [string]$message+"`r`n";$status.Text=[string]$message;$form.Refresh();[Windows.Forms.Application]::DoEvents()}
$form.Add_FormClosing({param($sender,$e)if($script:busy){$e.Cancel=$true}})
$apply.Add_Click({
    if($script:busy){return}
    Refresh-Plan
    if(!$apply.Enabled){return}
    $expected=Get-ApplicationSettingsFolder $script:program
    if($script:config -ne $expected){
        if([Windows.Forms.MessageBox]::Show("The selected settings folder differs from the detected application edition.`r`nExpected: $expected`r`nSelected: $script:config`r`n`r`nUse the selected folder anyway?",'Check settings target','YesNo','Warning') -ne 'Yes'){return}
    }
    $running=@(Get-Process -Name 'bambustudio','bambu-studio' -ErrorAction SilentlyContinue)
    if($running.Count){
        if([Windows.Forms.MessageBox]::Show("Bambu Studio is running. Close it to continue?`r`nSave any unsaved work when Bambu asks.",'Close Bambu Studio','OKCancel','Question') -ne 'OK'){return}
        $script:busy=$true;$apply.Enabled=$false
        try {
        foreach($process in $running){if(!$process.HasExited){[void]$process.CloseMainWindow()}}
        $deadline=(Get-Date).AddSeconds(60)
        while((Get-Process -Name 'bambustudio','bambu-studio' -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline){[Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 250}
        } finally {$script:busy=$false;$apply.Enabled=$true}
        if(Get-Process -Name 'bambustudio','bambu-studio' -ErrorAction SilentlyContinue){[Windows.Forms.MessageBox]::Show('Bambu is still running. Save your work, close it, then click Update again. No processes were forcibly stopped.','Waiting for Bambu') | Out-Null;return}
    }
    $sizes=@($checks.Keys | Where-Object {$checks[$_].Checked})
    $bridgeChange=($script:mode -eq 2 -or ($script:mode -eq 0 -and $script:state.action -ne 'Keep'))
    if($bridgeChange){
        if([Windows.Forms.MessageBox]::Show("This will stop or restart the bridge.`r`nHas your printer finished printing?",'Printer must be idle','YesNo','Question') -ne 'Yes'){return}
    }
    if($script:mode -ne 0){
        $question=if($script:mode -eq 2){'Uninstall the add-on? Custom settings and backups will be kept.'}else{'Remove these nozzle profiles: '+(($sizes | Where-Object {$_ -ne '0.4'}) -join ', ')+' mm?'}
        if([Windows.Forms.MessageBox]::Show($question,'Confirm removal','OKCancel','Warning') -ne 'OK'){return}
    }elseif($script:state.action -eq 'Upgrade'){
        if([Windows.Forms.MessageBox]::Show($script:state.detail+"`r`n`r`nContinue with a backup?",'Update bridge','OKCancel','Information') -ne 'OK'){return}
    }
    $script:busy=$true;$progress.Visible=$true;$apply.Enabled=$false;foreach($field in @($path,$cfg,$action,$browse)){$field.Enabled=$false};$details.Enabled=$false
    foreach($c in $checks.Values){$c.Enabled=$false}
    $success=$false;$failureMessage=''
    try{
        Invoke-Setup $root $script:program $script:config $sizes @('Install','Remove','Uninstall')[$script:mode] $logger | Out-Null
        $success=$true
    }catch{$failureMessage=$_.Exception.Message;$script:log+='ERROR: '+$_.Exception.Message+"`r`n";$status.Text=$_.Exception.Message}
    finally{
        $script:busy=$false;$progress.Visible=$false;foreach($field in @($path,$cfg,$action,$browse)){$field.Enabled=$true};$details.Enabled=$true
        if($success){Refresh-Plan;$status.ForeColor=[Drawing.Color]::FromArgb(35,105,65);$status.Text='Done. Reopen Bambu Studio.';if($script:mode -eq 0){$hint.Text='Enable the added models in Bambu Studio > Printer Selection.'}}
        else{Update-Choices;$status.ForeColor=[Drawing.Color]::Firebrick;$status.Text='Setup stopped. Open Details for backup information.';[Windows.Forms.MessageBox]::Show($failureMessage,'Setup stopped','OK','Error') | Out-Null}
    }
    if($success -and $script:mode -eq 0){
        if([Windows.Forms.MessageBox]::Show('Setup completed. Open Bambu Studio now?','Setup complete','YesNo','Question') -eq 'Yes'){
            try{
                $exe=@('bambu-studio.exe','bambustudio.exe') | ForEach-Object {Join-Path $script:program $_} | Where-Object {Test-Path -LiteralPath $_} | Select-Object -First 1
                if(!$exe){throw 'Bambu executable was not found. Open Bambu Studio normally.'}
                # Ask the desktop shell to launch as the signed-in user, not elevated setup.
                $shell=New-Object -ComObject Shell.Application
                $shell.ShellExecute($exe,'',$script:program,'open',1)
            }catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'Open Bambu Studio') | Out-Null}
        }
    }
})
# Show the window before detection so slow checks have visible feedback.
$initialCheck=New-Object Windows.Forms.Timer;$initialCheck.Interval=150
$initialCheck.Add_Tick({$initialCheck.Stop();Refresh-Plan})
$form.Add_Shown({$initialCheck.Start()})
[void]$form.ShowDialog()
$initialCheck.Dispose();$form.Dispose()
