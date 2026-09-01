#Requires -Version 7.0
# PSProfile v2.5.0 — 単一モジュール構成 / 起動を軽く保つ設計
# 方針: 標準コマンドだけで日常作業を回し、Proxy 系は初回呼び出しまで遅延ロード。
# Proxy 系の公開 API は px-on / px-off / px-state の 3 つだけ。
# px-on は Px 本体の起動ではなく、既に起動しているローカル Px へ env と Windows Internet Proxy を向ける操作。
# 実起動時間は端末依存 (企業 AV・OneDrive 等で変動)。自己計測は $env:PSPROFILE_BENCH=1。

$script:PSProfileVersion = '2.5.0'
$global:PSProfileVersion = $script:PSProfileVersion
$script:PSProfileUpdateBranch = 'main'
$script:PSProfileDefaultUpdateUrl = "https://raw.githubusercontent.com/yura-koizumi/ps-profile/$script:PSProfileUpdateBranch/install.ps1"

# ───────────────────────────────────────────────────────────── 起動時間計測
$script:_sw = [System.Diagnostics.Stopwatch]::StartNew()
$script:_bench = $env:PSPROFILE_BENCH -eq '1'
if ($script:_bench) {
  $script:_marks = [System.Collections.Generic.List[object]]::new()
  $script:_lap = [System.Diagnostics.Stopwatch]::StartNew()
}
function _mark {
  param([string]$Name)
  # $env:PSPROFILE_BENCH=1 の時だけ section 計測を記録する。
  # 通常起動では List への Add も避け、起動時の余計なコストを出さない。
  if ($script:_bench) {
    $script:_marks.Add(('  {0,-22} {1,5} ms' -f $Name, $script:_lap.ElapsedMilliseconds))
    $script:_lap.Restart()
  }
}

# ───────────────────────────────────────────────────────────── エンコーディング
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
_mark 'encoding'
# ───────────────────────────────────────────────────────────── PSReadLine
# Register-EngineEvent は端末によっては 3 秒以上かかるため使用しない。
# PSReadLine は対話体験に関わるが、失敗してもプロファイル全体を止めるほど重要ではないため catch で握る。
try {
  Set-PSReadLineOption -EditMode Windows -PredictionSource History -PredictionViewStyle ListView
  Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
  Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
  Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
} catch {}
_mark 'PSReadLine'
# ───────────────────────────────────────────────────────────── キャッシュディレクトリ
# cmdlet 不使用 (Join-Path 等の初回呼び出しは ~1.5s のオーバーヘッドを伴う)。
# Windows は %LOCALAPPDATA%\PSProfile、非 Windows は ~/.cache/PSProfile。
# 以前は LOCALAPPDATA + '\PSProfile' 固定だったため、非 Windows で \PSProfile のような不正寄りの
# パスになり得た。ここは .NET の Path.Combine で OS 別セパレーターに任せる。
if ($env:LOCALAPPDATA) {
  $script:_cacheDir = [IO.Path]::Combine($env:LOCALAPPDATA, 'PSProfile')
} else {
  $script:_cacheDir = [IO.Path]::Combine($HOME, '.cache', 'PSProfile')
}
# ───────────────────────────────────────────────────────────── 標準コマンド
function ls { Get-ChildItem @args }
function ll { Get-ChildItem -Force @args }
function lt {
  param(
    [string]$Path = '.',
    [int]$Depth = 2
  )
  Get-ChildItem -Path $Path -Recurse -Depth $Depth -Force @args
}
_mark 'commands'
# ───────────────────────────────────────────────────────────── Proxy lazy stubs
# Proxy.ps1 は px-* を初めて使うまで読み込まない (起動高速化のための遅延ロード)。
# ここにある Start/Stop/Get 関数は薄いスタブ。
# 実際の env / WinINET 操作は modules/PSProfile/Proxy.ps1 側に閉じ込める。
function Invoke-PSProfileProxy {
  param(
    [Parameter(Mandatory)][string]$Command,
    [object[]]$Arguments = @()
  )
  # Proxy.ps1 は毎回 dot-source する。
  # dot-source で定義される関数は「呼び出し元スコープ」に入り関数終了で消えるため、
  # 「初回だけ読み込んでフラグで使い回す」方式だと 2 回目以降の px-* で関数が見つからない
  # (px-on → px-state のような連続操作で再現)。再読込は関数定義のみで軽いので、
  # 起動高速化 (遅延ロード) を保ちつつ、確実性を優先して毎回ロードする。
  $proxyScript = [IO.Path]::Combine($PSScriptRoot, 'Proxy.ps1')
  if (-not [IO.File]::Exists($proxyScript)) {
    Write-Warning "Proxy.ps1 が見つかりません: $proxyScript"
    return
  }
  . $proxyScript
  & $Command @Arguments
}

function Start-PxProxy { Invoke-PSProfileProxy -Command 'Start-PSProfilePxProxy' -Arguments $args }
function Stop-PxProxy { Invoke-PSProfileProxy -Command 'Stop-PSProfilePxProxy' -Arguments $args }
function Get-PxState { Invoke-PSProfileProxy -Command 'Get-PSProfilePxState' -Arguments $args }

# CLI 表面は短い alias を主に使う。
# px-on は「Px を起動する」ではなく「ローカル Px に向けて proxy 設定を ON にする」。
# px-off は「Px を停止する」ではなく「proxy 設定を OFF にする」。
Set-Alias px-on    Start-PxProxy
Set-Alias px-off   Stop-PxProxy
Set-Alias px-state Get-PxState
_mark 'Proxy stubs'

# ───────────────────────────────────────────────────────────── Update
function Update-PSProfile {
  <#
    .SYNOPSIS
        PSProfile を GitHub から最新版に更新する。
    .DESCRIPTION
        GitHub raw 経由で install.ps1 を取得し -Update モードで実行する。
        $env:PSPROFILE_UPDATE_URL で取得元 URL を上書き可能。
    #>
  [CmdletBinding()]
  param(
    [string]$Branch = $script:PSProfileUpdateBranch
  )

  # 取得元: $env:PSPROFILE_UPDATE_URL があれば最優先 (fork 用)、なければ指定 Branch。
  $url = if ($env:PSPROFILE_UPDATE_URL) { $env:PSPROFILE_UPDATE_URL }
  else { "https://raw.githubusercontent.com/yura-koizumi/ps-profile/$Branch/install.ps1" }
  $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $separator = if ($url.Contains('?')) { '&' } else { '?' }
  $requestUrl = "$url${separator}cacheBust=$cacheBust"

  Write-Host "  PSProfile current: v$script:PSProfileVersion" -ForegroundColor DarkGray
  Write-Host "  PSProfile update:  $url" -ForegroundColor DarkGray
  try {
    $script = Invoke-RestMethod -Uri $requestUrl -Headers @{ 'Cache-Control' = 'no-cache' } -ErrorAction Stop
  } catch {
    Write-Warning "更新スクリプト取得失敗: $($_.Exception.Message)"
    return
  }
  & ([scriptblock]::Create($script)) -Update -Branch $Branch
}
Set-Alias psprofile-update Update-PSProfile
Set-Alias ps-update Update-PSProfile

function Get-PSProfileVersion {
  [pscustomobject]@{
    Version = $script:PSProfileVersion
    Branch = $script:PSProfileUpdateBranch
    ModulePath = $PSScriptRoot
    UpdateUrl = $script:PSProfileDefaultUpdateUrl
  }
}
Set-Alias psprofile-version Get-PSProfileVersion

# ───────────────────────────────────────────────────────────── git
# git の薄いラッパー 2 本のみ。関数定義だけなので遅延ロードは不要。
# 網羅的な git エイリアス群は v2.0 で意図的に外したので増やさない。

function Invoke-GitCommit {
  <#
  .SYNOPSIS
    コミットメッセージを入力して git commit を実行する。
  .EXAMPLE
    gcmt            # 対話入力
    gcmt "fix bug"  # メッセージを直接指定
  #>
  [CmdletBinding()]
  param(
    [Parameter(Position = 0)]
    [string]$Message
  )

  if (-not $Message) {
    $Message = Read-Host 'コミットメッセージ'
    if (-not $Message) { Write-Warning 'メッセージが空のため中止'; return }
  }
  & git commit -m $Message
}
Set-Alias gcmt Invoke-GitCommit

function Invoke-GitStash {
  <#
  .SYNOPSIS
    git stash のラッパー。引数なしで一覧を表示する。
  .EXAMPLE
    gst          # 一覧
    gst push     # 退避
    gst pop      # 復元
  #>
  if ($args.Count -eq 0) { & git stash list } else { & git stash @args }
}
Set-Alias gst Invoke-GitStash

# ───────────────────────────────────────────────────────────── phelp
$script:_sw.Stop()
$script:ProfileLoadMs = $script:_sw.ElapsedMilliseconds

function Show-ProfileHelp {
  [CmdletBinding()]
  param(
    [ValidateSet('All', 'Proxy', 'Git', 'Config', 'Examples')]
    [string]$Topic = 'All'
  )

  Write-Host ''
  Write-Host '  PSProfile' -NoNewline -ForegroundColor White
  Write-Host " v$script:PSProfileVersion" -NoNewline -ForegroundColor Yellow
  Write-Host ' ─── help ─────────────────────────────────────────' -ForegroundColor DarkGray
  Write-Host ''

  $sections = [ordered]@{}

  if ($Topic -in @('All', 'Proxy')) {
    $sections['Proxy'] = @(
      @{ c = 'px-on'; d = '社内用: env を設定し、Windows Internet Proxy を ProxyEnable=1 に戻して Px に向ける' }
      @{ c = 'px-off'; d = '社外用: 環境変数を解除し Windows Internet Proxy を無効化' }
      @{ c = 'px-state'; d = 'Px の待受 / 環境変数 / Windows Internet Proxy を表示' }
    )
  }

  if ($Topic -in @('All', 'Git')) {
    $sections['Git'] = @(
      @{ c = 'gcmt'; d = 'git commit -m。引数なしならメッセージを対話入力' }
      @{ c = 'gst'; d = 'git stash。引数なしで一覧、push / pop / drop をそのまま渡す' }
    )
  }

  if ($Topic -in @('All', 'Config')) {
    $sections['設定 (コード定数)'] = @(
      @{ c = 'proxy 値'; d = 'Proxy.ps1 の Get-PSProfilePxConfig (URL / port / NO_PROXY) を編集' }
      @{ c = '永続化'; d = 'px-on は User env にも書く。現セッションのみなら Proxy.ps1 の Test-PSProfilePersistProxyEnv を $false' }
    )
    $sections['安全設計'] = @(
      @{ c = 'px 本体'; d = 'px-on/off は px を起動停止しない。起動はログオン時タスク任せ' }
      @{ c = 'px-on'; d = 'Internet Proxy を disable から enable に戻すだけ。Px プロセス起動ではない' }
      @{ c = 'Windows Internet Proxy'; d = 'px-off は ProxyEnable=0 のみ。会社標準の ProxyServer 等は消さない' }
    )
  }

  if ($Topic -in @('All', 'Examples')) {
    $sections['よく使う流れ'] = @(
      @{ c = '社内LAN'; d = 'ログオン時タスクで Px 起動済み → px-on → 作業 → (社外へ移動) px-off' }
      @{ c = '外出先 / VPN'; d = 'プロキシ不要なら px-off。必要なら px-on' }
      @{ c = '状態確認'; d = 'px-state で env と Windows Internet Proxy を確認' }
    )
  }

  if ($Topic -eq 'All') {
    $sections['ファイル / 移動'] = @(
      @{ c = 'ls / ll / lt'; d = '標準の一覧補助 (Get-ChildItem ベース)' }
      @{ c = 'z <dir> / zi'; d = 'このプロファイルでは提供しない' }
    )
    $sections['プロファイル管理'] = @(
      @{ c = 'phelp'; d = 'このヘルプを表示' }
      @{ c = 'phelp -Topic Proxy'; d = 'Proxy 関連だけ表示' }
      @{ c = 'psprofile-version'; d = 'バージョン / 更新URL / 読み込み元パスを表示' }
      @{ c = 'psprofile-update'; d = 'GitHub raw から最新版に更新' }
      @{ c = 'ps-update'; d = 'psprofile-update の短縮 alias' }
    )
  }

  foreach ($title in $sections.Keys) {
    Write-Host '  ' -NoNewline
    Write-Host '❯ ' -NoNewline -ForegroundColor Yellow
    Write-Host $title -ForegroundColor Cyan
    $commandWidth = 20
    foreach ($i in $sections[$title]) {
      if ($i.c.Length -ge $commandWidth) {
        $commandWidth = $i.c.Length + 2
      }
    }
    $commandFormat = '{0,-' + $commandWidth + '}'
    foreach ($i in $sections[$title]) {
      Write-Host '    · ' -NoNewline -ForegroundColor DarkGray
      Write-Host ($commandFormat -f $i.c) -NoNewline -ForegroundColor White
      Write-Host $i.d -ForegroundColor DarkGray
    }
    Write-Host ''
  }
  Write-Host ('  ' + '─' * 50) -ForegroundColor DarkGray
  Write-Host '  まず迷ったら: px-state' -ForegroundColor DarkGray
  Write-Host ("  読み込み元: $PSScriptRoot") -ForegroundColor DarkGray
  Write-Host ("  プロファイル読み込み: $($script:ProfileLoadMs) ms") -ForegroundColor DarkGray
  Write-Host ''
}
Set-Alias phelp Show-ProfileHelp

# ───────────────────────────────────────────────────────────── 起動メッセージ
Write-Host '  カスタムコマンド一覧: ' -NoNewline -ForegroundColor DarkGray
Write-Host 'phelp' -ForegroundColor Yellow

if ($script:_bench) {
  _mark 'rest'
  Write-Host ''
  Write-Host '── PSProfile section timings ──' -ForegroundColor Yellow
  foreach ($m in $script:_marks) { Write-Host $m -ForegroundColor DarkGray }
  Write-Host ('  {0,-22} {1,5} ms' -f 'TOTAL', $script:_sw.ElapsedMilliseconds) -ForegroundColor Yellow
}

# 公開 API は最後に明示的に絞る。
Export-ModuleMember `
  -Function Show-ProfileHelp, Get-PSProfileVersion, Update-PSProfile, Start-PxProxy, Stop-PxProxy, Get-PxState, Invoke-GitCommit, Invoke-GitStash, ls, ll, lt `
  -Alias phelp, psprofile-version, psprofile-update, ps-update, px-on, px-off, px-state, gcmt, gst `
  -Variable ProfileLoadMs, PSProfileVersion
