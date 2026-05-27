#Requires -Version 7.0
# PSProfile Proxy v2.0 — env + VSCode の2層同期のみ (WinINET 廃止)
# Lazy load: PSProfile.psm1 のスタブから初回呼び出し時に dot-source される。

# ───────────────────────────────────────────────────────── helpers
function Get-PxExe {
    $e = (Get-Command px -ErrorAction SilentlyContinue)?.Source
    if ($e) { return $e }
    return Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\genotrance.px*" `
        -Filter 'px.exe' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

function Get-PxIniPath {
    param([switch]$PreferExisting)
    $exe = Get-PxExe
    $cands = @()
    if ($exe) { $cands += (Join-Path (Split-Path $exe -Parent) 'px.ini') }
    if ($env:APPDATA)     { $cands += (Join-Path $env:APPDATA     'px\px.ini') }
    if ($env:USERPROFILE) { $cands += (Join-Path $env:USERPROFILE '.px\px.ini') }
    $cands = $cands | Where-Object { $_ } | Select-Object -Unique
    if ($PreferExisting) {
        $hit = $cands | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return ($cands | Select-Object -First 1)
}

function Get-PxIniPort {
    param([string]$IniPath)
    if (-not $IniPath -or -not (Test-Path $IniPath)) { return $null }
    $m = Select-String -Path $IniPath -Pattern '^\s*port\s*=\s*(\d+)' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($m -and $m.Matches.Count -gt 0) { return [int]$m.Matches[0].Groups[1].Value }
    return $null
}

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
        # 末尾プロパティ末尾カンマ補正
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

# プロセス管理
function Get-PxProcessRecordPath {
    if ($env:PSPROFILE_PX_RECORD_PATH -and $env:PSPROFILE_PX_RECORD_PATH.Trim()) { return $env:PSPROFILE_PX_RECORD_PATH }
    $root = @($env:TEMP, $env:TMP, [Environment]::GetFolderPath('LocalApplicationData'), $env:USERPROFILE) |
        Where-Object { $_ -and $_.Trim() } | Select-Object -First 1
    if (-not $root) { $root = [System.IO.Path]::GetTempPath() }
    Join-Path $root 'PSProfile.Proxy.px-process.json'
}

function Get-PxRunningProcess { Get-Process -Name 'px' -ErrorAction SilentlyContinue | Select-Object -First 1 }

function Get-PxProcessRecord {
    $p = Get-PxProcessRecordPath
    if (-not (Test-Path $p)) { return $null }
    try { $r = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json; if ($r.ProcessId) { return $r } } catch {}
    return $null
}

function Set-PxProcessRecord {
    param([int]$ProcessId, [int]$Port)
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ProcessId = $ProcessId; Port = $Port
        StartTimeUtc = if ($proc) { $proc.StartTime.ToUniversalTime().ToString('o') } else { $null }
        UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    } | ConvertTo-Json -Depth 5 | Set-Content (Get-PxProcessRecordPath) -Encoding UTF8
}

function Clear-PxProcessRecord { Remove-Item (Get-PxProcessRecordPath) -ErrorAction SilentlyContinue }

function script:Test-PxPort {
    param([int]$Port)
    $tcp = [System.Net.Sockets.TcpClient]::new()
    try {
        $ar = $tcp.BeginConnect('127.0.0.1', $Port, $null, $null)
        $ok = $ar.AsyncWaitHandle.WaitOne(500)
        if ($ok) { try { $tcp.EndConnect($ar) } catch {} }
        return $ok
    } finally { $tcp.Close() }
}

function Get-PxListenPort {
    $proc = Get-Process -Name 'px' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) { return $null }
    $port = Get-NetTCPConnection -OwningProcess $proc.Id -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalAddress -in '127.0.0.1', '0.0.0.0' } |
        Select-Object -First 1 -ExpandProperty LocalPort
    if ($port) { return $port }
    $line = netstat -ano 2>$null | Where-Object { $_ -match "LISTENING\s+$($proc.Id)\s*$" } | Select-Object -First 1
    if ($line -match '(?:127\.0\.0\.1|0\.0\.0\.0):(\d+)') { return [int]$Matches[1] }
    return $null
}

# ───────────────────────────────────────────────────────── 公開関数

function Start-PxProxy {
    $managed = $null
    $port = Get-PxListenPort
    if (-not $port) {
        $exe = Get-PxExe
        if (-not $exe) { Write-Warning 'px.exe が見つかりません'; return }
        $port = (Get-PxIniPort -IniPath (Get-PxIniPath -PreferExisting)) ?? 63602
        $managed = Start-Process $exe -ArgumentList "--port=$port" -WindowStyle Hidden -PassThru
        $elapsed = 0
        do { Start-Sleep -Milliseconds 300; $elapsed += 300 } while (-not (Test-PxPort $port) -and $elapsed -lt 10000)
        if (-not (Test-PxPort $port)) { Write-Warning 'px.exe 起動タイムアウト'; return }
    } else {
        $managed = Get-PxRunningProcess
    }
    $proxy = "http://127.0.0.1:$port"
    $env:HTTP_PROXY = $env:HTTPS_PROXY = $proxy
    $env:NO_PROXY = 'localhost,127.0.0.1'
    Set-VSCodeProxySetting -ProxyUrl $proxy
    if ($managed) { Set-PxProcessRecord -ProcessId $managed.Id -Port $port }
    Write-Host "px ON  $proxy" -ForegroundColor Green
}

function Stop-PxProxy {
    param([switch]$KeepProcess)
    Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:NO_PROXY -ErrorAction SilentlyContinue
    Set-VSCodeProxySetting -Disable
    $stopped = 0
    if (-not $KeepProcess) {
        $r = Get-PxProcessRecord
        $procs = @()
        if ($r) {
            $t = Get-Process -Id $r.ProcessId -ErrorAction SilentlyContinue
            if ($t -and $r.StartTimeUtc) {
                if ($t.StartTime.ToUniversalTime().ToString('o') -eq $r.StartTimeUtc) { $procs = @($t) }
            } elseif ($t) { $procs = @($t) }
        }
        if (-not $procs) { $procs = @(Get-PxRunningProcess) }
        foreach ($p in $procs | Where-Object { $_ }) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $stopped++ }
            catch { Write-Warning "px 停止失敗 (PID=$($p.Id)): $($_.Exception.Message)" }
        }
        if ($stopped -gt 0) { Clear-PxProcessRecord }
    }
    if ($KeepProcess) { Write-Host 'px OFF (env only)' -ForegroundColor Yellow }
    else { Write-Host "px OFF (stopped=$stopped)" -ForegroundColor Yellow }
}

function Get-PxState {
    [CmdletBinding()]
    param([switch]$Edit)

    $proc = Get-Process -Name 'px' -ErrorAction SilentlyContinue | Select-Object -First 1
    $port = if ($proc) { Get-PxListenPort } else { $null }
    $ini = Get-PxIniPath -PreferExisting
    if (-not $ini) { $ini = Get-PxIniPath }
    $iniPort = Get-PxIniPort -IniPath $ini
    $vs = Get-VSCodeUserSettingsPath
    $vsProxy = $null; $vsSupport = $null
    if ($vs -and (Test-Path $vs)) {
        try {
            $raw = Get-Content $vs -Raw -Encoding UTF8
            $vsProxy = Get-JsoncPropertyValue -Text $raw -PropertyName 'http.proxy'
            $vsSupport = Get-JsoncPropertyValue -Text $raw -PropertyName 'http.proxySupport'
        } catch {}
    }

    if ($Edit) {
        if (-not $ini -or -not (Test-Path $ini)) { Write-Warning "px.ini なし: $ini"; return }
        if (Get-Command code -ErrorAction SilentlyContinue) { code $ini } else { Start-Process notepad $ini }
        return
    }

    $div = '  ' + ('─' * 46)
    Write-Host ''
    Write-Host '  px プロキシ状態' -ForegroundColor White
    Write-Host $div -ForegroundColor DarkGray
    Write-Host '  [ プロセス ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f '稼働', [bool]$proc) -ForegroundColor $(if ($proc) { 'Green' } else { 'DarkGray' })
    Write-Host ('  {0,-16}{1}' -f 'ポート', ($port ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'px.ini', ($ini ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'ini port', ($iniPort ?? '─')) -ForegroundColor Gray
    if ($ini -and $iniPort -and $port -and ($iniPort -ne $port)) {
        Write-Host '  ! px.ini と実行中ポートが不一致 → px-restart 推奨' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host '  [ 環境変数 ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f 'HTTP_PROXY', ($env:HTTP_PROXY ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'HTTPS_PROXY', ($env:HTTPS_PROXY ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'NO_PROXY', ($env:NO_PROXY ?? '─')) -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [ VSCode ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f 'settings', ($vs ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'http.proxy', ($vsProxy ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'proxySupport', ($vsSupport ?? '─')) -ForegroundColor Gray
    if ($proc -and -not $env:HTTP_PROXY) {
        Write-Host ''
        Write-Host '  ! 現ターミナルに環境変数未設定 → px-on で適用' -ForegroundColor Yellow
    }
    Write-Host $div -ForegroundColor DarkGray
    Write-Host ''
}

function Restart-PxProxy { Stop-PxProxy; Start-PxProxy }
