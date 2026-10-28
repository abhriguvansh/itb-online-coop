[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PrivateAddress,
    [string]$SessionDirectory,
    [string]$SaveRoot=(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Into The Breach'),
    [switch]$CoordinatorOnly,
    [switch]$SoftwareRendering
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Coop-Startup.psm1') -Force
$coordinator=$null
try {
    if(-not(Test-CoopPrivateAddress $PrivateAddress)){throw 'Use one explicit private IPv4 interface. Public/wildcard listeners are refused.'}
    if(-not$CoordinatorOnly){Assert-CoopGame;$null=Get-CoopSave $SaveRoot}
    $node=$null
    foreach($candidate in Get-Command node -CommandType Application -ErrorAction Stop){
        $version=& $candidate.Source --version
        if($LASTEXITCODE-eq0-and$version-match'^v(\d+)\.'-and[int]$Matches[1]-ge22){$node=$candidate.Source;break}
    }
    if(-not$node){throw 'Host requires Node.js 22 or newer on PATH. No software was installed.'}
    if(-not$SessionDirectory){$SessionDirectory=Join-Path $env:LOCALAPPDATA ('ITBCoop\Sessions\'+[guid]::NewGuid().ToString())}
    $SessionDirectory=[IO.Path]::GetFullPath($SessionDirectory)
    if(Test-Path -LiteralPath $SessionDirectory){throw 'Choose a new private session directory; previous evidence will not be overwritten.'}
    if($SessionDirectory.Contains('"')-or$PSScriptRoot.Contains('"')){throw 'Quoted paths are unsupported.'}
    New-Item -ItemType Directory -Path $SessionDirectory|Out-Null
    $runtime=Join-Path $SessionDirectory 'runtime'
    $source=Join-Path $PSScriptRoot 'phase-coordinator.cjs'
    $arguments=@(('"'+$source+'"'),('"'+$runtime+'"'),'--native-primary-choice','--private-address',$PrivateAddress)
    $coordinator=Start-Process -FilePath $node -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $SessionDirectory 'coordinator.out.log') -RedirectStandardError (Join-Path $SessionDirectory 'coordinator.err.log')
    $hostConfig=Join-Path $runtime 'host.json'
    $deadline=[DateTime]::UtcNow.AddSeconds(10)
    while(-not(Test-Path -LiteralPath $hostConfig)){
        if($coordinator.HasExited){throw 'Coordinator failed to start. See its private error log; no game was launched.'}
        if([DateTime]::UtcNow-gt$deadline){throw 'Coordinator startup timed out; no game was launched.'}
        Start-Sleep -Milliseconds 100
    }
    $null=Read-CoopConnection $hostConfig
    Write-Host ('Share only this private guest connection file over your secure channel: '+(Join-Path $runtime 'guest.json'))
    Write-Host 'The coordinator is unencrypted. Use an already established secure private network for remote play. No firewall/security changes were made.'
    if($CoordinatorOnly){Write-Host ('Engineering mode: host connection file '+$hostConfig);$coordinator.WaitForExit()}
    else {Start-CoopGame -ConnectionFile $hostConfig -SaveRoot $SaveRoot -SoftwareRendering:$SoftwareRendering}
    if(-not$coordinator.HasExited){throw 'Game closed before verified session completion. Evidence is preserved; do not retry this session.'}
    if($coordinator.ExitCode-ne0){throw 'Coordinator stopped without verified completion. See its private logs; do not retry this session.'}
    Write-Host 'Coordinator acknowledged matching committed mission results from both runtimes.'
}
finally {if($coordinator-and-not$coordinator.HasExited){$coordinator.Kill();$coordinator.WaitForExit()}}
