#Requires -Version 7.0

function Get-PSProfilePlatform {
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS) { return 'macOS' }
    if ($IsLinux) { return 'Linux' }
    return 'Unknown'
}

function Test-PSProfileWindows { return (Get-PSProfilePlatform) -eq 'Windows' }
function Test-PSProfileMacOS { return (Get-PSProfilePlatform) -eq 'macOS' }


function Get-PSProfileProxyPreset {
    foreach ($name in 'PSProfileProxyPreset', 'PSProfileNetworkProfile') {
        $v = Get-Variable -Scope Global -Name $name -ErrorAction SilentlyContinue
        if ($v -and "$($v.Value)".Trim()) { return "$($v.Value)".Trim() }
    }
    return $null
}

function Resolve-PSProfileProxyPreset {
    $preset = Get-PSProfileProxyPreset
    if (-not $preset) { return $null }
    $key = ($preset -replace '[\s_\-]', '').ToLowerInvariant()
    switch ($key) {
        { $_ -in @('workpc', 'work', 'office', 'company', '職場pc', '職場') } {
            return [pscustomobject]@{ Name = 'WorkPc'; DeviceRole = 'Work'; ProxyMode = 'WorkPx'; ProxyTargets = @('Env', 'System') }
        }
        { $_ -in @('workpcwithvscode', 'workvscode', 'officevscode', '職場pcvscode', '職場vscode') } {
            return [pscustomobject]@{ Name = 'WorkPcWithVSCode'; DeviceRole = 'Work'; ProxyMode = 'WorkPx'; ProxyTargets = @('Env', 'System', 'VSCode') }
        }
        { $_ -in @('powershellonly', 'terminalonly', 'shellonly', 'envonly', 'このpowershellだけ', 'powershellだけ') } {
            return [pscustomobject]@{ Name = 'PowerShellOnly'; DeviceRole = 'Work'; ProxyMode = 'WorkPx'; ProxyTargets = @('Env') }
        }
        { $_ -in @('privatepc', 'private', 'home', 'noproxy', 'none', '私用pc', '私用', '使わない') } {
            return [pscustomobject]@{ Name = 'PrivatePc'; DeviceRole = 'Private'; ProxyMode = 'None'; ProxyTargets = @('Env') }
        }
        { $_ -in @('manualproxy', 'manual', 'manualfull', '手動proxy', '手動プロキシ') } {
            return [pscustomobject]@{ Name = 'ManualProxy'; DeviceRole = 'Work'; ProxyMode = 'Manual'; ProxyTargets = @('Env', 'System') }
        }
        default {
            Write-Warning "PSProfileProxyPreset '$preset' は未対応です。WorkPc / WorkPcWithVSCode / PowerShellOnly / PrivatePc / ManualProxy から選んでください。"
            return $null
        }
    }
}

function Get-PSProfileProxyMode {
    $v = Get-Variable -Scope Global -Name PSProfileProxyMode -ErrorAction SilentlyContinue
    if ($v -and "$($v.Value)".Trim()) { return "$($v.Value)" }
    $preset = Resolve-PSProfileProxyPreset
    if ($preset) { return $preset.ProxyMode }
    return 'Unknown'
}

function Get-PSProfileDeviceRole {
    $v = Get-Variable -Scope Global -Name PSProfileDeviceRole -ErrorAction SilentlyContinue
    if ($v -and "$($v.Value)".Trim()) { return "$($v.Value)" }
    $preset = Resolve-PSProfileProxyPreset
    if ($preset) { return $preset.DeviceRole }
    return 'Unknown'
}

function Get-PSProfileProxyUrl {
    foreach ($name in 'PSProfileProxyUrl', 'PSProfileManualProxyUrl') {
        $v = Get-Variable -Scope Global -Name $name -ErrorAction SilentlyContinue
        if ($v -and "$($v.Value)".Trim()) { return "$($v.Value)" }
    }
    return $null
}
