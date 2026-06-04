#Requires -Version 7.0

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


function Get-PxRecordedPortIfReachable {
    $record = Get-PxProcessRecord
    if (-not $record -or -not $record.Port) { return $null }
    $port = [int]$record.Port
    if (Test-PxPort $port) { return $port }
    return $null
}

function Test-PxPort {
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
    if (-not (Test-PSProfileWindows)) { return $null }
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

function Get-PSProfilePxRuntimeState {
    $proc = Get-PxRunningProcess
    $record = Get-PxProcessRecord
    # Windows 起動直後の Get-NetTCPConnection / netstat は遅いことがあるため、
    # まず前回 px-on が記録した port の疎通だけで復元を試みる。
    $port = if ($proc) { Get-PxRecordedPortIfReachable } else { $null }
    if ($proc -and -not $port) { $port = Get-PxListenPort }
    $managed = $false
    if ($proc -and $record -and $record.ProcessId -eq $proc.Id) {
        if ($record.StartTimeUtc) {
            try { $managed = ($proc.StartTime.ToUniversalTime().ToString('o') -eq $record.StartTimeUtc) } catch {}
        } else {
            $managed = $true
        }
    }
    [pscustomobject]@{
        Process = $proc
        Running = [bool]$proc
        ProcessId = if ($proc) { $proc.Id } else { $null }
        ListenPort = $port
        Managed = $managed
        Record = $record
    }
}
