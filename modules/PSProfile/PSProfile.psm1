#Requires -Version 7.0
# PSProfile v2.5.0 — 単一モジュール構成 / 起動を軽く保つ設計
# 方針: 外部ツール init / exe 探索をキャッシュし、Proxy 系は初回呼び出しまで遅延ロード。
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
$script:_initCacheDir = [IO.Path]::Combine($script:_cacheDir, 'init-cache')
$script:_exeCacheFile = [IO.Path]::Combine($script:_cacheDir, 'exe-cache.ps1')  # .ps1 (hashtable) で読み込みを高速化

# ───────────────────────────────────────────────────────────── 高速ツール探索 (キャッシュ付き)
# Get-Command は ModuleAnalysisCache の影響で初回 ~50ms/件、
# PATH 全走査も OneDrive 等で 27 dirs × 4 exts × 4 tools = 約 1600ms かかる。
# → 解決済みパスを exe-cache.ps1 に保存し、$env:PATH の文字列が一致する限り再利用する。
if ($env:LOCALAPPDATA) {
  $script:_pathExt = @('.exe', '.cmd', '.bat', '.com')
} else {
  # Linux/macOS は拡張子なしの実行ファイルが基本。Windows 拡張子も一応見る。
  $script:_pathExt = @('', '.exe', '.cmd', '.bat', '.com')
}
$script:_pathSeparator = [IO.Path]::PathSeparator

function _Find-Exe-Raw {
  param([string]$Name)
  # Get-Command は便利だが初回コストが大きいので、PATH 文字列を直接走査する。
  # PATHEXT 相当は $script:_pathExt に固定し、PowerShell のコマンド探索ロジック全体は再現しない。
  # ここで探す対象は starship/zoxide/eza の exe/cmd/bat/com だけなので、この単純化で十分。
  foreach ($dir in ($env:PATH -split [regex]::Escape([string]$script:_pathSeparator))) {
    if (-not $dir) { continue }
    $trimmed = $dir.TrimEnd('\', '/')
    foreach ($ext in $script:_pathExt) {
      $p = [IO.Path]::Combine($trimmed, $Name + $ext)
      if ([IO.File]::Exists($p)) { return $p }
    }
  }
  return ''
}

function _Resolve-Exes {
  param([string[]]$Tools)
  # PATH 変更検知: 文字列リテラルとして保存 (MD5 は System.Security.Cryptography 初回 JIT で
  # ~300ms かかるため排除)。PATH は通常 1-4KB で I/O 上問題なし。
  $pathSig = $env:PATH -replace "'", "''"

  # .ps1 (hashtable literal) は ConvertFrom-Json より 1 桁速い
  if ([IO.File]::Exists($script:_exeCacheFile)) {
    try {
      $cached = . $script:_exeCacheFile
      # キャッシュは PATH 文字列が完全一致した時だけ信用する。
      # PATH の一部だけ変わった場合に古い exe を掴むと挙動が分かりにくいため、部分一致や時刻判定はしない。
      if ($cached.pathSig -eq $env:PATH) {
        $result = @{}
        $missing = $false
        foreach ($t in $Tools) {
          if (-not $cached.exes.ContainsKey($t)) { $missing = $true; break }
          $p = $cached.exes[$t]
          $result[$t] = if ($p) { $p } else { $null }
        }
        if (-not $missing) { return $result }
      }
    } catch { } # 破損キャッシュは無視
  }

  # 再スキャン
  if (-not [IO.Directory]::Exists($script:_cacheDir)) {
    [IO.Directory]::CreateDirectory($script:_cacheDir) | Out-Null
  }
  $result = @{}
  $exes = @{}
  foreach ($t in $Tools) {
    # 見つからないツールも空文字としてキャッシュする。
    # 毎回「無いもの」を PATH 全走査しないため。
    $p = _Find-Exe-Raw $t
    $result[$t] = if ($p) { $p } else { $null }
    $exes[$t] = $p
  }
  # ps1 hashtable literal として書き出す
  $sb = [System.Text.StringBuilder]::new()
  [void]$sb.AppendLine("@{")
  [void]$sb.AppendLine("  pathSig = '$pathSig'")
  [void]$sb.AppendLine("  exes = @{")
  foreach ($k in $exes.Keys) {
    $v = ($exes[$k] -replace "'", "''")
    [void]$sb.AppendLine("    '$k' = '$v'")
  }
  [void]$sb.AppendLine("  }")
  [void]$sb.AppendLine("}")
  try {
    $tmp = $script:_exeCacheFile + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    [IO.File]::WriteAllText($tmp, $sb.ToString(), [Text.UTF8Encoding]::new($false))
    # overwrite つき Move は同一ボリュームでアトミック (Copy は途中状態が見える)
    [IO.File]::Move($tmp, $script:_exeCacheFile, $true)
  } catch {
    # 他の PowerShell 起動直後と競合しても、キャッシュ更新失敗で起動自体は止めない。
  } finally {
    if ($tmp -and [IO.File]::Exists($tmp)) {
      try { [IO.File]::Delete($tmp) } catch {}
    }
  }
  return $result
}

# ───────────────────────────────────────────────────────────── 外部ツール init キャッシュ

function _Use-CachedInit {
  param(
    [Parameter(Mandatory)][string]$Tool,
    [Parameter(Mandatory)][string]$ExePath,
    [Parameter(Mandatory)][scriptblock]$Generate
  )
  function _Invoke-Init-Direct {
    # キャッシュを書けない環境でもプロファイル起動を止めないための退避経路。
    # 速度は落ちるが、starship/zoxide が使えるならその場で init コードを評価する。
    try {
      Invoke-Expression ((& $Generate) -join "`n")
    } catch {
      Write-Warning ("{0} init 直接実行失敗: {1}" -f $Tool, $_.Exception.Message)
    }
  }

  if (-not [IO.Directory]::Exists($script:_initCacheDir)) {
    try {
      [IO.Directory]::CreateDirectory($script:_initCacheDir) | Out-Null
    } catch {
      # キャッシュは性能最適化。権限差や削除直後の競合で作れなくても起動ノイズにしない。
      _Invoke-Init-Direct
      return
    }
  }
  $cache = [IO.Path]::Combine($script:_initCacheDir, $Tool + '.ps1')
  $stampFile = $cache + '.stamp'
  # exe のタイムスタンプ + サイズを指紋にして、ツール更新時はキャッシュを作り直す。
  # ([IO.FileInfo] のメタデータ参照は cmdlet より速く、init を実行するより桁違いに軽い)
  $stamp = ''
  try {
    $fi = [IO.FileInfo]::new($ExePath)
    $stamp = '' + $fi.LastWriteTimeUtc.Ticks + ':' + $fi.Length
  } catch {}
  $fresh = $false
  if ($stamp -and [IO.File]::Exists($cache) -and [IO.File]::Exists($stampFile)) {
    try { $fresh = ([IO.File]::ReadAllText($stampFile) -eq $stamp) } catch {}
  }
  if (-not $fresh) {
    try {
      # starship/zoxide の init は文字列の PowerShell コードを返す。
      # それをキャッシュファイルに保存して dot-source することで、毎回外部プロセスを起動しない。
      $content = (& $Generate) -join "`n"
      [IO.File]::WriteAllText($cache, $content, [Text.UTF8Encoding]::new($false))
      if ($stamp) { [IO.File]::WriteAllText($stampFile, $stamp, [Text.UTF8Encoding]::new($false)) }
    } catch {
      # 書き込み失敗は直接 init に落とす。profile 起動時の warning は実害よりノイズが大きい。
      if (-not [IO.File]::Exists($cache)) {
        _Invoke-Init-Direct
        return
      }
    }
  }
  . $cache
}

# ───────────────────────────────────────────────────────────── 1回限りツール検出
$script:_exe = _Resolve-Exes -Tools @('starship', 'zoxide', 'eza')
_mark 'exe-cache'
# ───────────────────────────────────────────────────────────── starship
if ($script:_exe.starship) {
  $env:STARSHIP_CONFIG = [IO.Path]::Combine($PSScriptRoot, 'starship.toml')
  _Use-CachedInit -Tool 'starship' -ExePath $script:_exe.starship -Generate {
    & $script:_exe.starship init powershell --print-full-init
  }
}
_mark 'starship'
# ───────────────────────────────────────────────────────────── zoxide
if ($script:_exe.zoxide) {
  _Use-CachedInit -Tool 'zoxide' -ExePath $script:_exe.zoxide -Generate {
    & $script:_exe.zoxide init powershell
  }
}
_mark 'zoxide'
# ───────────────────────────────────────────────────────────── eza (ls/ll/lt)
if ($script:_exe.eza) {
  Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
  function ls { eza --icons --group-directories-first @args }
  function ll { eza -la --icons --group-directories-first --git @args }
  function lt { eza --tree --level=2 --icons --group-directories-first @args }
}
_mark 'eza'
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

# ───────────────────────────────────────────────────────────── phelp
$script:_sw.Stop()
$script:ProfileLoadMs = $script:_sw.ElapsedMilliseconds

function Show-ProfileHelp {
  [CmdletBinding()]
  param(
    [ValidateSet('All', 'Proxy', 'Config', 'Examples')]
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
      @{ c = 'ls / ll / lt'; d = 'eza ベースの一覧 (eza がある時だけ)' }
      @{ c = 'z <dir> / zi'; d = 'zoxide スマート cd (zoxide がある時だけ)' }
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

# starship / zoxide の init は module scope に補助関数を作る。
# 便利な内部関数まで外へ export されると公開 API が膨らむため、最後に明示的に絞る。
Export-ModuleMember `
  -Function Show-ProfileHelp, Get-PSProfileVersion, Update-PSProfile, Start-PxProxy, Stop-PxProxy, Get-PxState, ls, ll, lt `
  -Alias phelp, psprofile-version, psprofile-update, ps-update, px-on, px-off, px-state `
  -Variable ProfileLoadMs, PSProfileVersion
