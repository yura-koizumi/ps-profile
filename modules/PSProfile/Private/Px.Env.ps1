#Requires -Version 7.0

function Get-PSProfileProxyTargets {
    $v = Get-Variable -Scope Global -Name PSProfileProxyTargets -ErrorAction SilentlyContinue
    if (-not $v -or -not $v.Value) { return @('Env') }
    return @($v.Value | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
}

function Test-PSProfileProxyTarget {
    param([Parameter(Mandatory)][string]$Name)
    foreach ($t in Get-PSProfileProxyTargets) {
        if ($t -eq '*' -or $t -ieq $Name) { return $true }
    }
    return $false
}

function Get-PSProfileNoProxy {
    $v = Get-Variable -Scope Global -Name PSProfileNoProxy -ErrorAction SilentlyContinue
    if ($v -and "$($v.Value)".Trim()) { return "$($v.Value)" }
    return 'localhost,127.0.0.1'
}

function Test-PSProfileLowercaseProxyEnv {
    $v = Get-Variable -Scope Global -Name PSProfileSetLowercaseProxyEnv -ErrorAction SilentlyContinue
    if (-not $v) { return $true }
    return ($v.Value -eq $true)
}

function Set-PSProfileProxyEnv {
    param([Parameter(Mandatory)][string]$ProxyUrl)
    $noProxy = Get-PSProfileNoProxy
    $env:HTTP_PROXY = $env:HTTPS_PROXY = $ProxyUrl
    $env:NO_PROXY = $noProxy
    if (Test-PSProfileLowercaseProxyEnv) {
        $env:http_proxy = $env:https_proxy = $ProxyUrl
        $env:no_proxy = $noProxy
    }
}

function Clear-PSProfileProxyEnv {
    Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:NO_PROXY, Env:http_proxy, Env:https_proxy, Env:no_proxy -ErrorAction SilentlyContinue
}

function Get-ProxyPortFromUrl {
    param([string]$Url)
    if (-not $Url) { return $null }
    try {
        $u = [Uri]$Url
        if ($u.Port -gt 0) { return $u.Port }
    } catch {}
    if ($Url -match ':(\d+)(?:/)?$') { return [int]$Matches[1] }
    return $null
}
