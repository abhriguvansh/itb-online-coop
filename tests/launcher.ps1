$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repo 'tools\Coop-Startup.psm1') -Force
$root=Join-Path $repo ('.local\tests\launcher-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root|Out-Null
function Assert($Condition,$Message){if(-not$Condition){throw $Message}}
function Refuses([scriptblock]$Action){$failed=$false;try{&$Action|Out-Null}catch{$failed=$true};Assert $failed 'Expected safe startup refusal.'}
foreach($address in @('127.0.0.1','10.0.2.2','172.16.0.1','192.168.4.1','100.64.0.1')){Assert (Test-CoopPrivateAddress $address) 'Private IPv4 refused'}
foreach($address in @('0.0.0.0','8.8.8.8','127.1.2.3','10.01.2.2','::1','localhost','172.32.0.1','100.128.0.1','10.0.0.256')){Assert (-not(Test-CoopPrivateAddress $address)) 'Unsafe/noncanonical target allowed'}
$js=& node -e "process.stdout.write(require('./tools/launcher-compatibility.cjs').compatibility().sourceSha256)"
Assert ($js-ceq(Get-CoopSourceIdentity)) 'Node/PowerShell source compatibility disagreement'
$mirror=Join-Path $root 'source mirror';New-Item -ItemType Directory -Path $mirror|Out-Null
foreach($name in @('package.json','tools','mod','native')){Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $mirror -Recurse}
$mirroredHost=Join-Path $mirror 'tools\Host-Coop.ps1'
[IO.File]::WriteAllText($mirroredHost,([IO.File]::ReadAllText($mirroredHost)).Replace("`r`n","`n").Replace("`n","`r`n"),[Text.UTF8Encoding]::new($false))
$mirroredIdentity=& node -e "process.stdout.write(require('./tools/launcher-compatibility.cjs').compatibility(process.argv[1]).sourceSha256)" $mirror
Assert ($mirroredIdentity-ceq$js) 'Git checkout line endings caused a false peer incompatibility'
$config=Join-Path $root 'guest.json'
$base=@{session='00000000-0000-4000-8000-000000000000';peer='guest';token=('a'*48);host='10.0.2.2';port=12345;terminalCheckpoint=$false;launch=@{protocol='itb-coop-launch-v1';probe='0.33.0';sourceSha256=$js;expiresAt=[DateTimeOffset]::UtcNow.AddMinutes(9).ToString('o')}}
foreach($flag in @('interactive','phaseRun','repeatedTurns','deployment','fullMission','liveBootstrap','nativeTransport','primarySetup')){$base[$flag]=$true}
function Write-Config($Value){$Value|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $config -Encoding UTF8}
Write-Config $base
Assert ((Read-CoopConnection $config).peer-eq'guest') 'Valid configuration refused'
$base.launch.expiresAt=[DateTimeOffset]::UtcNow.AddMinutes(9).UtcDateTime.ToString('o');Write-Config $base
Assert ((Read-CoopConnection $config).peer-eq'guest') 'UTC Z configuration refused or interpreted as local time'
foreach($entry in @(@('host','8.8.8.8'),@('peer','other'),@('port',0),@('port',1.5),@('token','short'),@('session','../other'),@('primarySetup',$false),@('fullMission','true'),@('terminalCheckpoint',$true))){
    $bad=$base.Clone();$bad[$entry[0]]=$entry[1];Write-Config $bad;Refuses {Read-CoopConnection $config}
}
foreach($entry in @(@('sourceSha256',('0'*64)),@('expiresAt',[DateTimeOffset]::UtcNow.AddSeconds(-1).ToString('o')),@('protocol','old'))){
    $bad=$base.Clone();$bad.launch=$base.launch.Clone();$bad.launch[$entry[0]]=$entry[1];Write-Config $bad;Refuses {Read-CoopConnection $config}
}
$saveRoot=Join-Path $root 'saves';$profile=Join-Path $saveRoot 'profile_Alpha'
New-Item -ItemType Directory -Path $profile|Out-Null
Set-Content -LiteralPath (Join-Path $saveRoot 'settings.lua') -Value 'Settings = {["last_profile"] = "Alpha",}'
Set-Content -LiteralPath (Join-Path $profile 'profile.lua') -Value 'Profile = {["visible_name"] = "ITB_Coop_Probe",}'
Set-Content -LiteralPath (Join-Path $profile 'saveData.lua') -Value 'inert private fixture'
Set-Content -LiteralPath (Join-Path $profile 'undoSave.lua') -Value 'inert private fixture'
$save=Get-CoopSave $saveRoot
Assert ($save.Key-eq'Alpha') 'Display name incorrectly treated as folder key'
$backup=Join-Path $root 'backup';Backup-CoopSave $save $backup
Assert ((Get-FileHash (Join-Path $backup 'saveData.lua')).Hash-eq$save.Hashes['saveData.lua']) 'Backup not verified'
Refuses {Backup-CoopSave $save $backup}
Set-Content -LiteralPath (Join-Path $profile 'profile.lua') -Value 'Profile = {["visible_name"] = "Aman",}'
Refuses {Get-CoopSave $saveRoot}
Set-Content -LiteralPath (Join-Path $saveRoot 'settings.lua') -Value 'Settings = {["last_profile"] = "",}'
Refuses {Get-CoopSave $saveRoot}
Write-Output 'Launcher contracts passed: private configuration, exact source identity, expired/driver refusal, selected-profile isolation and verified non-overwriting backup. Inert files only; no game or native executable was launched.'

# Exercise the actual host script and coordinator, not a duplicate of their setup code.
$session=Join-Path $root 'host session with spaces'
$engine=(Get-Process -Id $PID).Path
$process=Start-Process -FilePath $engine -ArgumentList @('-NoProfile','-File',('"'+(Join-Path $repo 'tools\Host-Coop.ps1')+'"'),'-PrivateAddress','127.0.0.1','-CoordinatorOnly','-SessionDirectory',('"'+$session+'"')) -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'host.out.log') -RedirectStandardError (Join-Path $root 'host.err.log')
$hostFile=Join-Path $session 'runtime\host.json';$deadline=[DateTime]::UtcNow.AddSeconds(15)
while(-not(Test-Path -LiteralPath $hostFile)-and-not$process.HasExited-and[DateTime]::UtcNow-lt$deadline){Start-Sleep -Milliseconds 100}
if(-not(Test-Path -LiteralPath $hostFile)){
    $null=$process.WaitForExit(15000)
    throw 'Actual host startup failed; inspect private fixture logs.'
}
$connection=Read-CoopConnection $hostFile
$guest=Read-CoopConnection (Join-Path $session 'runtime\guest.json')
Assert ($connection.peer-eq'host'-and$guest.peer-eq'guest'-and$connection.token-ne$guest.token) 'Role credentials not separated'
$client=[Net.Sockets.TcpClient]::new()
try {
    $client.Connect($connection.host,[int]$connection.port)
    $bytes=[Text.Encoding]::UTF8.GetBytes("invalid`n");$client.GetStream().Write($bytes,0,$bytes.Length)
} finally {$client.Dispose()}
Assert ($process.WaitForExit(10000)) 'Stopped coordinator did not retire the host launcher'
Assert ($process.ExitCode-ne0) 'Launcher falsely reported success after coordinator refusal'
$events=Get-Content -LiteralPath (Join-Path $session 'runtime\events.jsonl')|ForEach-Object{$_|ConvertFrom-Json}
Assert (@($events|Where-Object{$_.type-eq'dispatch'}).Count-eq0) 'Host startup test dispatched gameplay'
Write-Output 'Actual host launcher/private loopback passed: paths with spaces, compatible role files, invalid-frame refusal, zero gameplay and clear unsuccessful-session exit. No game was launched.'
