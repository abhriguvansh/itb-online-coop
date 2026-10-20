[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$GamePath,
    [ValidateSet('Plan','Install','Uninstall')][string]$Mode = 'Plan',
    [string]$NativeBridgePath,
    [string]$InitialChoicesPath
)
$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$gameRoot = (Resolve-Path -LiteralPath $GamePath).Path
if (-not (Test-Path -LiteralPath (Join-Path $gameRoot 'Breach.exe') -PathType Leaf)) { throw 'Breach.exe missing.' }
$modRoot = Join-Path $gameRoot 'mods\aman_itb_coop_probe'
$expectedRoot = [IO.Path]::GetFullPath($modRoot)
if (-not $expectedRoot.StartsWith($gameRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Target outside game folder.' }
foreach ($folder in @($gameRoot,(Join-Path $gameRoot 'mods'),$modRoot)) {
    if ((Test-Path -LiteralPath $folder) -and ((Get-Item -LiteralPath $folder).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Linked install folders are not supported.'
    }
}
$sourceRoot = Join-Path $repoPath 'mod'
$files = @('scripts\init.lua','scripts\json.lua','scripts\settle.lua','scripts\snapshot.lua','scripts\probe.lua')
$legacyFiles = @($files)
$files += @('scripts\movement.lua','scripts\movement_ui.lua')
$movementFiles = @($files)
$files += @('scripts\move_trace.lua')
$traceFiles = @($files)
$files += @('scripts\input_gate.lua')
$gateFiles = @($files)
$files += @('scripts\attack.lua')
$attackFiles = @($files)
$files += @('scripts\ui_bridge.lua','itb_input.dll')
$bridgeFiles = @($files)
$files += @('scripts\command_session.lua','scripts\end_turn.lua','scripts\phase_lab.lua')
$phaseFiles = @($files)
$files += @('scripts\phase_wire.lua')
$wireFiles = @($files)
$files += @('scripts\move_intent.lua')
$intentFiles = @($files)
$files += @('scripts\basic_attack.lua')
$basicFiles = @($files)
$files += @('scripts\spawn_sync.lua')
$spawnFiles = @($files)
$files += @('scripts\mission_completion.lua')
$resultFiles = @($files)
$files += @('scripts\inspection.lua')
$inspectionFiles = @($files)
$files += @('scripts\deployment.lua')
$deploymentFiles=@($files)
$files += @('scripts\initial_choices.lua')
if($InitialChoicesPath){$files+=@('itb_initial_choices.dll')}
$markerName = '.itb-coop-probe.json'
$markerPath = Join-Path $modRoot $markerName
if ($Mode -eq 'Plan') {
    [pscustomobject]@{Mode='Plan';Target=$modRoot;Files=$files;ExistingTarget=(Test-Path -LiteralPath $modRoot);LoaderInstalled=(Test-Path -LiteralPath (Join-Path $gameRoot 'scripts\mod_loader\modapi\init.lua'))} | ConvertTo-Json
    return
}
if (Get-Process -Name Breach -ErrorAction SilentlyContinue) { throw 'Close the game before installing or uninstalling.' }
if ($Mode -eq 'Install') {
    if (Test-Path -LiteralPath $modRoot) { throw 'Target already exists. Uninstall this probe before updating; unrelated content will not be overwritten.' }
    $loaderInit = Join-Path $gameRoot 'scripts\mod_loader\modapi\init.lua'
    if (-not (Test-Path -LiteralPath $loaderInit)) { throw 'Install the separately obtained loader first.' }
    if ((Get-Content -LiteralPath $loaderInit -Raw) -notmatch 'self\.version\s*=\s*"2\.9\.6"') { throw 'Expected pinned loader 2.9.6.' }
    if (-not $NativeBridgePath -or -not (Test-Path -LiteralPath $NativeBridgePath -PathType Leaf)) { throw 'Supply a separately built, reviewed native bridge using -NativeBridgePath.' }
    if($InitialChoicesPath-and-not(Test-Path -LiteralPath $InitialChoicesPath -PathType Leaf)){throw 'InitialChoicesPath missing'}
    foreach ($relative in ($files | Where-Object { $_ -notin @('itb_input.dll','itb_initial_choices.dll') })) {
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $relative) -PathType Leaf)) { throw "Missing source $relative" }
    }
    New-Item -ItemType Directory -Path (Join-Path $modRoot 'scripts') | Out-Null
    $installed = @()
    foreach ($relative in $files) {
        $source = if ($relative -eq 'itb_input.dll') { $NativeBridgePath } elseif($relative-eq'itb_initial_choices.dll'){$InitialChoicesPath}else { Join-Path $sourceRoot $relative }
        $destination = Join-Path $modRoot $relative
        Copy-Item -LiteralPath $source -Destination $destination
        $hash = (Get-FileHash -LiteralPath $source).Hash
        if ($hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Copy mismatch: $relative" }
        $installed += [pscustomobject]@{RelativePath=$relative;Sha256=$hash}
    }
    [pscustomobject]@{Id='aman_itb_coop_probe';Version='0.21.0';Files=$installed} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerPath -Encoding utf8
    Write-Output 'Probe installed. The game has not been launched.'
    return
}
if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'Ownership manifest missing; refusing to remove files.' }
$marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
if ($marker.Version -in @('0.1.0','0.1.1')) { $files = $legacyFiles }
elseif ($marker.Version -eq '0.2.0') { $files = $movementFiles }
elseif ($marker.Version -in @('0.2.1','0.2.2')) { $files = $traceFiles }
elseif ($marker.Version -eq '0.3.0') { $files = $gateFiles }
elseif ($marker.Version -in @('0.4.0','0.4.1','0.4.2')) { $files = $attackFiles }
elseif ($marker.Version -in @('0.5.0','0.5.1','0.5.2','0.5.3','0.5.4','0.5.5','0.5.6','0.5.7','0.5.8','0.5.9','0.5.10','0.6.0','0.7.0','0.7.1','0.7.2','0.8.0')) { $files=$bridgeFiles }
elseif ($marker.Version -in @('0.9.0','0.9.1')) { $files=$phaseFiles }
elseif ($marker.Version -eq '0.10.0') { $files=$wireFiles }
elseif ($marker.Version -in @('0.11.0','0.11.1','0.11.2','0.12.0','0.13.0')) { $files=$intentFiles }
elseif ($marker.Version -in @('0.14.0','0.15.0')) { $files=$basicFiles }
elseif ($marker.Version -eq '0.16.0') { $files=$spawnFiles }
elseif ($marker.Version -in @('0.17.0','0.17.1')) { $files=$resultFiles }
elseif ($marker.Version -in @('0.18.0','0.19.0')) { $files=$inspectionFiles }
elseif ($marker.Version -eq '0.20.0') { $files=$deploymentFiles }
elseif ($marker.Version -eq '0.21.0') {
    $files=@($deploymentFiles)+@('scripts\initial_choices.lua')
    if('itb_initial_choices.dll'-in$marker.Files.RelativePath){$files+=@('itb_initial_choices.dll')}
}
else { throw 'Unrecognized probe version; preserve and inspect before removal.' }
if ($marker.Id -ne 'aman_itb_coop_probe' -or $marker.Files.Count -ne $files.Count) { throw 'Unrecognized ownership manifest.' }
$actualFiles = @(Get-ChildItem -LiteralPath $modRoot -File -Force -Recurse)
if (Get-ChildItem -LiteralPath $modRoot -Force -Recurse | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Link in probe folder; refusing removal.' }
$allowedFiles = @($files) + @($markerName)
foreach ($actual in $actualFiles) {
    if ($actual.FullName.Substring($modRoot.Length+1) -notin $allowedFiles) { throw 'Unrecognized file in probe folder; preserve it before uninstalling.' }
}
$seen = @{}
foreach ($record in $marker.Files) {
    if ($record.RelativePath -notin $files -or $seen.ContainsKey($record.RelativePath)) { throw 'Unsafe or duplicate manifest path.' }
    $seen[$record.RelativePath] = $true
    $target = Join-Path $modRoot $record.RelativePath
    if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Get-FileHash -LiteralPath $target).Hash -ne $record.Sha256) {
        throw 'Probe file changed since installation; preserve changes before uninstalling.'
    }
}
# Every absolute target is verified above; never recursively delete the game or mods tree.
foreach ($relative in $files) { Remove-Item -LiteralPath (Join-Path $modRoot $relative) }
Remove-Item -LiteralPath $markerPath
foreach ($folder in @((Join-Path $modRoot 'scripts'),$modRoot)) {
    if (@(Get-ChildItem -LiteralPath $folder -Force).Count -eq 0) { [IO.Directory]::Delete($folder) }
}
Write-Output 'Only the owned probe files were removed. Loader and other mods remain installed.'
