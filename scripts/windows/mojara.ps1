# Mojara convenience launcher for Windows PowerShell.
# This invokes Linux Mojo inside WSL2; it is NOT a native Windows Mojo runtime.
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $MojaraArguments
)

$ErrorActionPreference = 'Stop'

$distro = $env:MOJARA_WSL_DISTRO
if ([string]::IsNullOrWhiteSpace($distro)) {
    $distro = 'Ubuntu-24.04'
}

if (-not (Get-Command 'wsl.exe' -ErrorAction SilentlyContinue)) {
    throw 'WSL2 is unavailable. Install WSL2 and Ubuntu first.'
}

# bash -lc receives arguments after argv[0]. "$@" preserves their boundaries.
# Try the default Pixi global location, then PATH for customized installs.
$command = 'if [ -x "$HOME/.pixi/bin/mojara" ]; then exec "$HOME/.pixi/bin/mojara" "$@"; else exec mojara "$@"; fi'
& wsl.exe --distribution $distro --exec bash -lc $command bash @MojaraArguments
if ($null -eq $LASTEXITCODE) {
    exit 1
}
exit [int]$LASTEXITCODE
