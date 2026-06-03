#Requires -Version 7.0

function Get-PSProfilePlatform {
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS) { return 'macOS' }
    if ($IsLinux) { return 'Linux' }
    return 'Unknown'
}

function Test-PSProfileWindows { return (Get-PSProfilePlatform) -eq 'Windows' }
function Test-PSProfileMacOS { return (Get-PSProfilePlatform) -eq 'macOS' }

function Get-PSProfileProxyMode {
    $v = Get-Variable -Scope Global -Name PSProfileProxyMode -ErrorAction SilentlyContinue
    if ($v -and "$($v.Value)".Trim()) { return "$($v.Value)" }
    return 'Unknown'
}

function Get-PSProfileDeviceRole {
    $v = Get-Variable -Scope Global -Name PSProfileDeviceRole -ErrorAction SilentlyContinue
    if ($v -and "$($v.Value)".Trim()) { return "$($v.Value)" }
    return 'Unknown'
}

function Get-PSProfileProxyUrl {
    foreach ($name in 'PSProfileProxyUrl', 'PSProfileManualProxyUrl') {
        $v = Get-Variable -Scope Global -Name $name -ErrorAction SilentlyContinue
        if ($v -and "$($v.Value)".Trim()) { return "$($v.Value)" }
    }
    return $null
}
