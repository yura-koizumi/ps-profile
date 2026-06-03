#Requires -Version 7.0
<#
.SYNOPSIS
    PSProfile v2.0 モジュールのケーステスト（Pester 不要・自前テストランナー）
.DESCRIPTION
    カバー範囲:
      Section 1  Proxy — VS Code settings.json 同期は既定無効、opt-in 時のみ更新
      Section 2  Proxy — Stop-PxProxy 環境変数クリア
      Section 3  Proxy — Start-PxProxy 環境変数セット + 実listen port優先 + プロセス記録
      Section 4  Proxy — 安全確認 + JSON 出力
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ──────────────────────────────────────────────────────────────────────────────
# テストランナー
# ──────────────────────────────────────────────────────────────────────────────
$script:_pass = 0
$script:_fail = 0

function script:Context([string]$Name) {
    Write-Host "`n  [$Name]" -ForegroundColor Cyan
}

function script:It {
    param([string]$Desc, [scriptblock]$Test)
    try {
        & $Test
        $script:_pass++
        Write-Host ('  ✓  {0}' -f $Desc) -ForegroundColor Green
    } catch {
        $script:_fail++
        Write-Host ('  ✗  {0}' -f $Desc) -ForegroundColor Red
        Write-Host ('     → {0}' -f $_.Exception.Message) -ForegroundColor DarkRed
    }
}

function script:Assert-Equal($Actual, $Expected, [string]$Because = '') {
    if ($Actual -ne $Expected) {
        $msg = "期待値 [$Expected]  実際値 [$Actual]"
        if ($Because) { $msg += "  ($Because)" }
        throw $msg
    }
}
function script:Assert-NotNull($Value, [string]$Because = '') {
    if ($null -eq $Value -or "$Value" -eq '') {
        throw ('値が null または空です' + $(if ($Because) { "  ($Because)" }))
    }
}
function script:Assert-Null($Value, [string]$Because = '') {
    if ($null -ne $Value -and "$Value" -ne '') {
        throw ("null/空を期待しましたが [$Value] が返りました" + $(if ($Because) { "  ($Because)" }))
    }
}
function script:Assert-Match($Actual, [string]$Pattern, [string]$Because = '') {
    if ($Actual -notmatch $Pattern) {
        throw ("[$Actual] が /$Pattern/ にマッチしません" + $(if ($Because) { "  ($Because)" }))
    }
}
function script:Assert-True($Value, [string]$Because = '') {
    if (-not $Value) {
        throw ('true を期待しましたが false でした' + $(if ($Because) { "  ($Because)" }))
    }
}

function script:New-TempDir {
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}
function script:Remove-TempDir([string]$Path) {
    if ($Path -and (Test-Path $Path)) {
        Remove-Item $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# PSProfile モジュールを読み込み + Proxy.ps1 をテスト用に強制ロード
# ──────────────────────────────────────────────────────────────────────────────
$ModulesRoot = Resolve-Path "$PSScriptRoot\..\modules"
Import-Module "$ModulesRoot\PSProfile" -Force *>$null
$script:proxyMod = Get-Module PSProfile | Select-Object -Last 1
$script:proxyScriptPath = (Resolve-Path "$ModulesRoot\PSProfile\Proxy.ps1").Path

# テスト用 AppData (VSCode settings.json) を用意
$script:proxyTestRoot   = script:New-TempDir
$script:proxyAppData    = Join-Path $script:proxyTestRoot 'AppData'
$script:proxySettingsDir = Join-Path $script:proxyAppData 'Code\User'
New-Item -ItemType Directory -Path $script:proxySettingsDir -Force | Out-Null

$script:originalAppData = $env:APPDATA
$script:originalVSCodeSync = Get-Variable -Scope Global -Name PSProfileSyncVSCodeProxy -ErrorAction SilentlyContinue
$script:originalDeviceRole = Get-Variable -Scope Global -Name PSProfileDeviceRole -ErrorAction SilentlyContinue
$script:originalProxyMode = Get-Variable -Scope Global -Name PSProfileProxyMode -ErrorAction SilentlyContinue
$env:APPDATA = $script:proxyAppData
$global:PSProfileSyncVSCodeProxy = $false

# ──────────────────────────────────────────────────────────────────────────────
# Section 1: Proxy — VS Code settings.json 同期
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 1: Proxy — VS Code settings.json 同期 opt-in' -ForegroundColor White

script:Context '既定では VSCode settings.json を変更しない'

script:It 'px-on は既定では settings.json を変更しない' {
    $settingsPath = Join-Path $script:proxySettingsDir 'settings.json'
    @'
{
  // keep this comment
  "editor.tabSize": 2,
  "http.proxySupport": "fallback"
}
'@ | Set-Content $settingsPath -Encoding UTF8

    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PxListenPort { 63602 }
            Start-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null

    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    script:Assert-Match $raw '"editor.tabSize": 2'
    script:Assert-Match $raw '"http.proxySupport": "fallback"'
    script:Assert-Match $raw 'keep this comment'
}

script:Context 'opt-in 時だけ JSONC を保持しつつ http.proxy を更新する'

script:It 'opt-in 時は JSONC のコメントと既存設定を残しつつ http.proxy を書く' {
    $global:PSProfileSyncVSCodeProxy = $true
    $settingsPath = Join-Path $script:proxySettingsDir 'settings.json'
    @'
{
  // keep this comment
  "editor.tabSize": 2,
  "http.proxySupport": "fallback"
}
'@ | Set-Content $settingsPath -Encoding UTF8

    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PxListenPort { 63602 }
            Start-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null

    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    script:Assert-Match $raw '"editor.tabSize": 2'
    script:Assert-Match $raw '"http.proxy": "http://127.0.0.1:63602"'
    script:Assert-Match $raw '"http.proxySupport": "override"'
    script:Assert-Match $raw 'keep this comment'
    $global:PSProfileSyncVSCodeProxy = $false
}

script:It 'opt-in 時は px-off が http.proxy を空に戻す' {
    $global:PSProfileSyncVSCodeProxy = $true
    $settingsPath = Join-Path $script:proxySettingsDir 'settings.json'
    @'
{
  "http.proxy": "http://127.0.0.1:63602",
  "http.proxySupport": "override"
}
'@ | Set-Content $settingsPath -Encoding UTF8

    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PxProcessRecord { [pscustomobject]@{ ProcessId = 123; StartTimeUtc = '2026-05-20T00:00:00.0000000Z' } }
            function Get-Process {
                param([int]$Id)
                [pscustomobject]@{ Id = $Id; StartTime = [datetime]::Parse('2026-05-20T00:00:00Z') }
            }
            function Stop-Process {
                param([int]$Id)
                $script:stoppedPid = $Id
            }
            Stop-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null

    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    script:Assert-Match $raw '"http.proxy": ""'
    script:Assert-Match $raw '"http.proxySupport": "fallback"'
    $global:PSProfileSyncVSCodeProxy = $false
}

script:It 'opt-in 時は既存末尾プロパティにカンマが無い場合でも JSONC を壊さない' {
    $global:PSProfileSyncVSCodeProxy = $true
    $settingsPath = Join-Path $script:proxySettingsDir 'settings.json'
    @'
{
  "editor.tabSize": 2
}
'@ | Set-Content $settingsPath -Encoding UTF8

    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PxListenPort { 63602 }
            Start-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null

    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    script:Assert-Match $raw '"editor.tabSize": 2,'
    script:Assert-Match $raw '"http.proxy": "http://127.0.0.1:63602"'
    script:Assert-Match $raw '"http.proxySupport": "override"'
    $global:PSProfileSyncVSCodeProxy = $false
}

# ──────────────────────────────────────────────────────────────────────────────
# Section 2: Proxy — Stop-PxProxy 環境変数クリア
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 2: Proxy — Stop-PxProxy 環境変数クリア' -ForegroundColor White

script:Context 'px-off が環境変数を削除する'

script:It 'HTTP_PROXY を削除する' {
    $env:HTTP_PROXY = 'http://127.0.0.1:63602'
    $env:http_proxy = 'http://127.0.0.1:63602'
    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PxProcessRecord { $null }
            function Get-PxRunningProcess { $null }
            function Stop-Process { param([int]$Id) }
            Stop-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null
    script:Assert-Null $env:HTTP_PROXY
    script:Assert-Null $env:http_proxy
}
script:It 'HTTPS_PROXY を削除する' {
    $env:HTTPS_PROXY = 'http://127.0.0.1:63602'
    $env:https_proxy = 'http://127.0.0.1:63602'
    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PxProcessRecord { $null }
            function Get-PxRunningProcess { $null }
            function Stop-Process { param([int]$Id) }
            Stop-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null
    script:Assert-Null $env:HTTPS_PROXY
    script:Assert-Null $env:https_proxy
}
script:It 'NO_PROXY を削除する' {
    $env:NO_PROXY = 'localhost,127.0.0.1'
    $env:no_proxy = 'localhost,127.0.0.1'
    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PxProcessRecord { $null }
            function Get-PxRunningProcess { $null }
            function Stop-Process { param([int]$Id) }
            Stop-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null
    script:Assert-Null $env:NO_PROXY
    script:Assert-Null $env:no_proxy
}

# ──────────────────────────────────────────────────────────────────────────────
# Section 3: Proxy — Start-PxProxy 環境変数セット + プロセス記録
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 3: Proxy — Start-PxProxy 環境変数セット' -ForegroundColor White

script:Context '環境変数とプロセス記録が作られる'

script:It 'HTTP_PROXY / HTTPS_PROXY / NO_PROXY を設定する' {
    Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:NO_PROXY -ErrorAction SilentlyContinue

    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PxListenPort { $null }
            function Get-PxExe { 'C:\px\px.exe' }
            function Get-PxIniPath { param([switch]$PreferExisting) $null }
            function Get-PxIniPort { param([string]$IniPath) $null }
            function Test-PxPort { param([int]$Port) $true }
            function Start-Process {
                param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru)
                [pscustomobject]@{ Id = 321 }
            }
            function Get-Process {
                param([int]$Id)
                [pscustomobject]@{ Id = $Id; StartTime = [datetime]::Parse('2026-05-20T00:00:00Z') }
            }
            Start-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null
    script:Assert-Equal $env:HTTP_PROXY 'http://127.0.0.1:63602'
    script:Assert-Equal $env:HTTPS_PROXY 'http://127.0.0.1:63602'
    script:Assert-Equal $env:NO_PROXY 'localhost,127.0.0.1'
    script:Assert-Equal $env:http_proxy 'http://127.0.0.1:63602'
    script:Assert-Equal $env:https_proxy 'http://127.0.0.1:63602'
    script:Assert-Equal $env:no_proxy 'localhost,127.0.0.1'
}

script:It '起動後に確認した実 listen port を環境変数に使う' {
    Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:NO_PROXY, Env:http_proxy, Env:https_proxy, Env:no_proxy -ErrorAction SilentlyContinue

    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            $script:listenCalls = 0
            function Get-PxListenPort {
                $script:listenCalls++
                if ($script:listenCalls -eq 1) { return $null }
                return 63603
            }
            function Get-PxExe { 'C:\px\px.exe' }
            function Get-PxIniPath { param([switch]$PreferExisting) 'C:\px\px.ini' }
            function Get-PxIniPort { param([string]$IniPath) 63602 }
            function Test-PxPort { param([int]$Port) $true }
            function Start-Process {
                param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru)
                [pscustomobject]@{ Id = 654 }
            }
            function Get-Process {
                param([int]$Id)
                [pscustomobject]@{ Id = $Id; StartTime = [datetime]::Parse('2026-05-20T00:00:00Z') }
            }
            Start-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null

    script:Assert-Equal $env:HTTP_PROXY 'http://127.0.0.1:63603'
    script:Assert-Equal $env:HTTPS_PROXY 'http://127.0.0.1:63603'
}

script:It 'Set-PxProcessRecord が記録ファイルを作る' {
    $recordPath = Join-Path $script:proxyTestRoot 'px-process.json'
    $env:PSPROFILE_PX_RECORD_PATH = $recordPath
    Remove-Item $recordPath -ErrorAction SilentlyContinue

    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-Process {
                param([int]$Id)
                [pscustomobject]@{ Id = $Id; StartTime = [datetime]::Parse('2026-05-20T00:00:00Z') }
            }
            Set-PxProcessRecord -ProcessId 321 -Port 63602
        }
    & $sb $script:proxyScriptPath *>$null

    script:Assert-True (Test-Path $recordPath) '記録ファイル'
    $record = Get-Content $recordPath -Raw -Encoding UTF8 | ConvertFrom-Json
    script:Assert-Equal $record.ProcessId 321 '記録した PID'
    script:Assert-Equal $record.Port 63602 '記録した port'
}

script:It 'Clear-PxProcessRecord が記録ファイルを消す' {
    $recordPath = Join-Path $script:proxyTestRoot 'px-process.json'
    $env:PSPROFILE_PX_RECORD_PATH = $recordPath
    @'
{"ProcessId":321,"Port":63602,"StartTimeUtc":"2026-05-20T00:00:00.0000000Z"}
'@ | Set-Content $recordPath -Encoding UTF8

    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            Clear-PxProcessRecord
        }
    & $sb $script:proxyScriptPath *>$null
    script:Assert-True (-not (Test-Path $recordPath)) '記録ファイル削除'
}

# ──────────────────────────────────────────────────────────────────────────────
# Section 4: Proxy — 安全確認 + JSON 出力
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 4: Proxy — 安全確認 + JSON 出力' -ForegroundColor White

script:Context 'Private PC では px-on を拒否する'

script:It 'PSProfileDeviceRole=Private の場合は HTTP_PROXY を設定しない' {
    Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:NO_PROXY -ErrorAction SilentlyContinue
    $global:PSProfileDeviceRole = 'Private'
    $global:PSProfileProxyMode = 'WorkPx'
    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PxListenPort { 63602 }
            Start-PSProfilePxProxy
        }
    & $sb $script:proxyScriptPath *>$null
    script:Assert-Null $env:HTTP_PROXY
    Remove-Variable -Scope Global -Name PSProfileDeviceRole -ErrorAction SilentlyContinue
    Remove-Variable -Scope Global -Name PSProfileProxyMode -ErrorAction SilentlyContinue
}

script:Context 'px-state は JSON 出力できる'

script:It 'Get-PSProfilePxState -Json が snapshot JSON を返す' {
    $sb = {
            param([string]$ProxyScript)
            . $ProxyScript
            function Get-PSProfilePlatform { 'Windows' }
            function Get-PxExeCandidates { @() }
            function Get-PxExe { $null }
            function Get-PxIniCandidates { @() }
            function Get-PxIniPath { param([switch]$PreferExisting) $null }
            function Get-PxIniPort { param([string]$IniPath) $null }
            function Get-PSProfilePxRuntimeState {
                [pscustomobject]@{ Running = $false; ProcessId = $null; ListenPort = $null; Managed = $false }
            }
            function Get-VSCodeUserSettingsPath { $null }
            function Get-GitProxyState { $null }
            function Get-NpmProxyState { $null }
            function Get-PipProxyState { $null }
            function Get-PSProfileSystemProxyState {
                [pscustomobject]@{ Platform = 'Windows'; ProxyServer = $null; AutoConfigURL = $null }
            }
            function Get-PSProfileVpnState {
                [pscustomobject]@{ Detected = $false; Evidence = @() }
            }
            Get-PSProfilePxState -Json
        }
    $json = (& $sb $script:proxyScriptPath | Out-String)
    $obj = $json | ConvertFrom-Json
    script:Assert-Equal $obj.Platform 'Windows'
    script:Assert-True ($obj.PSObject.Properties.Name -contains 'Warnings') 'Warnings property'
    script:Assert-True ($obj.PSObject.Properties.Name -contains 'Recommendations') 'Recommendations property'
}

# ──────────────────────────────────────────────────────────────────────────────
# クリーンアップ
# ──────────────────────────────────────────────────────────────────────────────
$env:APPDATA = $script:originalAppData
if ($script:originalVSCodeSync) {
    $global:PSProfileSyncVSCodeProxy = $script:originalVSCodeSync.Value
} else {
    Remove-Variable -Scope Global -Name PSProfileSyncVSCodeProxy -ErrorAction SilentlyContinue
}
if ($script:originalDeviceRole) {
    $global:PSProfileDeviceRole = $script:originalDeviceRole.Value
} else {
    Remove-Variable -Scope Global -Name PSProfileDeviceRole -ErrorAction SilentlyContinue
}
if ($script:originalProxyMode) {
    $global:PSProfileProxyMode = $script:originalProxyMode.Value
} else {
    Remove-Variable -Scope Global -Name PSProfileProxyMode -ErrorAction SilentlyContinue
}
script:Remove-TempDir $script:proxyTestRoot

# ──────────────────────────────────────────────────────────────────────────────
# 結果サマリー
# ──────────────────────────────────────────────────────────────────────────────
$total = $script:_pass + $script:_fail
Write-Host ''
Write-Host ('━' * 50) -ForegroundColor DarkGray
$color = if ($script:_fail -eq 0) { 'Green' } else { 'Red' }
Write-Host (' テスト結果: {0} / {1} 件 PASS' -f $script:_pass, $total) -ForegroundColor $color
if ($script:_fail -gt 0) {
    Write-Host (' FAIL: {0} 件' -f $script:_fail) -ForegroundColor Red
}
Write-Host ''

exit $script:_fail
