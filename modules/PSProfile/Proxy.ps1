#Requires -Version 7.0
# PSProfile Proxy — px-on / px-off / px-state の最小実装。
#
#   px-on  (Enable) : Px 用 User/Process 環境変数を設定し、
#                     Windows Internet Proxy を ProxyEnable=1 に戻す。
#   px-off (Disable): Px 用 User/Process 環境変数を削除し、
#                     Windows Internet Proxy を ProxyEnable=0 にする。
#   px-state (Status): Px の待受 / 環境変数 / Windows Internet Proxy を表示
#
# 重要:
# - px-on は Px 本体を起動しない。
# - px-on は Windows Internet Proxy を「disable から enable にする」操作に近い。
# - Px 本体の起動・常駐はログオン時タスクや手動起動が担当する。
# - このファイルは psm1 から遅延ロードされるため、通常の PowerShell 起動時には読み込まれない。
# - 設定は下の Get-PSProfilePxConfig (コード定数) を直接編集する。

function Test-PSProfileOnWindows {
    # PowerShell 7 では $IsWindows が自動変数として存在する。
    # Windows PowerShell 5.1 では未定義だが、このモジュールは #Requires -Version 7.0。
    # それでもテストや将来の互換性のため、未定義時は Windows 扱いに倒す。
    if ($null -ne $IsWindows) { return [bool]$IsWindows }
    return $true
}

function Get-PSProfilePxConfig {
    # ── 設定はここだけ。全端末共通の固定値 (px.ini と揃える) ──
    # ProxyUrl:
    #   CLI / PowerShell / WinINET アプリに見せるローカル Px の URL。
    #   社内プロキシの実ホスト名はここに書かない。実ホスト名は px.ini の server に置く。
    # NoProxy:
    #   ローカル宛・メタデータ宛はプロキシを通さない。小文字 no_proxy にも同じ値を書く。
    # Port:
    #   px-state が localhost の Listen を確認する時に使う。px.ini の port と一致させる。
    # RegPath:
    #   Windows Internet Options / WinINET のユーザー別設定。
    [pscustomobject]@{
        ProxyUrl = 'http://127.0.0.1:3128'
        NoProxy  = 'localhost,127.0.0.1,::1,169.254.169.254'
        Port     = 3128
        RegPath  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    }
}

# px-on で User スコープにも永続化するかをここで一元管理する。
# true:
#   Process env に加えて User env も書く。新しい PowerShell / GUI アプリが proxy を継承する。
# false:
#   現在の PowerShell プロセスだけに効かせる。テストではこの関数を上書きして User env 汚染を避ける。
function Test-PSProfilePersistProxyEnv { $true }

function Set-PSProfilePxEnv {
    param([Parameter(Mandatory)][string]$ProxyUrl, [Parameter(Mandatory)][string]$NoProxy)
    # 現セッション (Process) の即時反映。
    # 大文字は Windows / 多くの CLI 向け、小文字は Unix 由来ツールや一部ランタイム向け。
    # ALL_PROXY も入れるのは、HTTP_PROXY / HTTPS_PROXY を見ず ALL_PROXY だけを見るツールがあるため。
    $env:HTTP_PROXY = $env:HTTPS_PROXY = $env:ALL_PROXY = $ProxyUrl
    $env:NO_PROXY = $NoProxy
    $env:http_proxy = $env:https_proxy = $env:all_proxy = $ProxyUrl
    $env:no_proxy = $NoProxy
    # User スコープへの永続化。
    # [Environment]::SetEnvironmentVariable(..., 'User') は現在プロセスには即時反映しないため、
    # 上の $env:* 代入とセットで必要。新規ターミナルや WinINet 以外を見る GUI アプリが継承する。
    if (Test-PSProfilePersistProxyEnv) {
        foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY') {
            [Environment]::SetEnvironmentVariable($n, $ProxyUrl, 'User')
        }
        [Environment]::SetEnvironmentVariable('NO_PROXY', $NoProxy, 'User')
    }
}

function Clear-PSProfilePxEnv {
    # px-off は「このプロファイルが管理している proxy env を消す」処理。
    # Machine スコープは端末管理者や別ポリシーの領域なので触らない。
    # 小文字 env も消す。残すと一部 CLI だけ proxy を使い続け、状態が分かりにくくなる。
    foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy') {
        Remove-Item "Env:$n" -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable($n, $null, 'User')
    }
}

function Set-PSProfileInternetProxy {
    param([Parameter(Mandatory)][string]$ProxyUrl, [Parameter(Mandatory)][string]$RegPath)
    if (-not (Test-PSProfileOnWindows)) { return }
    # Windows Internet Proxy / WinINET 用。
    # px-on はここで ProxyEnable=1 にする。これは「無効化されていた Internet Proxy を有効化し直す」だけで、
    # Px プロセスを起動する処理ではない。ProxyServer にはローカル Px の URL を入れる。
    Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 1
    Set-ItemProperty -Path $RegPath -Name ProxyServer -Value $ProxyUrl
}

function Clear-PSProfileInternetProxy {
    param([Parameter(Mandatory)][string]$RegPath)
    if (-not (Test-PSProfileOnWindows)) { return }
    # px-off は ProxyEnable=0 だけを変更する。
    # ProxyServer / ProxyOverride / AutoConfigURL は会社標準や PAC の可能性があるため消さない。
    # これにより「社外では無効、社内では px-on で再度 enable」の切替だけを担当する。
    Set-ItemProperty -Path $RegPath -Name ProxyEnable -Value 0
}

function Get-PSProfilePxEnvTable {
    # 状態表示用。Machine スコープは表示しない。
    # v2.5 の管理対象は Process と User のみで、Machine env は変更もしないため。
    foreach ($n in 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY') {
        [pscustomobject]@{
            Name    = $n
            Process = [Environment]::GetEnvironmentVariable($n, 'Process')
            User    = [Environment]::GetEnvironmentVariable($n, 'User')
        }
    }
}

function Get-PSProfileInternetProxy {
    param([Parameter(Mandatory)][string]$RegPath)
    if (-not (Test-PSProfileOnWindows)) { return $null }
    # ErrorAction は SilentlyContinue。
    # 新規プロファイルや壊れたレジストリ状態でも px-state を落とさず、見える範囲だけ表示する。
    $i = Get-ItemProperty $RegPath -ErrorAction SilentlyContinue
    [pscustomobject]@{
        ProxyEnable   = $i.ProxyEnable
        ProxyServer   = $i.ProxyServer
        AutoConfigURL = $i.AutoConfigURL
    }
}

function Get-PSProfilePxListener {
    param([Parameter(Mandatory)][int]$Port)
    if (-not (Test-PSProfileOnWindows)) { return $null }
    # px-state のための観測だけ。ここで起動・停止・再起動はしない。
    # Listen が無ければ「Px 本体がまだ起動していない」と判断する材料にする。
    Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
}

function Start-PSProfilePxProxy {
    $c = Get-PSProfilePxConfig
    # px-on の実体。
    # 1) Process/User env をローカル Px に向ける。
    # 2) Windows では Internet Proxy を ProxyEnable=1 にし、ProxyServer をローカル Px に向ける。
    # 3) Px の Listen 状態を確認し、未起動なら警告する。
    # 注意: 3 は確認だけであり、ここで Px を起動しない。
    Set-PSProfilePxEnv -ProxyUrl $c.ProxyUrl -NoProxy $c.NoProxy
    Set-PSProfileInternetProxy -ProxyUrl $c.ProxyUrl -RegPath $c.RegPath
    Write-Host "px ON   $($c.ProxyUrl)" -ForegroundColor Green
    Write-Host "  NO_PROXY: $($c.NoProxy)" -ForegroundColor DarkGray
    if (Test-PSProfileOnWindows) { Write-Host '  Windows Internet Proxy: 有効' -ForegroundColor DarkGray }
    if (-not (Get-PSProfilePxListener -Port $c.Port)) {
        Write-Warning "px が 127.0.0.1:$($c.Port) で待受していません。ログオン時タスクで px が起動しているか確認してください。"
    }
}

function Stop-PSProfilePxProxy {
    $c = Get-PSProfilePxConfig
    # px-off の実体。
    # env を消し、Windows Internet Proxy は ProxyEnable=0 にする。
    # Px プロセス自体は停止しない。停止が必要な場合は SETUP.md の撤去手順で明示的に止める。
    Clear-PSProfilePxEnv
    Clear-PSProfileInternetProxy -RegPath $c.RegPath
    Write-Host 'px OFF  (環境変数を解除 / Windows Internet Proxy を無効化)' -ForegroundColor Yellow
}

function Get-PSProfilePxState {
    $c = Get-PSProfilePxConfig
    # 状態判定は「Px が Listen しているか」と「proxy env が入っているか」の組み合わせで見る。
    # Windows Internet Proxy は下で生値を表示するが、状態名は env と listener を中心にした簡易表示。
    $listener = Get-PSProfilePxListener -Port $c.Port
    $userProxy = [Environment]::GetEnvironmentVariable('HTTP_PROXY', 'User')
    $procProxy = $env:HTTP_PROXY

    $state =
    if ($listener -and ($userProxy -or $procProxy)) { '使用中' }
    elseif ($listener) { '待受のみ (env 未設定)' }
    elseif ($userProxy -or $procProxy) { '異常: env は有効だが px が未待受' }
    else { '停止' }

    Write-Host ''
    Write-Host "Px State: $state" -ForegroundColor White
    Write-Host ''
    if ($listener) {
        $pids = @($listener | Select-Object -ExpandProperty OwningProcess -Unique) -join ', '
        Write-Host "Px Listener: 127.0.0.1:$($c.Port) Listen (PID $pids)" -ForegroundColor Gray
    } else {
        Write-Host "Px Listener: 127.0.0.1:$($c.Port) は未待受" -ForegroundColor DarkGray
    }
    Write-Host ''
    Write-Host '=== Proxy Environment ===' -ForegroundColor Cyan
    Get-PSProfilePxEnvTable | Format-Table -AutoSize | Out-Host
    if (Test-PSProfileOnWindows) {
        Write-Host '=== Windows Internet Proxy ===' -ForegroundColor Cyan
        Get-PSProfileInternetProxy -RegPath $c.RegPath | Format-List | Out-Host
    }
    Write-Host ''
}
