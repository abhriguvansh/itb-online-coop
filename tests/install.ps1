$ErrorActionPreference = 'Stop'
$repoPath = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $repoPath ('.local\tests\install-' + [guid]::NewGuid().ToString('N'))
$gameRoot = Join-Path $fixtureRoot 'fake-game'
New-Item -ItemType Directory -Path (Join-Path $gameRoot 'scripts\mod_loader\modapi') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $gameRoot 'mods\unrelated') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $gameRoot 'Breach.exe') -Value 'inert test fixture, not executable'
Set-Content -LiteralPath (Join-Path $gameRoot 'scripts\mod_loader\modapi\init.lua') -Value 'self.version = "2.9.6"'
Set-Content -LiteralPath (Join-Path $gameRoot 'mods\unrelated\keep.txt') -Value 'preserve'
$nativeFixture = Join-Path $fixtureRoot 'inert-native.dll'
Set-Content -LiteralPath $nativeFixture -Value 'inert fixture, never loaded'
$installer = Join-Path $repoPath 'tools\Install-Probe.ps1'
$modRoot = Join-Path $gameRoot 'mods\aman_itb_coop_probe'
function Assert-Condition($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Expect-Failure([scriptblock]$Action) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    Assert-Condition $failed 'Expected rejection.'
}
& $installer -GamePath $gameRoot -Mode Plan | Out-Null
Assert-Condition (-not (Test-Path -LiteralPath $modRoot)) 'Plan wrote into fixture.'
& $installer -GamePath $gameRoot -Mode Install -NativeBridgePath $nativeFixture | Out-Null
Assert-Condition (Test-Path -LiteralPath (Join-Path $modRoot 'scripts\init.lua')) 'Probe missing.'
Assert-Condition (@(Get-ChildItem -LiteralPath $modRoot -File -Recurse -Force).Count -eq 16) 'Unexpected install payload.'
Expect-Failure { & $installer -GamePath $gameRoot -Mode Install -NativeBridgePath $nativeFixture }
$initPath = Join-Path $modRoot 'scripts\init.lua'
$original = [IO.File]::ReadAllBytes($initPath)
Add-Content -LiteralPath $initPath -Value '-- local edit'
Expect-Failure { & $installer -GamePath $gameRoot -Mode Uninstall }
Assert-Condition (Test-Path -LiteralPath (Join-Path $modRoot '.itb-coop-probe.json')) 'Partial uninstall after failed preflight.'
[IO.File]::WriteAllBytes($initPath, $original)
Set-Content -LiteralPath (Join-Path $modRoot 'unowned.txt') -Value 'preserve'
Expect-Failure { & $installer -GamePath $gameRoot -Mode Uninstall }
Remove-Item -LiteralPath (Join-Path $modRoot 'unowned.txt')
& $installer -GamePath $gameRoot -Mode Uninstall | Out-Null
Assert-Condition (-not (Test-Path -LiteralPath $modRoot)) 'Owned folder remains.'
Assert-Condition ((Get-Content -LiteralPath (Join-Path $gameRoot 'mods\unrelated\keep.txt') -Raw).Trim() -eq 'preserve') 'Unrelated mod changed.'
Assert-Condition (Test-Path -LiteralPath (Join-Path $gameRoot 'scripts\mod_loader\modapi\init.lua')) 'Loader changed.'
& $installer -GamePath $gameRoot -Mode Install -NativeBridgePath $nativeFixture | Out-Null
# Simulate the exact earlier five-file ownership schema to exercise upgrade removal.
$markerPath = Join-Path $modRoot '.itb-coop-probe.json'
$marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
foreach ($newFile in @('command_session','end_turn','phase_lab')) { Remove-Item -LiteralPath (Join-Path $modRoot ('scripts\'+$newFile+'.lua')) }
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'command_session|end_turn|phase_lab' })
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\ui_bridge.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'itb_input.dll')
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'ui_bridge|itb_input' })
$marker.Version = '0.1.1'
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'movement|move_trace|input_gate|attack' })
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\move_trace.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\input_gate.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\attack.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\movement.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\movement_ui.lua')
$marker | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerPath -Encoding utf8
& $installer -GamePath $gameRoot -Mode Uninstall | Out-Null
Assert-Condition (-not (Test-Path -LiteralPath $modRoot)) 'Legacy probe could not be removed for upgrade.'
& $installer -GamePath $gameRoot -Mode Install -NativeBridgePath $nativeFixture | Out-Null
$marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
foreach ($newFile in @('command_session','end_turn','phase_lab')) { Remove-Item -LiteralPath (Join-Path $modRoot ('scripts\'+$newFile+'.lua')) }
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'command_session|end_turn|phase_lab' })
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\ui_bridge.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'itb_input.dll')
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'ui_bridge|itb_input' })
$marker.Version = '0.2.0'
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'move_trace|input_gate|attack' })
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\move_trace.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\input_gate.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\attack.lua')
$marker | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerPath -Encoding utf8
& $installer -GamePath $gameRoot -Mode Uninstall | Out-Null
Assert-Condition (-not (Test-Path -LiteralPath $modRoot)) 'Seven-file probe upgrade removal failed.'
Write-Output 'Installer fixture checks passed: plan, exact payload, duplicate rejection, changed-file rejection, unowned-file rejection, uninstall, unrelated-mod preservation.'
Write-Output "Inert test evidence retained at $fixtureRoot"

& $installer -GamePath $gameRoot -Mode Install -NativeBridgePath $nativeFixture | Out-Null
$marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
foreach ($newFile in @('command_session','end_turn','phase_lab')) { Remove-Item -LiteralPath (Join-Path $modRoot ('scripts\'+$newFile+'.lua')) }
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'command_session|end_turn|phase_lab' })
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\ui_bridge.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'itb_input.dll')
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'ui_bridge|itb_input' })
$marker.Version = '0.2.2'
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'input_gate|attack' })
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\input_gate.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\attack.lua')
$marker | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerPath -Encoding utf8
& $installer -GamePath $gameRoot -Mode Uninstall | Out-Null
Assert-Condition (-not (Test-Path -LiteralPath $modRoot)) 'Eight-file probe upgrade removal failed.'

& $installer -GamePath $gameRoot -Mode Install -NativeBridgePath $nativeFixture | Out-Null
$marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
foreach ($newFile in @('command_session','end_turn','phase_lab')) { Remove-Item -LiteralPath (Join-Path $modRoot ('scripts\'+$newFile+'.lua')) }
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'command_session|end_turn|phase_lab' })
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\ui_bridge.lua')
Remove-Item -LiteralPath (Join-Path $modRoot 'itb_input.dll')
$marker.Files = @($marker.Files | Where-Object { $_.RelativePath -notmatch 'ui_bridge|itb_input' })
$marker.Version = '0.3.0'
$marker.Files = @($marker.Files | Where-Object RelativePath -NotLike '*attack*')
Remove-Item -LiteralPath (Join-Path $modRoot 'scripts\attack.lua')
$marker | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $markerPath -Encoding utf8
& $installer -GamePath $gameRoot -Mode Uninstall | Out-Null
Assert-Condition (-not (Test-Path -LiteralPath $modRoot)) 'Nine-file probe upgrade removal failed.'
