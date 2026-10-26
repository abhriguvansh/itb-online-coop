param([Parameter(Mandatory)][string]$ZigPath,[Parameter(Mandatory)][string]$LuaHeaders,[switch]$RunMockTests)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$zig=(Resolve-Path -LiteralPath $ZigPath).Path
$lua=(Resolve-Path -LiteralPath $LuaHeaders).Path
if(-not(Test-Path -LiteralPath (Join-Path $lua 'lua.h'))){throw 'Lua 5.1 headers missing'}
$output=Join-Path $repo '.local/transport-build'
New-Item -ItemType Directory -Force -Path $output|Out-Null
$env:ZIG_GLOBAL_CACHE_DIR=Join-Path $output 'global-cache'
$env:ZIG_LOCAL_CACHE_DIR=Join-Path $output 'local-cache'
$common=@('cc','-target','x86-windows-gnu','-O2','-Wall','-Wextra','-Werror',"-I$lua")
& $zig @common -shared (Join-Path $repo 'native/transport.c') -lws2_32 -o (Join-Path $output 'itb_transport.dll')
if($LASTEXITCODE-ne0){throw 'Transport DLL compilation failed'}
Get-FileHash -LiteralPath (Join-Path $output 'itb_transport.dll')
if($RunMockTests){
 if($env:GITHUB_ACTIONS-ne'true'){throw 'Native test executable is CI-only after the unresolved local antivirus alert'}
 $test=Join-Path $output 'transport-tests.exe'
 & $zig @common (Join-Path $repo 'tests/native_transport.c') -lws2_32 -o $test
 if($LASTEXITCODE-ne0){throw 'Transport contract compilation failed'}
 & $test
 if($LASTEXITCODE-ne0){throw 'Native transport contracts failed'}
}
