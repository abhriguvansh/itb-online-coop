[CmdletBinding()]
param([string]$Root='C:\ITBCoopProbe\Wire')
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if([IO.Path]::GetFullPath($Root)-ne'C:\ITBCoopProbe\Wire'){throw 'Only the disposable guest mailbox is supported'}
if((Get-Item -LiteralPath $Root).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked mailbox refused'}
$config=Get-Content -LiteralPath (Join-Path $Root 'connection.json') -Raw | ConvertFrom-Json
if($config.host-ne'10.0.2.2' -or $config.peer-notin@('host','guest') -or $config.session-notmatch'^[a-f0-9-]{36}$' -or $config.token-notmatch'^[a-f0-9]{48}$' -or $config.port-lt1 -or $config.port-gt65535){throw 'Invalid private connection configuration'}
$utf8=[Text.UTF8Encoding]::new($false,$true);$incoming=1;$outgoing=1;$complete=$false
function Write-Frame($frame){
    if($script:incoming-gt1024){throw 'Incoming frame limit'}
    if($frame.session-ne$config.session -or $frame.kind-notin@('PING','STOP','PROPOSE','READY','CONSENT','EXEC','DONE','INPUT','PREPARE') -or $frame.peer-notin@('host','guest','-') -or $frame.revision-lt0 -or $frame.revision-gt4 -or $frame.phase-notmatch'^[\w.:-]{1,96}$' -or $frame.id-notmatch'^[\w.:-]{1,96}$' -or $frame.witness.Length-gt65536 -or $frame.witness-match'[\r\n]'){throw 'Invalid coordinator frame'}
    $header=@($frame.kind,$frame.session,$frame.peer,$frame.revision,$frame.phase,$frame.id)
    if($null-ne$frame.move){
        if($frame.kind-notin@('EXEC','PREPARE') -or $frame.move.actor-notin@('combat','cannon','artillery')){throw 'Invalid move payload'}
        foreach($key in @('fromX','fromY','toX','toY')){if($frame.move.$key-notmatch'^[0-7]$'){throw 'Invalid move coordinate'}}
        $header+=@($frame.move.actor,$frame.move.fromX,$frame.move.fromY,$frame.move.toX,$frame.move.toY)
    }
    $text=($header -join '|')+"`n"+$frame.witness
    $target=Join-Path $Root ('in-{0:d4}.txt'-f$script:incoming)
    [IO.File]::WriteAllText($target+'.tmp',$text,$utf8)
    [IO.File]::Move($target+'.tmp',$target);$script:incoming++
}
$client=[Net.Sockets.TcpClient]::new()
try{
    $waiting=[Diagnostics.Stopwatch]::StartNew()
    [IO.File]::WriteAllText((Join-Path $Root 'bridge-ready.txt'),$config.session,$utf8)
    while(-not(Test-Path -LiteralPath (Join-Path $Root 'out-0001.json'))){
        if($waiting.Elapsed.TotalSeconds-gt300){throw 'Game was not armed before startup deadline'}
        Start-Sleep -Milliseconds 100
    }
    $connecting=$client.BeginConnect($config.host,[int]$config.port,$null,$null)
    if(-not$connecting.AsyncWaitHandle.WaitOne(5000)){throw 'Connect timeout'}
    $client.EndConnect($connecting);$client.NoDelay=$true
    $stream=$client.GetStream();$stream.WriteTimeout=5000
    function Send-Message($message){
        $text=$message|ConvertTo-Json -Compress -Depth 30
        $bytes=$utf8.GetBytes($text+"`n");if($bytes.Length-gt140000){throw 'Outgoing frame limit'}
        $stream.Write($bytes,0,$bytes.Length)
    }
    Send-Message @{type='hello';session=$config.session;peer=$config.peer;token=$config.token}
    $buffer='';$bytes=[byte[]]::new(8192);$chars=[char[]]::new(8192);$decoder=$utf8.GetDecoder()
    $last=[Diagnostics.Stopwatch]::StartNew();$total=[Diagnostics.Stopwatch]::StartNew()
    while($total.Elapsed.TotalSeconds-lt610){
        if($client.Client.Poll(0,[Net.Sockets.SelectMode]::SelectRead)-and$client.Available-eq0){
            if($complete){Write-Output 'Guest phase bridge completed';exit 0};throw 'Coordinator disconnected'
        }
        if($stream.DataAvailable){
            $count=$stream.Read($bytes,0,$bytes.Length);if($count-eq0){throw 'Coordinator closed'}
            $length=$decoder.GetChars($bytes,0,$count,$chars,0)
            $buffer+=[string]::new($chars,0,$length);if($buffer.Length-gt140000){throw 'Incoming frame size'}
            while(($cut=$buffer.IndexOf("`n"))-ge0){
                $frame=$buffer.Substring(0,$cut)|ConvertFrom-Json;$buffer=$buffer.Substring($cut+1)
                Write-Frame $frame;$last.Restart()
                if($frame.kind-eq'PING'){Send-Message @{type='pong';session=$config.session}}
                if($frame.kind-eq'STOP'){throw 'Coordinator stopped the experiment'}
            }
        }
        if($last.Elapsed.TotalSeconds-gt10){throw 'Coordinator heartbeat expired'}
        if($outgoing-gt32){throw 'Outgoing message limit'}
        $file=Join-Path $Root ('out-{0:d4}.json'-f$outgoing)
        if(Test-Path -LiteralPath $file){
            if((Get-Item -LiteralPath $file).Length-gt140000){throw 'Game output size'}
            $message=Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
            if($message.session-ne$config.session -or $message.peer-ne$config.peer){throw 'Game identity mismatch'}
            Send-Message $message;$outgoing++
            if($message.type-eq'complete'){$complete=$true}
        }
        Start-Sleep -Milliseconds 50
    }
    throw 'Bridge experiment deadline'
}catch{
    $reason=$_.Exception.Message
    try{Write-Frame @{kind='STOP';session=$config.session;peer='-';revision=0;phase='-';id='-';witness=''}}catch{}
    [IO.File]::WriteAllText((Join-Path $Root 'bridge-failure.txt'),$reason,$utf8)
    Write-Error $reason
    exit 1
}finally{$client.Dispose()}
