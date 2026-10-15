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
@{session='replacement-session';peer='host';token='replacement-token'}|ConvertTo-Json|Set-Content (Join-Path $Root 'connection.json')
$rejected=$false
try{Write-Frame $frame}catch{if($_.Exception.Message-notlike'*Mailbox replaced*'){throw};$rejected=$true}
if(-not$rejected-or(Test-Path (Join-Path $Root 'in-0002.txt'))-or(Test-Path (Join-Path $Root 'in-0002.txt.tmp'))){throw 'Stale bridge wrote into a replacement mailbox'}
'Bridge filesystem contract passed: valid frame committed, replaced mailbox refused before any write. No sockets or game input.'
