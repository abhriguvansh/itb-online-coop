# Restricted alpha startup only. No installation, save restoration or input automation.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:Repo=Split-Path -Parent $PSScriptRoot
$script:Game='C:\ITBCoopProbe\GameVerified'
$script:Wire='C:\ITBCoopProbe\Wire'
function Get-CoopSourceIdentity {
    $files=[Collections.Generic.List[string]]::new();$files.Add('package.json')
    foreach($dir in @('tools','mod/scripts','native')){
        foreach($file in Get-ChildItem -LiteralPath (Join-Path $script:Repo $dir) -File){
            if($file.Name -cmatch '\.(cjs|ps1|psm1|lua|c|h)$'){$files.Add($dir+'/'+$file.Name)}
        }
    }
    $sorted=$files.ToArray();[Array]::Sort($sorted,[StringComparer]::Ordinal)
    $text=[Text.StringBuilder]::new()
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
        foreach($file in $sorted){
            # Git checks out PS1 with CRLF; equivalent reviewed checkouts must agree.
            $source=[Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes((Join-Path $script:Repo $file))).Replace("`r`n","`n")
            $fileHash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($source)))).Replace('-','').ToLowerInvariant()
            [void]$text.Append($file+[char]0+$fileHash+"`n")
        }
        $hash=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text.ToString())))).Replace('-','').ToLowerInvariant()
    } finally {$sha.Dispose()}
    return $hash
}
function Test-CoopPrivateAddress([string]$Address){
    $ip=$null
    if(-not[Net.IPAddress]::TryParse($Address,[ref]$ip)-or$ip.AddressFamily-ne[Net.Sockets.AddressFamily]::InterNetwork-or$ip.ToString()-cne$Address){return $false}
    $n=$ip.GetAddressBytes()
    return $Address-eq'127.0.0.1'-or$n[0]-eq10-or($n[0]-eq172-and$n[1]-ge16-and$n[1]-le31)-or($n[0]-eq192-and$n[1]-eq168)-or($n[0]-eq100-and$n[1]-ge64-and$n[1]-le127)
}
function Read-CoopConnection([string]$Path){
    if((Get-Item -LiteralPath $Path).Length-gt8192){throw 'Connection file is too large.'}
    $c=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
    $version=(Get-Content -LiteralPath (Join-Path $script:Repo 'package.json') -Raw|ConvertFrom-Json).version
    if($c.launch.protocol-cne'itb-coop-launch-v1'-or$c.launch.probe-cne$version-or$c.launch.sourceSha256-cne(Get-CoopSourceIdentity)){throw 'Source/protocol mismatch. Both players need the same reviewed checkout.'}
    # PowerShell 7 JSON converts a Z timestamp to DateTime; PS 5 keeps a string.
    # Preserve DateTime.Kind instead of reparsing a culture-formatted UTC value as local.
    $expiry=if($c.launch.expiresAt-is[DateTime]){[DateTimeOffset]$c.launch.expiresAt}else{[DateTimeOffset]::Parse($c.launch.expiresAt,[Globalization.CultureInfo]::InvariantCulture)}
    if($expiry-le[DateTimeOffset]::UtcNow-or$expiry-gt[DateTimeOffset]::UtcNow.AddMinutes(11)){throw 'Connection file expired or invalid; start a new session, never reuse an old session.'}
    if($c.session-cnotmatch'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'-or$c.peer-cnotmatch'^(host|guest)$'-or$c.token-cnotmatch'^[a-f0-9]{48}$'-or-not(Test-CoopPrivateAddress $c.host)-or($c.port-isnot[int]-and$c.port-isnot[long])-or$c.port-lt1-or$c.port-gt65535){throw 'Invalid private connection identity or endpoint.'}
    foreach($flag in @('interactive','phaseRun','repeatedTurns','deployment','fullMission','liveBootstrap','nativeTransport','primarySetup')){
        if($c.$flag-isnot[bool]-or-not$c.$flag){throw 'Only the interactive primary-choice full-mission mode is supported.'}
    }
    if($c.terminalCheckpoint){throw 'Checkpoint tactical drivers are not supported by this launcher.'}
    return $c
}
function Assert-CoopPlainPath([string]$Path){
    $item=Get-Item -LiteralPath $Path -Force
    while($null-ne$item){
        if($item.Attributes-band[IO.FileAttributes]::ReparsePoint){throw 'Linked game/save/session paths are unsupported.'}
        $item=if($item-is[IO.FileInfo]){$item.Directory}else{$item.Parent}
    }
}
function Get-CoopSave([string]$SaveRoot){
    Assert-CoopPlainPath $SaveRoot
    $settings=Get-Content -LiteralPath (Join-Path $SaveRoot 'settings.lua') -Raw
    $matches=[regex]::Matches($settings,'\["last_profile"\]\s*=\s*"([A-Za-z0-9_-]+)"')
    if($matches.Count-ne1){throw 'Select the disposable ITB_Coop_Probe profile normally before launching.'}
    $key=$matches[0].Groups[1].Value
    $profile=Join-Path $SaveRoot ('profile_'+$key);Assert-CoopPlainPath $profile
    $text=Get-Content -LiteralPath (Join-Path $profile 'profile.lua') -Raw
    if(([regex]::Matches($text,'\["visible_name"\]\s*=\s*"ITB_Coop_Probe"')).Count-ne1){throw 'The selected profile is not ITB_Coop_Probe. Normal saves are refused.'}
    $hashes=@{}
    foreach($name in @('profile.lua','saveData.lua','undoSave.lua')){
        $file=Join-Path $profile $name;Assert-CoopPlainPath $file
        $hashes[$name]=(Get-FileHash -LiteralPath $file).Hash
    }
    return [pscustomobject]@{Path=$profile;Key=$key;Hashes=$hashes}
}
function Assert-CoopGame {
    if(Get-Process -Name Breach -ErrorAction SilentlyContinue){throw 'Close Into the Breach before starting a new session.'}
    Assert-CoopPlainPath $script:Game
    if((Get-FileHash -LiteralPath (Join-Path $script:Game 'Breach.exe')).Hash-ne'31FE352655982398FB3EE8B0BBE80EFD5D65E3A9AA11E3DC39D0364354493FE9'){throw 'Unsupported game executable. The alpha requires the pinned Windows 1.2.93 build.'}
    $loader=Join-Path $script:Game 'scripts\mod_loader\modapi\init.lua';Assert-CoopPlainPath $loader
    if((Get-Content -LiteralPath $loader -Raw)-notmatch'self\.version\s*=\s*"2\.9\.6"'){throw 'Expected mod loader 2.9.6.'}
    $root=Join-Path $script:Game 'mods\aman_itb_coop_probe';Assert-CoopPlainPath $root
    $marker=Get-Content -LiteralPath (Join-Path $root '.itb-coop-probe.json') -Raw|ConvertFrom-Json
    $version=(Get-Content -LiteralPath (Join-Path $script:Repo 'package.json') -Raw|ConvertFrom-Json).version
    if($marker.Id-ne'aman_itb_coop_probe'-or$marker.Version-ne$version-or$marker.Files.Count-ne30){throw 'Installed probe is incompatible or incomplete. Use the reviewed installer with the game closed.'}
    $expected=@{}
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $script:Repo 'mod\scripts') -Filter '*.lua' -File){$expected['scripts\'+$file.Name]=(Get-FileHash -LiteralPath $file.FullName).Hash}
    $expected['itb_input.dll']='37DFB3C5BD7293BCAE57B9B37BA99977813165A890C9FB1E9D5B74441675CF3B'
    $expected['itb_initial_choices.dll']='D1F0A909C90F21E648784EA0146A649125F29E360B6AEE268E080C6839742E3C'
    $expected['itb_transport.dll']='D17D6540B0EA247C52EC41246282B81A47B1ED763180033CCBF7BCE50C3E9A20'
    $seen=@{}
    foreach($record in $marker.Files){
        $name=$record.RelativePath
        if(-not$expected.ContainsKey($name)-or$seen.ContainsKey($name)){throw 'Unexpected/duplicate owned payload path.'}
        $file=Join-Path $root $name;Assert-CoopPlainPath $file
        if($record.Sha256-ne$expected[$name]-or(Get-FileHash -LiteralPath $file).Hash-ne$expected[$name]){throw "Payload mismatch: $name"}
        $seen[$name]=$true
    }
    if(@(Get-ChildItem -LiteralPath $root -File -Recurse -Force).Count-ne31){throw 'Unrecognized extra files in owned probe folder.'}
}
function Backup-CoopSave($Save,[string]$Destination){
    if(Test-Path -LiteralPath $Destination){throw 'Backup already exists; refusing to replace it.'}
    # Reject linked children before copying; only the selected disposable profile is read.
    foreach($item in Get-ChildItem -LiteralPath $Save.Path -Recurse -Force){Assert-CoopPlainPath $item.FullName}
    Copy-Item -LiteralPath $Save.Path -Destination $Destination -Recurse
    foreach($name in $Save.Hashes.Keys){
        if((Get-FileHash -LiteralPath (Join-Path $Destination $name)).Hash-ne$Save.Hashes[$name]-or(Get-FileHash -LiteralPath (Join-Path $Save.Path $name)).Hash-ne$Save.Hashes[$name]){throw 'Save changed during backup; game will not launch.'}
    }
    $Save.Hashes|ConvertTo-Json|Set-Content -LiteralPath ($Destination+'-hashes.json') -Encoding UTF8
}
function Start-CoopGame([string]$ConnectionFile,[string]$SaveRoot,[switch]$CheckOnly,[switch]$SoftwareRendering){
    $c=Read-CoopConnection $ConnectionFile
    Assert-CoopGame
    $save=Get-CoopSave $SaveRoot
    if($CheckOnly){Write-Output 'Compatible interactive runtime and disposable profile verified; nothing changed.';return}
    $sessionRoot=Join-Path 'C:\ITBCoopProbe\Sessions' $c.session
    if(Test-Path -LiteralPath $sessionRoot){throw 'This session was already prepared; do not retry. Start a fresh session after preserving evidence.'}
    $parent=Split-Path -Parent $sessionRoot
    if(Test-Path -LiteralPath $parent){Assert-CoopPlainPath $parent}else{Assert-CoopPlainPath 'C:\ITBCoopProbe'}
    New-Item -ItemType Directory -Path $sessionRoot|Out-Null;Assert-CoopPlainPath $sessionRoot
    Backup-CoopSave $save (Join-Path $sessionRoot 'profile-before')
    if(Test-Path -LiteralPath $script:Wire){
        Assert-CoopPlainPath $script:Wire
        # Both resolved paths are explicitly confined to the fixed disposable root.
        $old=[IO.Path]::GetFullPath($script:Wire);$target=[IO.Path]::GetFullPath((Join-Path $sessionRoot 'wire-before'))
        if($old-cne'C:\ITBCoopProbe\Wire'-or-not$target.StartsWith('C:\ITBCoopProbe\Sessions\',[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe mailbox preservation target.'}
        Move-Item -LiteralPath $old -Destination $target
    }
    New-Item -ItemType Directory -Path $script:Wire|Out-Null
    $utf8=[Text.UTF8Encoding]::new($false)
    [IO.File]::WriteAllText((Join-Path $script:Wire 'native-connection.txt'),(@('itb-transport-v2',$c.session,$c.peer,$c.host,[string]$c.port,$c.token,'')-join"`n"),$utf8)
    [IO.File]::WriteAllText((Join-Path $script:Wire 'session.txt'),$c.session+"`n"+$c.peer+"`nfull-mission`n",$utf8)
    $previousLog=Join-Path $script:Game 'modloader.log'
    if(Test-Path -LiteralPath $previousLog){Assert-CoopPlainPath $previousLog;Move-Item -LiteralPath $previousLog -Destination (Join-Path $sessionRoot 'modloader-before.log')}
    $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=Join-Path $script:Game 'Breach.exe';$psi.WorkingDirectory=$script:Game;$psi.UseShellExecute=$false
    foreach($name in @($psi.EnvironmentVariables.Keys|Where-Object{$_-like'ITB_COOP_*'})){$psi.EnvironmentVariables.Remove($name)}
    foreach($name in @('NATIVE_TRANSPORT','CHOOSE_MECHS','LIVE_BOOTSTRAP','FRAME_TRACE','RESET_TRACE')){$psi.EnvironmentVariables['ITB_COOP_'+$name]='1'}
    $psi.EnvironmentVariables['ITB_COOP_INITIAL_CHOICES']=if($c.peer-eq'host'){'capture'}else{'replay'}
    $psi.EnvironmentVariables['ITB_COOP_WIRE_DIR']='C:/ITBCoopProbe/Wire'
    if($SoftwareRendering){$psi.EnvironmentVariables['LP_NUM_THREADS']='1';$psi.EnvironmentVariables['GALLIUM_DRIVER']='llvmpipe';$psi.EnvironmentVariables['LIBGL_ALWAYS_SOFTWARE']='true'}
    $game=[Diagnostics.Process]::Start($psi)
    Write-Host "Protected $($c.peer) game started. Backup: $sessionRoot"
    Write-Host 'Host: Continue into Chronology Hall. Guest: stay at the main menu until this console reports READY TO ENTER.'
    Write-Host 'At deployment, use Interactive co-op phase, choose different primary mechs, agree the first shared controller, and approve locally in both games.'
    Write-Host 'Unsupported encounters, time-pod collection/rewards and campaign continuation are excluded. Stop on uncertainty; never retry a possibly committed action.'
    $ready=$false;$agreed=$false;$failed=$false
    while(-not$game.WaitForExit(1000)){
        # Hints only: these messages grant no command authority and never click anything.
        $log=Join-Path $script:Game 'modloader.log'
        if(-not(Test-Path -LiteralPath $log)){continue}
        $stream=$null
        try {
            $stream=[IO.File]::Open($log,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
            $length=[int][Math]::Min(65536,$stream.Length);[void]$stream.Seek(-$length,[IO.SeekOrigin]::End)
            $bytes=New-Object byte[] $length;$count=$stream.Read($bytes,0,$length);$tail=[Text.Encoding]::UTF8.GetString($bytes,0,$count)
            if(-not$ready-and$c.peer-eq'guest'-and$tail.Contains('"event":"initial_choice_live_installed"')){$ready=$true;Write-Host 'READY TO ENTER: Guest may Continue into Chronology Hall now.'}
            if(-not$agreed-and$tail.Contains('"event":"initial_choice_live_agreed"')){$agreed=$true;Write-Host 'Both initializations agreed. Protected deployment can now be armed locally.'}
            if(-not$failed-and($tail.Contains('"event":"initial_choice_bootstrap_failed"')-or$tail.Contains('"event":"native_transport_failed"'))){$failed=$true;Write-Host 'Runtime reported a startup/connection failure. Preserve the log and exit safely; do not retry this session.'}
        }
        catch [IO.IOException] { } # A transient log read cannot authorize an action.
        finally {if($stream){$stream.Dispose()}}
    }
}
Export-ModuleMember -Function Get-CoopSourceIdentity,Test-CoopPrivateAddress,Read-CoopConnection,Assert-CoopGame,Get-CoopSave,Backup-CoopSave,Start-CoopGame
