#Requires -Version 7.0
<#
.SYNOPSIS
    PSProfile v2.0 モジュールのケーステスト（Pester 不要・自前テストランナー）
.DESCRIPTION
    カバー範囲:
      Section 1  Proxy — VS Code settings.json 同期（JSONC 含む）
      Section 2  Proxy — Stop-PxProxy 環境変数クリア
      Section 3  Proxy — Start-PxProxy 環境変数セット + プロセス記録
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
# PSProfile モジュールを読み込み + Proxy.ps1 を強制ロード
# ──────────────────────────────────────────────────────────────────────────────
$ModulesRoot = Resolve-Path "$PSScriptRoot\..\modules"
Import-Module "$ModulesRoot\PSProfile" -Force *>$null
$script:proxyMod = Get-Module PSProfile | Select-Object -Last 1

# テスト用 AppData (VSCode settings.json) を用意
$script:proxyTestRoot   = script:New-TempDir
$script:proxyAppData    = Join-Path $script:proxyTestRoot 'AppData'
$script:proxySettingsDir = Join-Path $script:proxyAppData 'Code\User'
New-Item -ItemType Directory -Path $script:proxySettingsDir -Force | Out-Null

$script:originalAppData = $env:APPDATA
$env:APPDATA = $script:proxyAppData

# ──────────────────────────────────────────────────────────────────────────────
# Section 1: Proxy — VS Code settings.json 同期
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 1: Proxy — VS Code settings.json 同期' -ForegroundColor White

script:Context 'px-on / px-off が JSONC を保持しつつ http.proxy を更新する'

script:It 'JSONC のコメントと既存設定を残しつつ http.proxy を書く' {
    $settingsPath = Join-Path $script:proxySettingsDir 'settings.json'
    @'
{
  // keep this comment
  "editor.tabSize": 2,
  "http.proxySupport": "fallback"
}
'@ | Set-Content $settingsPath -Encoding UTF8

    $sb = $script:proxyMod.NewBoundScriptBlock({
            function Get-PxListenPort { 63602 }
            Start-PxProxy
        })
    & $sb *>$null

    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    script:Assert-Match $raw '"editor.tabSize": 2'
    script:Assert-Match $raw '"http.proxy": "http://127.0.0.1:63602"'
    script:Assert-Match $raw '"http.proxySupport": "override"'
    script:Assert-Match $raw 'keep this comment'
}

script:It 'px-off が http.proxy を空に戻す' {
    $settingsPath = Join-Path $script:proxySettingsDir 'settings.json'
    @'
{
  "http.proxy": "http://127.0.0.1:63602",
  "http.proxySupport": "override"
}
'@ | Set-Content $settingsPath -Encoding UTF8

    $sb = $script:proxyMod.NewBoundScriptBlock({
            function Get-PxProcessRecord { [pscustomobject]@{ ProcessId = 123; StartTimeUtc = '2026-05-20T00:00:00.0000000Z' } }
            function Get-Process {
                param([int]$Id)
                [pscustomobject]@{ Id = $Id; StartTime = [datetime]::Parse('2026-05-20T00:00:00Z') }
            }
            function Stop-Process {
                param([int]$Id)
                $script:stoppedPid = $Id
            }
            Stop-PxProxy
        })
    & $sb *>$null

    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    script:Assert-Match $raw '"http.proxy": ""'
    script:Assert-Match $raw '"http.proxySupport": "fallback"'
}

script:It '既存末尾プロパティにカンマが無い場合でも JSONC を壊さない' {
    $settingsPath = Join-Path $script:proxySettingsDir 'settings.json'
    @'
{
  "editor.tabSize": 2
}
'@ | Set-Content $settingsPath -Encoding UTF8

    $sb = $script:proxyMod.NewBoundScriptBlock({
            function Get-PxListenPort { 63602 }
            Start-PxProxy
        })
    & $sb *>$null

    $raw = Get-Content $settingsPath -Raw -Encoding UTF8
    script:Assert-Match $raw '"editor.tabSize": 2,'
    script:Assert-Match $raw '"http.proxy": "http://127.0.0.1:63602"'
    script:Assert-Match $raw '"http.proxySupport": "override"'
}

# ──────────────────────────────────────────────────────────────────────────────
# Section 2: Proxy — Stop-PxProxy 環境変数クリア
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 2: Proxy — Stop-PxProxy 環境変数クリア' -ForegroundColor White

script:Context 'px-off が環境変数を削除する'

script:It 'HTTP_PROXY を削除する' {
    $env:HTTP_PROXY = 'http://127.0.0.1:63602'
    $sb = $script:proxyMod.NewBoundScriptBlock({
            function Get-PxProcessRecord { $null }
            function Get-PxRunningProcess { $null }
            function Stop-Process { param([int]$Id) }
            Stop-PxProxy
        })
    & $sb *>$null
    script:Assert-Null $env:HTTP_PROXY
}
script:It 'HTTPS_PROXY を削除する' {
    $env:HTTPS_PROXY = 'http://127.0.0.1:63602'
    $sb = $script:proxyMod.NewBoundScriptBlock({
            function Get-PxProcessRecord { $null }
            function Get-PxRunningProcess { $null }
            function Stop-Process { param([int]$Id) }
            Stop-PxProxy
        })
    & $sb *>$null
    script:Assert-Null $env:HTTPS_PROXY
}
script:It 'NO_PROXY を削除する' {
    $env:NO_PROXY = 'localhost,127.0.0.1'
    $sb = $script:proxyMod.NewBoundScriptBlock({
            function Get-PxProcessRecord { $null }
            function Get-PxRunningProcess { $null }
            function Stop-Process { param([int]$Id) }
            Stop-PxProxy
        })
    & $sb *>$null
    script:Assert-Null $env:NO_PROXY
}

# ──────────────────────────────────────────────────────────────────────────────
# Section 3: Proxy — Start-PxProxy 環境変数セット + プロセス記録
# ──────────────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 3: Proxy — Start-PxProxy 環境変数セット' -ForegroundColor White

script:Context '環境変数とプロセス記録が作られる'

script:It 'HTTP_PROXY / HTTPS_PROXY / NO_PROXY を設定する' {
    Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:NO_PROXY -ErrorAction SilentlyContinue

    $sb = $script:proxyMod.NewBoundScriptBlock({
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
            Start-PxProxy
        })
    & $sb *>$null

    script:Assert-Equal $env:HTTP_PROXY 'http://127.0.0.1:63602'
    script:Assert-Equal $env:HTTPS_PROXY 'http://127.0.0.1:63602'
    script:Assert-Equal $env:NO_PROXY 'localhost,127.0.0.1'
}

script:It 'Set-PxProcessRecord が記録ファイルを作る' {
    $recordPath = Join-Path $script:proxyTestRoot 'px-process.json'
    $env:PSPROFILE_PX_RECORD_PATH = $recordPath
    Remove-Item $recordPath -ErrorAction SilentlyContinue

    $sb = $script:proxyMod.NewBoundScriptBlock({
            function Get-Process {
                param([int]$Id)
                [pscustomobject]@{ Id = $Id; StartTime = [datetime]::Parse('2026-05-20T00:00:00Z') }
            }
            Set-PxProcessRecord -ProcessId 321 -Port 63602
        })
    & $sb *>$null

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

    $sb = $script:proxyMod.NewBoundScriptBlock({
            Clear-PxProcessRecord
        })
    & $sb *>$null

    script:Assert-True (-not (Test-Path $recordPath)) '記録ファイル削除'
}

# ──────────────────────────────────────────────────────────────────────────────
# クリーンアップ
# ──────────────────────────────────────────────────────────────────────────────
$env:APPDATA = $script:originalAppData
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
