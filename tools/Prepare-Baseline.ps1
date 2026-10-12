[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GamePath,
    [Parameter(Mandatory)][string]$LoaderArchive
)
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$gameRoot = (Resolve-Path -LiteralPath $GamePath).Path
$archivePath = (Resolve-Path -LiteralPath $LoaderArchive).Path
$pins = Get-Content -LiteralPath (Join-Path $repoPath 'dependencies.json') -Raw | ConvertFrom-Json
if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'Breach.exe') -PathType Leaf)) { throw 'Breach.exe missing.' }
if (Get-Process -Name Breach -ErrorAction SilentlyContinue) { throw 'Close the game before backing up.' }
if (Test-Path -LiteralPath (Join-Path $gameRoot 'scripts\mod_loader')) { throw 'Existing loader found. Review it before preparing a clean baseline.' }
if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pins.loader.sha256) {
    throw 'Loader archive checksum mismatch.'
}
$privateRoot = Join-Path $repoPath '.local'
$stageRoot = Join-Path $privateRoot 'stage\loader-2.9.6'
if (Test-Path -LiteralPath $stageRoot) { throw 'Staging already exists; refusing to replace it.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    foreach ($entry in $archive.Entries) {
        $destination = [IO.Path]::GetFullPath((Join-Path $stageRoot $entry.FullName))
        if (-not $destination.StartsWith($stageRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Unsafe archive path.'
        }
    }
} finally { $archive.Dispose() }
New-Item -ItemType Directory -Path $stageRoot | Out-Null
[IO.Compression.ZipFile]::ExtractToDirectory($archivePath, $stageRoot)

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupRoot = Join-Path $privateRoot ('backups\baseline-' + $stamp)
New-Item -ItemType Directory -Path (Join-Path $backupRoot 'game-files') | Out-Null
$saveRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games\Into The Breach'
if (Test-Path -LiteralPath $saveRoot) {
    if (Get-ChildItem -LiteralPath $saveRoot -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) {
        throw 'Save tree contains a link; inspect before backing up.'
    }
    Copy-Item -LiteralPath $saveRoot -Destination (Join-Path $backupRoot 'saves') -Recurse
}
$plan = @()
foreach ($source in Get-ChildItem -LiteralPath $stageRoot -File -Recurse) {
    $relative = $source.FullName.Substring($stageRoot.Length + 1)
    $target = Join-Path $gameRoot $relative
    $plan += [pscustomobject]@{ RelativePath=$relative; Exists=(Test-Path -LiteralPath $target); Sha256=(Get-FileHash -LiteralPath $source.FullName).Hash }
}
$affected = @($plan | Where-Object Exists | ForEach-Object RelativePath)
# The loader rewrites resource.dat on launch, beyond archive extraction.
$affected += @('resources\resource.dat', 'resources\resource.dat.bak')
$backupRecords = @()
foreach ($relative in ($affected | Select-Object -Unique)) {
    $source = Join-Path $gameRoot $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    $copy = Join-Path (Join-Path $backupRoot 'game-files') $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $copy
    $hash = (Get-FileHash -LiteralPath $source).Hash
    if ($hash -ne (Get-FileHash -LiteralPath $copy).Hash) { throw "Backup mismatch: $relative" }
    $backupRecords += [pscustomobject]@{ RelativePath=$relative; Sha256=$hash }
}
$saveRecords = @()
if (Test-Path -LiteralPath $saveRoot) {
    foreach ($source in Get-ChildItem -LiteralPath $saveRoot -File -Recurse) {
        $relative = $source.FullName.Substring($saveRoot.Length + 1)
        $copy = Join-Path (Join-Path $backupRoot 'saves') $relative
        $hash = (Get-FileHash -LiteralPath $source.FullName).Hash
        if ($hash -ne (Get-FileHash -LiteralPath $copy).Hash) { throw "Save backup mismatch: $relative" }
        $saveRecords += [pscustomobject]@{ RelativePath=$relative; Sha256=$hash }
    }
}
$result = [pscustomobject]@{
    GamePath=$gameRoot; SavePath=$saveRoot; StagePath=$stageRoot; BackupPath=$backupRoot
    ArchiveSha256=$pins.loader.sha256; GameModified=$false; GameLaunched=$false
    CloudStatus='Not verified; no Cloud settings changed; one test instance only'
    SaveIsolation='Pending: create and select ITB_Coop_Probe through the game UI before a test mission'
    OverwrittenFiles=@($plan | Where-Object Exists | ForEach-Object RelativePath)
    Files=$plan; GameBackups=$backupRecords; SaveBackups=$saveRecords
}
$manifestPath = Join-Path $backupRoot 'manifest.json'
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
[pscustomobject]@{Manifest=$manifestPath;LoaderFiles=$plan.Count;OverwrittenFiles=$result.OverwrittenFiles;VerifiedGameBackups=$backupRecords.Count;VerifiedSaveBackups=$saveRecords.Count;GameModified=$false} | ConvertTo-Json
