#Requires -Version 7.0

function Write-PSProfileProxyScope {
    param([switch]$VSCodeChanged, [switch]$SystemChanged)
    $parts = @('現在の PowerShell 環境変数')
    if ($SystemChanged) { $parts += 'Windows system proxy / ブラウザー / デスクトップアプリ' }
    if ($VSCodeChanged) { $parts += 'VSCode settings.json' }
    Write-Host ('影響範囲: ' + ($parts -join ' + ')) -ForegroundColor DarkGray
}

function Start-PSProfilePxProxy {
    $mode = Get-PSProfileProxyMode
    $deviceRole = Get-PSProfileDeviceRole
    if ($deviceRole -eq 'Private') {
        Write-Warning 'PSProfileDeviceRole=Private のため proxy は有効化しません'
        return
    }
    if ($mode -eq 'None') {
        Write-Warning 'PSProfileProxyMode=None のため proxy は有効化しません'
        return
    }
    if ($mode -eq 'Unknown') {
        Write-Warning 'PSProfileProxyMode が未設定です。user-config.ps1 で WorkPx / Manual / None を明示することを推奨します'
    }
    # Manual は Windows でも Px を起動せず、明示 URL を現セッションへ適用する。
    # VPN や社外ネットワークなど、Px ではなく固定 proxy を使いたい場面の UX を改善する。
    if ($mode -eq 'Manual' -or -not (Test-PSProfileWindows)) {
        $manualProxy = Get-PSProfileProxyUrl
        if (-not $manualProxy) {
            Write-Warning 'env proxy が必要な場合は $global:PSProfileProxyUrl を設定してください'
            return
        }
        Set-PSProfileProxyEnv -ProxyUrl $manualProxy
        $syncSystem = Test-PSProfileProxyTarget 'System'
        if ($syncSystem) {
            Set-PSProfileSystemProxy -ProxyUrl $manualProxy
        }
        $syncVSCode = Test-PSProfileSyncVSCodeProxy
        if ($syncVSCode) {
            Set-VSCodeProxySetting -ProxyUrl $manualProxy
        }
        Write-Host "proxy ON  $manualProxy" -ForegroundColor Green
        Write-PSProfileProxyScope -VSCodeChanged:$syncVSCode -SystemChanged:$syncSystem
        return
    }

    $managed = $null
    $port = Get-PxRecordedPortIfReachable
    if (-not $port) { $port = Get-PxListenPort }
    if (-not $port) {
        $exe = Get-PxExe
        if (-not $exe) { Write-Warning 'px.exe が見つかりません'; return }
        $port = (Get-PxIniPort -IniPath (Get-PxIniPath -PreferExisting)) ?? 63602
        $managed = Start-Process $exe -ArgumentList "--port=$port" -WindowStyle Hidden -PassThru
        $elapsed = 0
        $ready = $false
        do {
            Start-Sleep -Milliseconds 200
            $elapsed += 200
            $ready = Test-PxPort $port
        } while (-not $ready -and $elapsed -lt 8000)
        if (-not $ready) { Write-Warning 'px.exe 起動タイムアウト'; return }
        $actualPort = Get-PxListenPort
        if ($actualPort) { $port = $actualPort }
    } else {
        $managed = Get-PxRunningProcess
    }
    $proxy = "http://127.0.0.1:$port"
    Set-PSProfileProxyEnv -ProxyUrl $proxy
    $syncSystem = Test-PSProfileProxyTarget 'System'
    if ($syncSystem) {
        Set-PSProfileSystemProxy -ProxyUrl $proxy
    }
    $syncVSCode = Test-PSProfileSyncVSCodeProxy
    if ($syncVSCode) {
        Set-VSCodeProxySetting -ProxyUrl $proxy
    }
    if ($managed) { Set-PxProcessRecord -ProcessId $managed.Id -Port $port }
    Write-Host "px ON  $proxy" -ForegroundColor Green
    Write-PSProfileProxyScope -VSCodeChanged:$syncVSCode -SystemChanged:$syncSystem
    if (-not $syncVSCode) {
        Write-Host 'VSCode settings.json は未変更 (PSProfileSyncVSCodeProxy=false)' -ForegroundColor DarkGray
    }
}

function Stop-PSProfilePxProxy {
    [CmdletBinding()]
    param([switch]$KeepProcess, [switch]$StopProcess)

    Clear-PSProfileProxyEnv
    $syncSystem = Test-PSProfileProxyTarget 'System'
    if ($syncSystem) {
        Restore-PSProfileSystemProxy
    }
    $syncVSCode = Test-PSProfileSyncVSCodeProxy
    if ($syncVSCode) {
        Set-VSCodeProxySetting -Disable
    }
    $stopped = 0
    $stopOnOffVar = Get-Variable -Scope Global -Name PSProfileStopPxProcessOnOff -ErrorAction SilentlyContinue
    $stopOnOff = $stopOnOffVar -and ($stopOnOffVar.Value -eq $true)
    $shouldStop = $StopProcess -or ($stopOnOff -and -not $KeepProcess)
    if ($shouldStop) {
        $r = Get-PxProcessRecord
        $procs = @()
        if ($r) {
            $t = Get-Process -Id $r.ProcessId -ErrorAction SilentlyContinue
            if ($t -and $r.StartTimeUtc) {
                if ($t.StartTime.ToUniversalTime().ToString('o') -eq $r.StartTimeUtc) { $procs = @($t) }
            } elseif ($t) { $procs = @($t) }
        }
        foreach ($p in $procs | Where-Object { $_ }) {
            try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $stopped++ }
            catch { Write-Warning "px 停止失敗 (PID=$($p.Id)): $($_.Exception.Message)" }
        }
        if ($stopped -gt 0) { Clear-PxProcessRecord }
    }
    if ($shouldStop) { Write-Host "px OFF (stopped=$stopped)" -ForegroundColor Yellow }
    elseif ($syncSystem) { Write-Host 'px OFF (env + system proxy restored; px process kept)' -ForegroundColor Yellow }
    else { Write-Host 'px OFF (env only; px process kept)' -ForegroundColor Yellow }
    Write-PSProfileProxyScope -VSCodeChanged:$syncVSCode -SystemChanged:$syncSystem
    if (-not $syncVSCode) {
        Write-Host 'VSCode settings.json は未変更 (PSProfileSyncVSCodeProxy=false)' -ForegroundColor DarkGray
    }
}

function Get-PSProfilePxState {
    [CmdletBinding()]
    param([switch]$Edit, [switch]$Json)

    $s = Get-PSProfilePxSnapshot

    if ($Json) {
        $s | ConvertTo-Json -Depth 8
        return
    }

    if ($Edit) {
        if (-not $s.SelectedIni -or -not (Test-Path $s.SelectedIni)) { Write-Warning "px.ini なし: $($s.SelectedIni)"; return }
        if (Get-Command code -ErrorAction SilentlyContinue) { code $s.SelectedIni } else { Start-Process notepad $s.SelectedIni }
        return
    }

    $div = '  ' + ('─' * 46)
    Write-Host ''
    Write-Host '  px プロキシ状態' -ForegroundColor White
    Write-Host $div -ForegroundColor DarkGray
    Write-Host '  [ Profile ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f 'platform', $s.Platform) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'preset', ($s.ProxyPreset ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'device role', $s.DeviceRole) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'proxy mode', $s.ProxyMode) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'targets', (($s.ProxyTargets -join ', ') ?? '─')) -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [ Px executable ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f 'selected', ($s.PxExe ?? '─')) -ForegroundColor Gray
    foreach ($e in $s.ExeCandidates) {
        Write-Host ('  {0,-16}{1}' -f $e.Source, $e.Path) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  [ Px config ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f 'selected ini', ($s.SelectedIni ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'ini port', ($s.IniPort ?? '─')) -ForegroundColor Gray
    foreach ($i in $s.IniCandidates) {
        $mark = if ($i.Exists) { 'exists' } else { 'missing' }
        Write-Host ('  {0,-16}{1} ({2})' -f $i.Source, $i.Path, $mark) -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  [ プロセス ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f '稼働', $s.Runtime.Running) -ForegroundColor $(if ($s.Runtime.Running) { 'Green' } else { 'DarkGray' })
    Write-Host ('  {0,-16}{1}' -f 'pid', ($s.Runtime.ProcessId ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'listen port', ($s.Runtime.ListenPort ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'managed', $s.Runtime.Managed) -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [ 環境変数 ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f 'HTTP_PROXY', ($s.EnvHttpProxy ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'HTTPS_PROXY', ($s.EnvHttpsProxy ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'NO_PROXY', ($s.EnvNoProxy ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'http_proxy', ($s.EnvLowerHttpProxy ?? '─')) -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [ VSCode ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f 'sync enabled', $s.VSCodeSyncEnabled) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'settings', ($s.VSCodeSettings ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'http.proxy', ($s.VSCodeProxy ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'proxySupport', ($s.VSCodeProxySupport ?? '─')) -ForegroundColor Gray
    Write-Host ''
    Write-Host '  [ Git ]' -ForegroundColor Cyan
    if ($s.Git) {
        Write-Host ('  {0,-16}{1}' -f 'http.proxy', ($s.Git.HttpProxy ?? '─')) -ForegroundColor Gray
        Write-Host ('  {0,-16}{1}' -f 'https.proxy', ($s.Git.HttpsProxy ?? '─')) -ForegroundColor Gray
    } else {
        Write-Host ('  {0,-16}{1}' -f 'git', 'not found') -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  [ npm / pip ]' -ForegroundColor Cyan
    if ($s.Npm) {
        Write-Host ('  {0,-16}{1}' -f 'npm proxy', ($s.Npm.Proxy ?? '─')) -ForegroundColor Gray
        Write-Host ('  {0,-16}{1}' -f 'npm https', ($s.Npm.HttpsProxy ?? '─')) -ForegroundColor Gray
    } else {
        Write-Host ('  {0,-16}{1}' -f 'npm', 'not found') -ForegroundColor DarkGray
    }
    if ($s.Pip) {
        Write-Host ('  {0,-16}{1}' -f 'pip proxy', ($s.Pip.Proxy ?? '─')) -ForegroundColor Gray
    } else {
        Write-Host ('  {0,-16}{1}' -f 'pip', 'not found') -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '  [ System proxy / desktop apps ]' -ForegroundColor Cyan
    Write-Host ('  {0,-16}{1}' -f 'proxy enable', ($s.SystemProxy.ProxyEnable ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'proxy server', ($s.SystemProxy.ProxyServer ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'override', ($s.SystemProxy.ProxyOverride ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'pac', ($s.SystemProxy.AutoConfigURL ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'managed by', 'PSProfile System target when enabled') -ForegroundColor DarkGray
    if ($s.Warnings.Count -gt 0) {
        Write-Host ''
        Write-Host '  [ Warnings ]' -ForegroundColor Yellow
        foreach ($w in $s.Warnings) {
            Write-Host "  ! $w" -ForegroundColor Yellow
        }
    }
    if ($s.Recommendations.Count -gt 0) {
        Write-Host ''
        Write-Host '  [ Next actions ]' -ForegroundColor Green
        foreach ($r in $s.Recommendations) {
            Write-Host ('  - {0}' -f $r.Action) -ForegroundColor Gray
            if ($r.Command) { Write-Host ('    command: {0}' -f $r.Command) -ForegroundColor DarkGray }
        }
    }
    Write-Host $div -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-PSProfilePxDoctor {
    [CmdletBinding()]
    param([switch]$Json)

    $s = Get-PSProfilePxSnapshot
    if ($Json) {
        $localOk = if ($s.Runtime.ListenPort) { Test-PxPort $s.Runtime.ListenPort } else { $false }
        $s | Add-Member -NotePropertyName Doctor -NotePropertyValue ([pscustomobject]@{ LocalPortReachable = $localOk }) -Force
        $s | ConvertTo-Json -Depth 8
        return
    }

    Get-PSProfilePxState
    Write-Host '  [ Doctor ]' -ForegroundColor Cyan
    if ($s.Runtime.ListenPort) {
        $localOk = Test-PxPort $s.Runtime.ListenPort
        Write-Host ('  {0,-16}{1}' -f 'local port', $localOk) -ForegroundColor $(if ($localOk) { 'Green' } else { 'Yellow' })
    } else {
        Write-Host ('  {0,-16}{1}' -f 'local port', 'no listen port') -ForegroundColor Yellow
    }
    Write-Host ('  {0,-16}{1}' -f 'vpn detected', $s.Vpn.Detected) -ForegroundColor $(if ($s.Vpn.Detected) { 'Yellow' } else { 'Gray' })
    if ($s.Vpn.Evidence.Count -gt 0) {
        Write-Host ('  {0,-16}{1}' -f 'vpn evidence', ($s.Vpn.Evidence -join ', ')) -ForegroundColor DarkGray
    }
    Write-Host ('  {0,-16}{1}' -f 'sys proxy', ($s.SystemProxy.ProxyServer ?? '─')) -ForegroundColor Gray
    Write-Host ('  {0,-16}{1}' -f 'sys pac', ($s.SystemProxy.AutoConfigURL ?? '─')) -ForegroundColor Gray
    Write-Host ''
}

function Restart-PSProfilePxProxy { Stop-PSProfilePxProxy -StopProcess; Start-PSProfilePxProxy }
