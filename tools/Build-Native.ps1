param(
    [Parameter(Mandatory=$true)][string]$ZigPath,
    [Parameter(Mandatory=$true)][string]$LuaHeaders,
    [Parameter(Mandatory=$true)][string]$SdlHeaders,
    [switch]$RunMockTests
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$zig = (Resolve-Path -LiteralPath $ZigPath).Path
$lua = (Resolve-Path -LiteralPath $LuaHeaders).Path
$sdl = (Resolve-Path -LiteralPath $SdlHeaders).Path
foreach ($header in @((Join-Path $lua 'lua.h'),(Join-Path $sdl 'SDL.h'))) {
    if (-not (Test-Path -LiteralPath $header -PathType Leaf)) { throw "Missing header: $header" }
}
$output = Join-Path $repo '.local/native-build'
New-Item -ItemType Directory -Force -Path $output | Out-Null
$common = @('cc','-target','x86-windows-gnu','-O2','-Wall','-Wextra','-Werror',"-I$lua","-I$sdl")
& $zig @common -shared (Join-Path $repo 'native/input_bridge.c') -luser32 -o (Join-Path $output 'itb_input.dll')
if ($LASTEXITCODE -ne 0) { throw 'Native bridge compilation failed.' }
Get-FileHash -LiteralPath (Join-Path $output 'itb_input.dll') -Algorithm SHA256
if ($RunMockTests) {
    # Explicit opt-in. This compiles a separate executable whose input functions are mocks.
    $test = Join-Path $output 'native-tests.exe'
    & $zig @common (Join-Path $repo 'tests/native_bridge.c') -luser32 -o $test
    if ($LASTEXITCODE -ne 0) { throw 'Native contract compilation failed.' }
    & $test
    if ($LASTEXITCODE -ne 0) { throw 'Native contracts failed.' }
}
