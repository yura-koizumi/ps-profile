#Requires -Version 7.0

function Get-PSProfileProxyTargets {
    $v = Get-Variable -Scope Global -Name PSProfileProxyTargets -ErrorAction SilentlyContinue
    if (-not $v -or -not $v.Value) {
        $preset = Resolve-PSProfileProxyPreset
        if ($preset) { return @($preset.ProxyTargets) }
        if ((Test-PSProfileWindows) -and (Get-PSProfileDeviceRole) -eq 'Work' -and (Get-PSProfileProxyMode) -eq 'WorkPx') {
            return @('Env', 'System')
        }
        return @('Env')
    }
    return @($v.Value | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ })
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


function Get-PSProfileSystemProxyRecordPath {
    if ($env:PSPROFILE_SYSTEM_PROXY_RECORD_PATH -and $env:PSPROFILE_SYSTEM_PROXY_RECORD_PATH.Trim()) { return $env:PSPROFILE_SYSTEM_PROXY_RECORD_PATH }
    $root = if ($env:LOCALAPPDATA -and $env:LOCALAPPDATA.Trim()) { $env:LOCALAPPDATA } else { [System.IO.Path]::GetTempPath() }
    $dir = [System.IO.Path]::Combine($root, 'PSProfile')
    if (-not [IO.Directory]::Exists($dir)) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
    return [System.IO.Path]::Combine($dir, 'system-proxy-before-px.json')
}

function Get-PSProfileSystemProxySettings {
    if (-not (Test-PSProfileWindows)) { return $null }
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    try {
        $p = Get-ItemProperty $path -ErrorAction Stop
        [pscustomobject]@{
            ProxyEnable = $p.ProxyEnable
            ProxyServer = $p.ProxyServer
            ProxyOverride = $p.ProxyOverride
            AutoConfigURL = $p.AutoConfigURL
        }
    } catch { $null }
}

function Save-PSProfileSystemProxySettings {
    if (-not (Test-PSProfileWindows)) { return }
    $recordPath = Get-PSProfileSystemProxyRecordPath
    if ([IO.File]::Exists($recordPath)) { return }
    $settings = Get-PSProfileSystemProxySettings
    if (-not $settings) { return }
    try {
        $settings | ConvertTo-Json -Depth 5 | Set-Content $recordPath -Encoding UTF8
    } catch {
        Write-Warning "Windows system proxy の復元記録に失敗: $($_.Exception.Message)"
    }
}

function ConvertTo-PSProfileWinInetProxyServer {
    param([Parameter(Mandatory)][string]$ProxyUrl)
    try {
        $u = [Uri]$ProxyUrl
        if ($u.Host -and $u.Port -gt 0) { return ('{0}:{1}' -f $u.Host, $u.Port) }
    } catch {}
    return ($ProxyUrl -replace '^https?://', '').TrimEnd('/')
}

function ConvertTo-PSProfileWinInetProxyOverride {
    $noProxy = Get-PSProfileNoProxy
    $items = @($noProxy -split '[,;]' | ForEach-Object { "$($_)".Trim() } | Where-Object { $_ })
    if ($items -notcontains '<local>') { $items += '<local>' }
    return ($items -join ';')
}

function Invoke-PSProfileSystemProxyRefresh {
    if (-not (Test-PSProfileWindows)) { return }
    try {
        if (-not ('PSProfile.WinInet.NativeMethods' -as [type])) {
            Add-Type -Namespace PSProfile.WinInet -Name NativeMethods -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(System.IntPtr hInternet, int dwOption, System.IntPtr lpBuffer, int dwBufferLength);
'@ | Out-Null
        }
        [void][PSProfile.WinInet.NativeMethods]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
        [void][PSProfile.WinInet.NativeMethods]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
    } catch {
        Write-Warning "Windows system proxy の変更通知に失敗: $($_.Exception.Message)"
    }
}

function Set-PSProfileSystemProxy {
    param([Parameter(Mandatory)][string]$ProxyUrl)
    if (-not (Test-PSProfileWindows)) {
        Write-Warning 'System proxy target は Windows でのみ利用できます'
        return
    }
    Save-PSProfileSystemProxySettings
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $server = ConvertTo-PSProfileWinInetProxyServer -ProxyUrl $ProxyUrl
    $override = ConvertTo-PSProfileWinInetProxyOverride
    try {
        New-ItemProperty -Path $path -Name ProxyEnable -PropertyType DWord -Value 1 -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $path -Name ProxyServer -PropertyType String -Value $server -Force -ErrorAction Stop | Out-Null
        New-ItemProperty -Path $path -Name ProxyOverride -PropertyType String -Value $override -Force -ErrorAction Stop | Out-Null
        Remove-ItemProperty -Path $path -Name AutoConfigURL -ErrorAction SilentlyContinue
        Invoke-PSProfileSystemProxyRefresh
    } catch {
        Write-Warning "Windows system proxy 設定失敗: $($_.Exception.Message)"
    }
}

function Restore-PSProfileSystemProxy {
    if (-not (Test-PSProfileWindows)) { return }
    $recordPath = Get-PSProfileSystemProxyRecordPath
    if (-not [IO.File]::Exists($recordPath)) {
        Write-Warning 'Windows system proxy の復元記録がないため system proxy は変更しません'
        return
    }
    try {
        $settings = Get-Content $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
        $enable = if ($null -ne $settings.ProxyEnable) { [int]$settings.ProxyEnable } else { 0 }
        New-ItemProperty -Path $path -Name ProxyEnable -PropertyType DWord -Value $enable -Force -ErrorAction Stop | Out-Null
        foreach ($name in 'ProxyServer', 'ProxyOverride', 'AutoConfigURL') {
            $value = $settings.$name
            if ($null -ne $value -and "$value" -ne '') {
                New-ItemProperty -Path $path -Name $name -PropertyType String -Value "$value" -Force -ErrorAction Stop | Out-Null
            } else {
                Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
            }
        }
        Invoke-PSProfileSystemProxyRefresh
        Remove-Item $recordPath -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Windows system proxy 復元失敗: $($_.Exception.Message)"
    }
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
