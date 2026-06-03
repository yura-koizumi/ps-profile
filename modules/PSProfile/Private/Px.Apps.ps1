#Requires -Version 7.0

function Get-VSCodeUserSettingsPath {
    $cands = @()
    if ($env:APPDATA) {
        $cands += (Join-Path $env:APPDATA 'Code\User\settings.json')
        $cands += (Join-Path $env:APPDATA 'Code - Insiders\User\settings.json')
    }
    if (-not $cands) { return $null }
    $hit = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($hit) { return $hit }
    return $cands[0]
}

function Get-JsoncPropertyValue {
    param([string]$Text, [string]$PropertyName)
    if (-not $Text) { return $null }
    $e = [regex]::Escape($PropertyName)
    $m = [regex]::Match($Text, "(?m)^\s*`"$e`"\s*:\s*(?<v>`"(?:\\.|[^`"])*`"|true|false|null|-?\d+(?:\.\d+)?)\s*,?\s*$")
    if (-not $m.Success) { return $null }
    $v = $m.Groups['v'].Value
    if ($v.StartsWith('"')) {
        return ($v.Substring(1, $v.Length - 2) -replace '\\\\', '\\' -replace '\\"', '"')
    }
    return $v
}

function Set-JsoncPropertyLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$PropertyName,
        [AllowNull()][string]$PropertyValue,
        [ref]$Found
    )
    $e = [regex]::Escape($PropertyName)
    $val = if ($null -eq $PropertyValue) { 'null' } else { '"' + ($PropertyValue -replace '\\', '\\\\' -replace '"', '\\"') + '"' }
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^(?<indent>\s*)`"$e`"\s*:\s*(?<v>.*?)(?<c>,?)\s*$") {
            $Lines[$i] = ('{0}"{1}": {2}{3}' -f $Matches['indent'], $PropertyName, $val, $Matches['c'])
            $Found.Value = $true; return
        }
    }
    $Found.Value = $false
}

function Update-VSCodeProxySettingsText {
    param([string]$Text, [AllowNull()][string]$ProxyUrl, [switch]$Disable)
    if (-not $Text) { $Text = "{`n}`n" }
    if (-not ($Text -match '\{')) { $Text = "{`n$Text`n}" }
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($l in ($Text -split "`r?`n")) { $null = $lines.Add($l) }
    $desired = if ($Disable) {
        @{ 'http.proxy' = ''; 'http.proxySupport' = 'fallback' }
    } else {
        @{ 'http.proxy' = $ProxyUrl; 'http.proxySupport' = 'override' }
    }
    $missing = @()
    foreach ($n in 'http.proxy', 'http.proxySupport') {
        $f = $false
        Set-JsoncPropertyLine -Lines $lines -PropertyName $n -PropertyValue $desired[$n] -Found ([ref]$f)
        if (-not $f) { $missing += $n }
    }
    if ($missing.Count -gt 0) {
        $closing = $null
        for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '^\s*}\s*$') { $closing = $i; break } }
        if ($null -eq $closing) { $lines.Add('}'); $closing = $lines.Count - 1 }
        $last = $null
        for ($i = $closing - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match '^\s*$|^\s*//|^\s*/\*|^\s*\*') { continue }
            if ($lines[$i] -match '^\s*".+"\s*:') { $last = $i; break }
        }
        if ($null -ne $last -and $lines[$last] -notmatch ',\s*(//.*)?$') {
            if ($lines[$last] -match '^(?<b>.*?)(?<c>\s*//.*)?$') {
                $cmt = $Matches['c']
                $lines[$last] = if ($cmt) { $Matches['b'] + ',' + $cmt } else { $lines[$last] + ',' }
            } else { $lines[$last] += ',' }
        }
        $ind = $null
        for ($i = 0; $i -lt $closing; $i++) { if ($lines[$i] -match '^(?<i>\s*)"') { $ind = $Matches['i']; break } }
        if (-not $ind) {
            $cind = ''
            if ($lines[$closing] -match '^(?<i>\s*)\}') { $cind = $Matches['i'] }
            $ind = $cind + '  '
        }
        $ins = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $missing.Count; $i++) {
            $c = if ($i -lt $missing.Count - 1) { ',' } else { '' }
            $v = $desired[$missing[$i]]
            $vt = if ($null -eq $v) { 'null' } else { '"' + ($v -replace '\\', '\\\\' -replace '"', '\\"') + '"' }
            $null = $ins.Add(('{0}"{1}": {2}{3}' -f $ind, $missing[$i], $vt, $c))
        }
        $pre = if ($closing -gt 0) { $lines[0..($closing - 1)] } else { @() }
        $suf = $lines[$closing..($lines.Count - 1)]
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($l in $pre) { $null = $lines.Add($l) }
        foreach ($l in $ins) { $null = $lines.Add($l) }
        foreach ($l in $suf) { $null = $lines.Add($l) }
    }
    return ($lines -join "`n")
}

function Set-VSCodeProxySetting {
    param([AllowNull()][string]$ProxyUrl, [switch]$Disable)
    $p = Get-VSCodeUserSettingsPath
    if (-not $p) { return }
    $d = Split-Path $p -Parent
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    try {
        $raw = if (Test-Path $p) { Get-Content $p -Raw -Encoding UTF8 } else { "{`n}`n" }
        $new = Update-VSCodeProxySettingsText -Text $raw -ProxyUrl $ProxyUrl -Disable:$Disable
        Set-Content $p $new -Encoding UTF8
    } catch {
        Write-Warning "VSCode settings.json 更新失敗: $($_.Exception.Message)"
    }
}

function Test-PSProfileSyncVSCodeProxy {
    return (($global:PSProfileSyncVSCodeProxy -eq $true) -or (Test-PSProfileProxyTarget 'VSCode'))
}

function Get-GitProxyState {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return $null }
    $http = $null
    $https = $null
    try { $http = (& $git.Source config --global --get http.proxy 2>$null) } catch {}
    try { $https = (& $git.Source config --global --get https.proxy 2>$null) } catch {}
    [pscustomobject]@{
        HttpProxy = $http
        HttpsProxy = $https
    }
}

function Get-NpmProxyState {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) { return $null }
    $proxy = $null
    $httpsProxy = $null
    try { $proxy = (& $npm.Source config get proxy 2>$null) } catch {}
    try { $httpsProxy = (& $npm.Source config get https-proxy 2>$null) } catch {}
    if ($proxy -eq 'null') { $proxy = $null }
    if ($httpsProxy -eq 'null') { $httpsProxy = $null }
    [pscustomobject]@{
        Proxy = $proxy
        HttpsProxy = $httpsProxy
    }
}

function Get-PipProxyState {
    $pip = Get-Command pip -ErrorAction SilentlyContinue
    if (-not $pip) { $pip = Get-Command pip3 -ErrorAction SilentlyContinue }
    if (-not $pip) { return $null }
    $proxy = $null
    try { $proxy = (& $pip.Source config get global.proxy 2>$null) } catch {}
    if ($proxy -match 'No such key') { $proxy = $null }
    [pscustomobject]@{
        Proxy = $proxy
    }
}
