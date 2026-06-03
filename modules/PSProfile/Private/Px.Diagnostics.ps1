#Requires -Version 7.0

function Get-PSProfileVpnState {
    $hits = @()
    if (Test-PSProfileWindows) {
        try {
            $hits += Get-NetAdapter -ErrorAction SilentlyContinue |
                Where-Object { $_.Status -eq 'Up' -and ($_.Name -match 'Akamai|VPN|EAA|Enterprise Application Access' -or $_.InterfaceDescription -match 'Akamai|VPN|EAA|Enterprise Application Access') } |
                ForEach-Object { $_.Name }
        } catch {}
    }
    try {
        $hits += Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.ProcessName -match 'akamai|vpn|eaa' } |
            Select-Object -ExpandProperty ProcessName -Unique
    } catch {}
    $hits = @($hits | Where-Object { $_ } | Select-Object -Unique)
    [pscustomobject]@{
        Detected = ($hits.Count -gt 0)
        Evidence = $hits
    }
}

function Get-PSProfileSystemProxyState {
    $state = [ordered]@{
        Platform = Get-PSProfilePlatform
        ProxyEnable = $null
        ProxyServer = $null
        AutoConfigURL = $null
        Raw = $null
    }
    if (Test-PSProfileWindows) {
        try {
            $p = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
            $state.ProxyEnable = $p.ProxyEnable
            $state.ProxyServer = $p.ProxyServer
            $state.AutoConfigURL = $p.AutoConfigURL
        } catch {}
    } elseif (Test-PSProfileMacOS) {
        try {
            $raw = (& scutil --proxy 2>$null) -join "`n"
            $state.Raw = $raw
            if ($raw -match 'HTTPEnable\s*:\s*(\d+)') { $state.ProxyEnable = [int]$Matches[1] }
            if ($raw -match 'HTTPProxy\s*:\s*(.+)') { $state.ProxyServer = $Matches[1].Trim() }
            if ($raw -match 'ProxyAutoConfigURLString\s*:\s*(.+)') { $state.AutoConfigURL = $Matches[1].Trim() }
        } catch {}
    }
    [pscustomobject]$state
}

function Get-PSProfilePxSnapshot {
    $runtime = Get-PSProfilePxRuntimeState
    $selectedIni = Get-PxIniPath -PreferExisting
    if (-not $selectedIni) { $selectedIni = Get-PxIniPath }
    $iniPort = Get-PxIniPort -IniPath $selectedIni
    $vs = Get-VSCodeUserSettingsPath
    $vsProxy = $null; $vsSupport = $null
    if ($vs -and (Test-Path $vs)) {
        try {
            $raw = Get-Content $vs -Raw -Encoding UTF8
            $vsProxy = Get-JsoncPropertyValue -Text $raw -PropertyName 'http.proxy'
            $vsSupport = Get-JsoncPropertyValue -Text $raw -PropertyName 'http.proxySupport'
        } catch {}
    }
    $snapshot = [pscustomobject]@{
        Platform = Get-PSProfilePlatform
        DeviceRole = Get-PSProfileDeviceRole
        ProxyMode = Get-PSProfileProxyMode
        ProxyTargets = @(Get-PSProfileProxyTargets)
        ExeCandidates = @(Get-PxExeCandidates)
        PxExe = Get-PxExe
        IniCandidates = @(Get-PxIniCandidates)
        SelectedIni = $selectedIni
        IniPort = $iniPort
        Runtime = $runtime
        EnvHttpProxy = $env:HTTP_PROXY
        EnvHttpsProxy = $env:HTTPS_PROXY
        EnvNoProxy = $env:NO_PROXY
        EnvLowerHttpProxy = $env:http_proxy
        VSCodeSettings = $vs
        VSCodeProxy = $vsProxy
        VSCodeProxySupport = $vsSupport
        VSCodeSyncEnabled = [bool](Test-PSProfileSyncVSCodeProxy)
        Git = Get-GitProxyState
        Npm = Get-NpmProxyState
        Pip = Get-PipProxyState
        SystemProxy = Get-PSProfileSystemProxyState
        Vpn = Get-PSProfileVpnState
    }
    $snapshot | Add-Member -NotePropertyName Warnings -NotePropertyValue @(Get-PSProfilePxWarnings -Snapshot $snapshot)
    $snapshot | Add-Member -NotePropertyName Recommendations -NotePropertyValue @(Get-PSProfilePxRecommendations -Snapshot $snapshot)
    return $snapshot
}

function Get-PSProfilePxWarnings {
    param([Parameter(Mandatory)]$Snapshot)
    $warnings = [System.Collections.Generic.List[string]]::new()
    $existingIni = @($Snapshot.IniCandidates | Where-Object { $_.Exists })
    if ($existingIni.Count -gt 1) {
        $null = $warnings.Add('px.ini が複数あります。実際に使われる設定を確認してください')
    }
    if ($Snapshot.IniPort -and $Snapshot.Runtime.ListenPort -and $Snapshot.IniPort -ne $Snapshot.Runtime.ListenPort) {
        $null = $warnings.Add("px.ini port ($($Snapshot.IniPort)) と listen port ($($Snapshot.Runtime.ListenPort)) が不一致です")
    }
    $envPort = Get-ProxyPortFromUrl $Snapshot.EnvHttpProxy
    if ($envPort -and $Snapshot.Runtime.ListenPort -and $envPort -ne $Snapshot.Runtime.ListenPort) {
        $null = $warnings.Add("HTTP_PROXY port ($envPort) と listen port ($($Snapshot.Runtime.ListenPort)) が不一致です")
    }
    if ($Snapshot.VSCodeProxy -and -not $Snapshot.VSCodeSyncEnabled) {
        $null = $warnings.Add('VSCode settings.json に http.proxy が残っています (Settings Sync 対象の可能性)')
    }
    if ($Snapshot.Git -and (($Snapshot.Git.HttpProxy -and $Snapshot.Git.HttpProxy -ne $Snapshot.EnvHttpProxy) -or ($Snapshot.Git.HttpsProxy -and $Snapshot.Git.HttpsProxy -ne $Snapshot.EnvHttpsProxy))) {
        $null = $warnings.Add('Git global proxy が現セッションの proxy と異なります')
    }
    if ($Snapshot.Npm -and (($Snapshot.Npm.Proxy -and $Snapshot.Npm.Proxy -ne $Snapshot.EnvHttpProxy) -or ($Snapshot.Npm.HttpsProxy -and $Snapshot.Npm.HttpsProxy -ne $Snapshot.EnvHttpsProxy))) {
        $null = $warnings.Add('npm proxy が現セッションの proxy と異なります')
    }
    if ($Snapshot.Pip -and $Snapshot.Pip.Proxy -and $Snapshot.Pip.Proxy -ne $Snapshot.EnvHttpProxy) {
        $null = $warnings.Add('pip global.proxy が現セッションの proxy と異なります')
    }
    if ($Snapshot.Vpn.Detected -and $Snapshot.EnvHttpProxy) {
        $null = $warnings.Add('VPN らしき接続が有効で、同時に HTTP_PROXY も設定されています')
    }
    if ($Snapshot.Runtime.Running -and -not $Snapshot.EnvHttpProxy) {
        $null = $warnings.Add('px は稼働中ですが、現ターミナルに HTTP_PROXY が設定されていません')
    }
    return @($warnings)
}

function Get-PSProfilePxRecommendations {
    param([Parameter(Mandatory)]$Snapshot)
    $items = [System.Collections.Generic.List[object]]::new()

    if ($Snapshot.ProxyMode -eq 'None') {
        $null = $items.Add([pscustomobject]@{
            Reason = 'ProxyMode is None'
            Action = 'px-on は使わず、必要なら user-config.ps1 で PSProfileProxyMode を変更してください'
            Command = 'phelp'
        })
    }
    if ($Snapshot.DeviceRole -eq 'Private' -and $Snapshot.EnvHttpProxy) {
        $null = $items.Add([pscustomobject]@{
            Reason = 'Private PC has HTTP_PROXY'
            Action = '私用PCで proxy が残っているため解除してください'
            Command = 'px-off'
        })
    }
    if ($Snapshot.Vpn.Detected -and $Snapshot.EnvHttpProxy) {
        $null = $items.Add([pscustomobject]@{
            Reason = 'VPN and HTTP_PROXY are both active'
            Action = 'Akamai VPN/外出先では proxy を外す運用なら解除してください'
            Command = 'px-off'
        })
    }
    if ($Snapshot.Runtime.Running -and -not $Snapshot.EnvHttpProxy) {
        $null = $items.Add([pscustomobject]@{
            Reason = 'Px is running without session env'
            Action = '社内LANでPxを使うなら現セッションへproxyを適用してください'
            Command = 'px-on'
        })
    }
    if ($Snapshot.VSCodeProxy -and -not $Snapshot.VSCodeSyncEnabled) {
        $null = $items.Add([pscustomobject]@{
            Reason = 'VSCode proxy remains while sync is disabled'
            Action = 'VSCode Settings Sync の影響を確認し、必要なら手動で http.proxy を消してください'
            Command = 'px-state'
        })
    }
    if ($Snapshot.IniPort -and $Snapshot.Runtime.ListenPort -and $Snapshot.IniPort -ne $Snapshot.Runtime.ListenPort) {
        $null = $items.Add([pscustomobject]@{
            Reason = 'px.ini port differs from listen port'
            Action = 'px.ini と実行中Pxのport差分を確認してください'
            Command = 'px-state -Edit'
        })
    }
    if ($Snapshot.Platform -ne 'Windows' -and -not (Get-PSProfileProxyUrl) -and $Snapshot.ProxyMode -ne 'None') {
        $null = $items.Add([pscustomobject]@{
            Reason = 'Non-Windows proxy URL is not configured'
            Action = 'macOS/Linuxでenv proxyを使う場合は PSProfileProxyUrl を設定してください'
            Command = '$global:PSProfileProxyUrl = ''http://proxy.example.com:8080'''
        })
    }
    return @($items)
}
