param(
    [Parameter(Mandatory)][string]$ZigPath,
    [Parameter(Mandatory)][string]$LuaHeaders,
    [switch]$RunMockTests
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$zig=(Resolve-Path -LiteralPath $ZigPath).Path
$lua=(Resolve-Path -LiteralPath $LuaHeaders).Path
if(-not(Test-Path -LiteralPath (Join-Path $lua 'lua.h'))){throw 'Lua 5.1 headers missing'}
$output=Join-Path $repo '.local/initial-choices-build'
New-Item -ItemType Directory -Force -Path $output|Out-Null
$common=@('cc','-target','x86-windows-gnu','-O2','-Wall','-Wextra','-Werror',"-I$lua")
& $zig @common -shared (Join-Path $repo 'native/initial_choices.c') -ladvapi32 -o (Join-Path $output 'itb_initial_choices.dll')
if($LASTEXITCODE-ne0){throw 'Initial-choice DLL compilation failed'}
Get-FileHash -LiteralPath (Join-Path $output 'itb_initial_choices.dll')
if($RunMockTests){
    if($env:GITHUB_ACTIONS-ne'true'){throw 'Native test executable is CI-only after the unresolved local antivirus alert'}
    $test=Join-Path $output 'initial-choice-tests.exe'
    & $zig @common (Join-Path $repo 'tests/native_initial_choices.c') -ladvapi32 -o $test
    if($LASTEXITCODE-ne0){throw 'Initial-choice contract compilation failed'}
    & $test
    if($LASTEXITCODE-ne0){throw 'Initial-choice native contracts failed'}
}
