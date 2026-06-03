#Requires -Version 7.0
# PSProfile Proxy loader. This file is lazy-loaded by PSProfile.psm1.

$script:PSProfileProxyPrivateFiles = @(
    'Private\Px.Platform.ps1'
    'Private\Px.Discovery.ps1'
    'Private\Px.Env.ps1'
    'Private\Px.Apps.ps1'
    'Private\Px.Runtime.ps1'
    'Private\Px.Diagnostics.ps1'
    'Private\Px.Commands.ps1'
)

foreach ($file in $script:PSProfileProxyPrivateFiles) {
    $path = Join-Path $PSScriptRoot $file
    if (-not (Test-Path $path)) {
        Write-Warning "PSProfile proxy component not found: $path"
        continue
    }
    . $path
}
