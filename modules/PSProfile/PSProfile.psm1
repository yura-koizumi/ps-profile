#Requires -Version 7.0
# PSProfile v2.1.0 — 単一モジュール構成 / 起動時間最優先
# 目標: コールド起動でも 1 秒未満。Proxy 系は初回呼び出しまで実体ロード遅延。

$script:PSProfileVersion = '2.1.0'
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
# Set-PSReadLineOption はモジュール既ロード後だと ~30ms 程度。
try {
  Set-PSReadLineOption -EditMode Windows -PredictionSource History -PredictionViewStyle ListView
  Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
  Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
  Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
} catch {}
_mark 'PSReadLine'
# ───────────────────────────────────────────────────────────── キャッシュディレクトリ
# cmdlet 不使用 (Join-Path 等の初回呼び出しは ~1.5s のオーバーヘッドを伴う)
$script:_cacheDir = $env:LOCALAPPDATA + '\PSProfile'
$script:_initCacheDir = $script:_cacheDir + '\init-cache'
$script:_exeCacheFile = $script:_cacheDir + '\exe-cache.ps1'  # .ps1 (hashtable) で読み込みを高速化

# ───────────────────────────────────────────────────────────── 高速ツール探索 (キャッシュ付き)
# Get-Command は ModuleAnalysisCache の影響で初回 ~50ms/件、
# PATH 全走査も OneDrive 等で 27 dirs × 4 exts × 4 tools = 約 1600ms かかる。
# → 解決済みパスを exe-cache.json に保存し、$env:PATH のハッシュが一致する限り再利用する。
$script:_pathExt = @('.exe', '.cmd', '.bat', '.com')

function _Find-Exe-Raw {
  param([string]$Name)
  foreach ($dir in ($env:PATH -split ';')) {
    if (-not $dir) { continue }
    $base = $dir.TrimEnd('\') + '\' + $Name
    foreach ($ext in $script:_pathExt) {
      $p = $base + $ext
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
  [IO.File]::WriteAllText($script:_exeCacheFile, $sb.ToString(), [Text.UTF8Encoding]::new($false))
  return $result
}

# ───────────────────────────────────────────────────────────── 外部ツール init キャッシュ

function _Use-CachedInit {
  param(
    [Parameter(Mandatory)][string]$Tool,
    [Parameter(Mandatory)][string]$ExePath,
    [Parameter(Mandatory)][scriptblock]$Generate
  )
  if (-not [IO.Directory]::Exists($script:_initCacheDir)) {
    [IO.Directory]::CreateDirectory($script:_initCacheDir) | Out-Null
  }
  $cache = $script:_initCacheDir + '\' + $Tool + '.ps1'
  # キャッシュが存在すれば即利用 (Get-Item LastWriteTimeUtc 比較は OneDrive 配下で重い)。
  # ツールアップグレード時は exe-cache.ps1 を消すと init キャッシュも自動再生成。
  if (-not [IO.File]::Exists($cache)) {
    try {
      $content = (& $Generate) -join "`n"
      [IO.File]::WriteAllText($cache, $content, [Text.UTF8Encoding]::new($false))
    } catch {
      Write-Warning ("{0} init キャッシュ生成失敗: {1}" -f $Tool, $_.Exception.Message)
      return
    }
  }
  . $cache
}

# ───────────────────────────────────────────────────────────── 1回限りツール検出
$script:_exe = _Resolve-Exes -Tools @('starship', 'zoxide', 'eza', 'mise')
_mark 'exe-cache'
# ───────────────────────────────────────────────────────────── starship
if ($script:_exe.starship) {
  $env:STARSHIP_CONFIG = $PSScriptRoot + '\starship.toml'
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
# ───────────────────────────────────────────────────────────── mise (opt-in)
# 起動時間を ~1.5s 消費するため既定では無効。user-config.ps1 で
# $global:PSProfileEnableMise = $true としたときのみ有効化する。
if ($script:_exe.mise -and $global:PSProfileEnableMise) {
  _Use-CachedInit -Tool 'mise' -ExePath $script:_exe.mise -Generate {
    & $script:_exe.mise activate pwsh
  }
}

# ───────────────────────────────────────────────────────────── Proxy lazy stubs
# Load Proxy.ps1 only when a px-* command is called.
function Invoke-PSProfileProxy {
  param(
    [Parameter(Mandatory)][string]$Command,
    [object[]]$Arguments = @()
  )
  $proxyScript = $PSScriptRoot + '\Proxy.ps1'
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
function Invoke-PxDoctor { Invoke-PSProfileProxy -Command 'Invoke-PSProfilePxDoctor' -Arguments $args }
function Restart-PxProxy { Invoke-PSProfileProxy -Command 'Restart-PSProfilePxProxy' -Arguments $args }

Set-Alias px-on      Start-PxProxy
Set-Alias px-off     Stop-PxProxy
Set-Alias px-state   Get-PxState
Set-Alias px-doctor  Invoke-PxDoctor
Set-Alias px-restart Restart-PxProxy
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
    [switch]$Prerelease,
    [string]$Branch = $script:PSProfileUpdateBranch
  )

  $url = if ($env:PSPROFILE_UPDATE_URL) { $env:PSPROFILE_UPDATE_URL }
  elseif ($Prerelease) { "https://raw.githubusercontent.com/yura-koizumi/ps-profile/$Branch/install.ps1" }
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
    $sections['Proxy: 状態確認'] = @(
      @{ c = 'px-state'; d = 'Px / env / VSCode / Git / npm / pip の現在値を表示' }
      @{ c = 'px-state -Json'; d = '状態を JSON で出力。ログ保存や比較に使う' }
      @{ c = 'px-state -Edit'; d = '検出した px.ini をエディタで開く' }
      @{ c = 'px-doctor'; d = 'VPN / system proxy / PAC / local port / 推奨アクションを診断' }
      @{ c = 'px-doctor -Json'; d = '診断結果と推奨アクションを JSON で出力' }
    )
    $sections['Proxy: 切り替え'] = @(
      @{ c = 'px-on'; d = '職場LANなど proxy が必要な時だけ、現セッションへ env proxy を設定' }
      @{ c = 'px-off'; d = '現セッションの proxy env を解除し、管理中の Px を停止' }
      @{ c = 'px-off -KeepProcess'; d = 'env だけ解除し、Px プロセスは残す' }
      @{ c = 'px-restart'; d = 'Px と env proxy を再読み込み' }
    )
  }

  if ($Topic -in @('All', 'Config')) {
    $sections['端末固有設定'] = @(
      @{ c = '~/.psprofile/user-config.ps1'; d = '職場PC / 私用PC / macOS など端末ごとの設定置き場' }
      @{ c = '$global:PSProfileDeviceRole'; d = 'Work / Private。Private では px-on を安全側で拒否' }
      @{ c = '$global:PSProfileProxyMode'; d = 'WorkPx / Manual / None。私用PCは None が安全' }
      @{ c = '$global:PSProfileProxyUrl'; d = 'macOS / Manual モードで使う proxy URL' }
      @{ c = '$global:PSProfileSyncVSCodeProxy'; d = 'true の時だけ VSCode settings.json を連動' }
      @{ c = '$global:PSProfileNoProxy'; d = 'NO_PROXY / no_proxy の値を上書き' }
    )
    $sections['安全設計'] = @(
      @{ c = 'VSCode'; d = '既定では settings.json を変更しない。Settings Sync 事故を避ける' }
      @{ c = 'Git / npm / pip'; d = '既定では global proxy を変更しない。px-state / px-doctor で確認する' }
      @{ c = 'Windows'; d = 'Px を使う。system proxy / PAC / VPN 状態は px-doctor で確認' }
      @{ c = 'macOS'; d = 'Px 起動はしない。必要なら PSProfileProxyUrl を明示して env だけ設定' }
    )
  }

  if ($Topic -in @('All', 'Examples')) {
    $sections['よく使う流れ'] = @(
      @{ c = '社内LAN'; d = 'px-doctor → px-on → 作業 → px-off' }
      @{ c = 'Akamai VPN / 外出先'; d = 'px-off → px-doctor で proxy 残りを確認' }
      @{ c = '私用PC'; d = 'PSProfileDeviceRole=Private / PSProfileProxyMode=None を設定' }
      @{ c = 'Git push 失敗時'; d = 'px-state で Git global proxy と env proxy のズレを確認' }
      @{ c = '詳細だけ見る'; d = 'phelp -Topic Proxy / phelp -Topic Config / phelp -Topic Examples' }
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
  Write-Host '  まず迷ったら: px-doctor' -ForegroundColor DarkGray
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
