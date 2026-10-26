$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$Root=Join-Path $repo ('.local\tests\mailbox-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Root|Out-Null
$config=[pscustomobject]@{session='fixture-session';peer='host';token='private-fixture-token'}
$config|ConvertTo-Json|Set-Content (Join-Path $Root 'connection.json')
$utf8=[Text.UTF8Encoding]::new($false);$incoming=1;$frameLimit=32
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'tools\Run-GuestPhaseBridge.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Bridge parse error'}
foreach($name in @('Assert-MailboxSession','Write-Frame')){
    $fn=$ast.Find({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-eq$name},$true)
    if(-not$fn){throw 'Required bridge function missing'}
    . ([scriptblock]::Create($fn.Extent.Text))
}
$frame=@{kind='PING';session=$config.session;peer='-';revision=0;phase='-';id='-';witness=''}
Write-Frame $frame
if(-not(Test-Path (Join-Path $Root 'in-0001.txt'))){throw 'Valid frame missing'}
$placement=@{kind='EXEC';session=$config.session;peer='host';revision=0;phase='deployment';id='move-host-1';witness='{}';move=@{actor='combat';kind='deploy';fromX=-1;fromY=-1;toX=1;toY=4}}
Write-Frame $placement
if((Get-Content (Join-Path $Root 'in-0002.txt') -Raw)-notmatch '\|deploycombat\|-1\|-1\|1\|4'){throw 'Deployment frame mismatch'}
$placement.move.kind='move';$failed=$false
try{Write-Frame $placement}catch{$failed=$true}
if(-not$failed-or(Test-Path (Join-Path $Root 'in-0003.txt'))){throw 'Normal movement accepted an off-board origin'}
$config|Add-Member liveBootstrap $true
$config.peer='guest';$config|ConvertTo-Json|Set-Content (Join-Path $Root 'connection.json')
Write-Frame @{kind='BOOTSTRAPCHOICES';session=$config.session;witness="ai-constructor|32768|42`n"}
if((Get-Content (Join-Path $Root 'bootstrap-offer.txt') -Raw)-ne($config.session+"`nai-constructor|32768|42`n")){throw 'Bootstrap delivery mismatch'}
if($incoming-ne3){throw 'Bootstrap consumed a gameplay frame number'}
$failed=$false;try{Write-Frame @{kind='BOOTSTRAPREADY';session='stale';witness=''}}catch{$failed=$true}
if(-not$failed-or(Test-Path (Join-Path $Root 'bootstrap-agreed.txt'))){throw 'Stale bootstrap delivered'}
@{session='replacement-session';peer='host';token='replacement-token'}|ConvertTo-Json|Set-Content (Join-Path $Root 'connection.json')
$rejected=$false
try{Write-Frame $frame}catch{if($_.Exception.Message-notlike'*Mailbox replaced*'){throw};$rejected=$true}
if(-not$rejected-or(Test-Path (Join-Path $Root 'in-0003.txt'))-or(Test-Path (Join-Path $Root 'in-0003.txt.tmp'))){throw 'Stale bridge wrote into a replacement mailbox'}
'Bridge filesystem contract passed: valid frame committed, replaced mailbox refused before any write. No sockets or game input.'
'Live bootstrap side-channel delivery preserves gameplay numbering and refuses stale sessions (filesystem fixture only).'
