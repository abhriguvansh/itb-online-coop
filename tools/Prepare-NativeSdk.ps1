# Downloads build inputs into ignored .local only. No installation or execution.
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $repo '.local/native-ci'
if (Test-Path -LiteralPath $root) { throw 'Native SDK directory already exists; preserve and inspect it.' }
New-Item -ItemType Directory -Path $root | Out-Null
function Fetch-Checked($Url,$Name,$Sha256) {
    $destination = Join-Path $root $Name
    Invoke-WebRequest -Uri $Url -OutFile $destination
    if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Checksum mismatch: $Name"
    }
    return $destination
}
$zig = Fetch-Checked 'https://ziglang.org/download/0.14.1/zig-x86_64-windows-0.14.1.zip' 'zig.zip' '554f5378228923ffd558eac35e21af020c73789d87afeabf4bfd16f2e6feed2c'
$lua = Fetch-Checked 'https://www.lua.org/ftp/lua-5.1.5.tar.gz' 'lua.tar.gz' '2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333'
Expand-Archive -LiteralPath $zig -DestinationPath $root
& tar -xzf $lua -C $root
if ($LASTEXITCODE -ne 0) { throw 'Lua header extraction failed.' }
$source = Join-Path $root 'native-source'
& git -c http.sslBackend=schannel clone --no-checkout https://github.com/kartoFlane/IntoTheBreachLua.git $source
if ($LASTEXITCODE -ne 0) { throw 'Header source clone failed.' }
$revision = 'dcf22e726088f9f1ab788c693a59259450e31ef6'
& git -C $source checkout $revision -- sdl
if ($LASTEXITCODE -ne 0) { throw 'Pinned SDL header checkout failed.' }
Write-Output 'Pinned build inputs prepared. No compiler, test, or game was launched.'
