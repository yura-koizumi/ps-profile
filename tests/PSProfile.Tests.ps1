#Requires -Version 7.0
<#
.SYNOPSIS
    PSProfile v2.5 Proxy の最小テスト (Pester 不要・自前ランナー)
.DESCRIPTION
    Proxy.ps1 の px-on / px-off / px-state 最小実装を対象。
      Section 1  Config  — 既定値と「コード定数」方針
      Section 2  px-on   — 環境変数 (HTTP/HTTPS/ALL/NO + 小文字) を設定
      Section 3  px-off  — 環境変数を解除
    WinINET / listener は Test-PSProfileOnWindows をモックして切り離す。
    重要: テスト内の px-on は Px 起動を検証しない。env と Internet Proxy 切替の責務だけを見る。
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── テストランナー ────────────────────────────────────────────
$script:_pass = 0
$script:_fail = 0
function script:Context([string]$Name) { Write-Host "`n  [$Name]" -ForegroundColor Cyan }
function script:It {
    param([string]$Desc, [scriptblock]$Test)
    try { & $Test; $script:_pass++; Write-Host ('  ✓  {0}' -f $Desc) -ForegroundColor Green }
    catch { $script:_fail++; Write-Host ('  ✗  {0}' -f $Desc) -ForegroundColor Red; Write-Host ('     → {0}' -f $_.Exception.Message) -ForegroundColor DarkRed }
}
function script:Assert-Equal($Actual, $Expected, [string]$Because = '') {
    if ($Actual -ne $Expected) {
        $msg = "期待値 [$Expected]  実際値 [$Actual]"; if ($Because) { $msg += "  ($Because)" }; throw $msg
    }
}
function script:Assert-Null($Value, [string]$Because = '') {
    if ($null -ne $Value -and "$Value" -ne '') { throw ("null/空を期待しましたが [$Value]" + $(if ($Because) { "  ($Because)" })) }
}

# ── モジュール読み込み + Proxy.ps1 のパス解決 ──────────────────
$ModulesRoot = Resolve-Path "$PSScriptRoot\..\modules"
Import-Module "$ModulesRoot\PSProfile" -Force *>$null
$script:proxyScriptPath = (Resolve-Path "$ModulesRoot\PSProfile\Proxy.ps1").Path

# User env への書き込みは、各テストで Test-PSProfilePersistProxyEnv を $false に上書きして抑止する。
# これによりテスト実行後に利用者の実 User 環境変数を汚さない。

# ── Section 1: Config ─────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 1: Config — 既定値と上書き' -ForegroundColor White
script:Context '既定値'
script:It '既定は port=3128 / 127.0.0.1:3128 / NoProxy にループバック+メタデータ' {
    $sb = {
        param($P)
        . $P
        Remove-Variable -Scope Global -Name PSProfileProxyUrl, PSProfilePxPort, PSProfileNoProxy -ErrorAction SilentlyContinue
        Get-PSProfilePxConfig
    }
    $c = & $sb $script:proxyScriptPath
    script:Assert-Equal $c.Port 3128
    script:Assert-Equal $c.ProxyUrl 'http://127.0.0.1:3128'
    script:Assert-Equal $c.NoProxy 'localhost,127.0.0.1,::1,169.254.169.254'
}
script:Context '設定は定数 (global 上書きは効かない)'
script:It 'global を設定しても Get-PSProfilePxConfig は固定値を返す' {
    $sb = {
        param($P)
        . $P
        # v2.5 は user-config / global override を読まない。
        # proxy の実値は Proxy.ps1 の Get-PSProfilePxConfig に集約する。
        $global:PSProfileProxyUrl = 'http://proxy.example.internal:8080'
        $global:PSProfilePxPort = 9999
        $c = Get-PSProfilePxConfig
        Remove-Variable -Scope Global -Name PSProfileProxyUrl, PSProfilePxPort -ErrorAction SilentlyContinue
        $c
    }
    $c = & $sb $script:proxyScriptPath
    script:Assert-Equal $c.ProxyUrl 'http://127.0.0.1:3128'
    script:Assert-Equal $c.Port 3128
}

# ── Section 2: px-on ──────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 2: px-on — 環境変数を設定' -ForegroundColor White
script:Context 'px-on が大文字/小文字の proxy env を設定する'
script:It 'HTTP/HTTPS/ALL/NO_PROXY と小文字版を設定する' {
    Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:ALL_PROXY, Env:NO_PROXY, Env:http_proxy, Env:https_proxy, Env:all_proxy, Env:no_proxy -ErrorAction SilentlyContinue
    $sb = {
        param($P)
        . $P
        function Test-PSProfileOnWindows { $false }        # WinINET / listener を切り離す。px-on は Px 起動ではない。
        function Test-PSProfilePersistProxyEnv { $false }  # User env を書かない (Process のみ)
        Start-PSProfilePxProxy
    }
    & $sb $script:proxyScriptPath *>$null
    script:Assert-Equal $env:HTTP_PROXY  'http://127.0.0.1:3128'
    script:Assert-Equal $env:HTTPS_PROXY 'http://127.0.0.1:3128'
    script:Assert-Equal $env:ALL_PROXY   'http://127.0.0.1:3128'
    script:Assert-Equal $env:NO_PROXY    'localhost,127.0.0.1,::1,169.254.169.254'
    script:Assert-Equal $env:http_proxy  'http://127.0.0.1:3128'
    script:Assert-Equal $env:all_proxy   'http://127.0.0.1:3128'
}

# ── Section 3: px-off ─────────────────────────────────────────
Write-Host ''
Write-Host '━━ Section 3: px-off — 環境変数を解除' -ForegroundColor White
script:Context 'px-off が proxy env を削除する'
script:It 'HTTP/HTTPS/ALL/NO_PROXY と小文字版を削除する' {
    $env:HTTP_PROXY = $env:HTTPS_PROXY = $env:ALL_PROXY = 'http://127.0.0.1:3128'
    $env:NO_PROXY = 'localhost'
    $env:http_proxy = $env:https_proxy = $env:all_proxy = 'http://127.0.0.1:3128'
    $env:no_proxy = 'localhost'
    $sb = {
        param($P)
        . $P
        function Test-PSProfileOnWindows { $false }
        Stop-PSProfilePxProxy
    }
    & $sb $script:proxyScriptPath *>$null
    script:Assert-Null $env:HTTP_PROXY
    script:Assert-Null $env:HTTPS_PROXY
    script:Assert-Null $env:ALL_PROXY
    script:Assert-Null $env:NO_PROXY
    script:Assert-Null $env:http_proxy
    script:Assert-Null $env:no_proxy
}

# ── 結果 ──────────────────────────────────────────────────────
$total = $script:_pass + $script:_fail
Write-Host ''
Write-Host ('━' * 50) -ForegroundColor DarkGray
Write-Host (' テスト結果: {0} / {1} 件 PASS' -f $script:_pass, $total) -ForegroundColor $(if ($script:_fail -eq 0) { 'Green' } else { 'Red' })
if ($script:_fail -gt 0) { Write-Host (' FAIL: {0} 件' -f $script:_fail) -ForegroundColor Red }
Write-Host ''
exit $script:_fail
