[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConnectionFile,
    [string]$SaveRoot=(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Into The Breach'),
    [switch]$CheckOnly,
    [switch]$SoftwareRendering
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Coop-Startup.psm1') -Force
try {Start-CoopGame -ConnectionFile $ConnectionFile -SaveRoot $SaveRoot -CheckOnly:$CheckOnly -SoftwareRendering:$SoftwareRendering}
catch {Write-Error ('Co-op startup stopped: '+$_.Exception.Message);exit 1}
