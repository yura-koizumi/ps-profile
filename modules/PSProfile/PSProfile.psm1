#Requires -Version 7.0
# PSProfile v2.5.1 — 単一モジュール構成 / 起動時間最優先
# 目標: コールド起動でも 1 秒未満。Proxy 系は初回呼び出しまで実体ロード遅延。

$script:PSProfileVersion = '2.5.1'
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
# 起動速度を優先したい端末では user-config.ps1 で
# $global:PSProfileSkipPSReadLine = $true を設定すると完全にスキップできる。
if ($global:PSProfileSkipPSReadLine -ne $true) {
  try {
    Set-PSReadLineOption -EditMode Windows -PredictionSource History -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
  } catch {}
}
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

# ───────────────────────────────────────────────────────────── 外部ツール lazy 初期化
# 起動速度優先: PATH 全走査と init スクリプト dot-source を起動時にまとめて行わない。
# - starship は見た目用途のため opt-in
# - zoxide は初回 z / zi 実行時に初期化
# - eza は ls / ll / lt 実行時に解決
$script:_toolExe = @{}
function _Get-ToolExe {
  param([Parameter(Mandatory)][string]$Name)
  if ($script:_toolExe.ContainsKey($Name)) { return $script:_toolExe[$Name] }
  $p = _Find-Exe-Raw $Name
  $script:_toolExe[$Name] = if ($p) { $p } else { $null }
  return $script:_toolExe[$Name]
}
_mark 'tool lazy stubs'

# ───────────────────────────────────────────────────────────── starship (opt-in)
# user-config.ps1 で $global:PSProfileEnableStarship = $true の場合だけ起動時に有効化。
# 既定では無効にして Windows 起動直後の PowerShell 起動を軽くする。
if ($global:PSProfileEnableStarship -eq $true) {
  $starship = _Get-ToolExe 'starship'
  if ($starship) {
    $env:STARSHIP_CONFIG = $PSScriptRoot + '\starship.toml'
    _Use-CachedInit -Tool 'starship' -ExePath $starship -Generate {
      & $starship init powershell --print-full-init
    }
  }
}
_mark 'starship opt-in'

# ───────────────────────────────────────────────────────────── zoxide (lazy)
$script:_zoxideReady = $false
function _Ensure-Zoxide {
  if ($script:_zoxideReady) { return $true }
  $zoxide = _Get-ToolExe 'zoxide'
  if (-not $zoxide) { return $false }
  _Use-CachedInit -Tool 'zoxide' -ExePath $zoxide -Generate {
    & $zoxide init powershell
  }
  $script:_zoxideReady = $true
  return $true
}
function z {
  if (_Ensure-Zoxide) {
    Remove-Item Function:z -Force -ErrorAction SilentlyContinue
    z @args
  } else {
    Set-Location @args
  }
}
function zi {
  if (_Ensure-Zoxide) {
    Remove-Item Function:zi -Force -ErrorAction SilentlyContinue
    zi @args
  } else {
    Write-Warning 'zoxide が見つかりません'
  }
}
_mark 'zoxide lazy'

# ───────────────────────────────────────────────────────────── eza (lazy ls/ll/lt)
Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
function _Invoke-EzaOrFallback {
  param([string[]]$EzaArgs, [object[]]$OriginalArgs)
  $eza = _Get-ToolExe 'eza'
  if ($eza) { & $eza @EzaArgs @OriginalArgs }
  else { Get-ChildItem @OriginalArgs }
}
function ls { _Invoke-EzaOrFallback -EzaArgs @('--icons', '--group-directories-first') -OriginalArgs $args }
function ll { _Invoke-EzaOrFallback -EzaArgs @('-la', '--icons', '--group-directories-first', '--git') -OriginalArgs $args }
function lt { _Invoke-EzaOrFallback -EzaArgs @('--tree', '--level=2', '--icons', '--group-directories-first') -OriginalArgs $args }
_mark 'eza lazy'

# ───────────────────────────────────────────────────────────── mise (opt-in)
# 起動時間を ~1.5s 消費するため既定では無効。user-config.ps1 で
# $global:PSProfileEnableMise = $true としたときのみ有効化する。
if ($global:PSProfileEnableMise -eq $true) {
  $mise = _Get-ToolExe 'mise'
  if ($mise) {
    _Use-CachedInit -Tool 'mise' -ExePath $mise -Generate {
      & $mise activate pwsh
    }
  }
}
_mark 'mise opt-in'

# ───────────────────────────────────────────────────────────── Proxy lazy stubs
# Load Proxy.ps1 only when a px-* command is called. 2回目以降は dot-source 済みの
# 関数を再利用し、px-state → px-doctor のような連続操作の待ち時間を減らす。
$script:PSProfileProxyLoaded = $false
function Invoke-PSProfileProxy {
  param(
    [Parameter(Mandatory)][string]$Command,
    [object[]]$Arguments = @()
  )
  if (-not $script:PSProfileProxyLoaded) {
    $proxyScript = $PSScriptRoot + '\Proxy.ps1'
    if (-not [IO.File]::Exists($proxyScript)) {
      Write-Warning "Proxy.ps1 が見つかりません: $proxyScript"
      return
    }
    . $proxyScript
    $script:PSProfileProxyLoaded = $true
  }
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
        $env:PSPROFILE_UPDATE_BRANCH または -Branch で取得ブランチ/タグを指定可能。
    #>
  [CmdletBinding()]
  param(
    [switch]$Prerelease,
    [string]$Branch = $(if ($env:PSPROFILE_UPDATE_BRANCH) { $env:PSPROFILE_UPDATE_BRANCH } else { $script:PSProfileUpdateBranch }),
    [switch]$Force
  )

  $baseUrl = "https://raw.githubusercontent.com/yura-koizumi/ps-profile/$Branch"
  $url = if ($env:PSPROFILE_UPDATE_URL) { $env:PSPROFILE_UPDATE_URL }
  elseif ($Prerelease) { "$baseUrl/install.ps1" }
  else { "$baseUrl/install.ps1" }
  $manifestUrl = if ($url -match '/install\.ps1(\?.*)?$') {
    $url -replace '/install\.ps1(\?.*)?$', '/modules/PSProfile/PSProfile.psd1'
  } else {
    "$baseUrl/modules/PSProfile/PSProfile.psd1"
  }
  $cacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $separator = if ($url.Contains('?')) { '&' } else { '?' }
  $requestUrl = "$url${separator}cacheBust=$cacheBust"
  $manifestSeparator = if ($manifestUrl.Contains('?')) { '&' } else { '?' }
  $manifestRequestUrl = "$manifestUrl${manifestSeparator}cacheBust=$cacheBust"

  Write-Host "  PSProfile current: v$script:PSProfileVersion" -ForegroundColor DarkGray
  Write-Host "  PSProfile branch:   $Branch" -ForegroundColor DarkGray
  Write-Host "  PSProfile update:  $url" -ForegroundColor DarkGray

  $remoteVersion = $null
  try {
    $manifest = Invoke-RestMethod -Uri $manifestRequestUrl -Headers @{ 'Cache-Control' = 'no-cache' } -ErrorAction Stop
    if ($manifest -match "ModuleVersion\s*=\s*'([^']+)'") { $remoteVersion = $Matches[1] }
    elseif ($manifest -match 'ModuleVersion\s*=\s*"([^"]+)"') { $remoteVersion = $Matches[1] }
  } catch {
    Write-Warning "更新先バージョン確認に失敗しました: $($_.Exception.Message)"
  }

  if ($remoteVersion) {
    Write-Host "  PSProfile remote:  v$remoteVersion" -ForegroundColor DarkGray
    try {
      if (([version]$remoteVersion) -le ([version]$script:PSProfileVersion) -and -not $Force) {
        Write-Warning "取得先 ($Branch) には現在より新しい PSProfile がありません。PR/別ブランチを試す場合は psprofile-update -Branch <branch>、同じ版を再インストールする場合は -Force を付けてください。"
        return
      }
    } catch { }
  }

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


# ───────────────────────────────────────────────────────────── user-config 導線
function Get-PSProfileConfigPath {
  [pscustomobject]@{
    UserConfig = $HOME + '\.psprofile\user-config.ps1'
    ConfigDir = $HOME + '\.psprofile'
  }
}

function Initialize-PSProfileConfig {
  [CmdletBinding()]
  param([switch]$Force)

  $paths = Get-PSProfileConfigPath
  if (-not [IO.Directory]::Exists($paths.ConfigDir)) {
    [IO.Directory]::CreateDirectory($paths.ConfigDir) | Out-Null
  }
  if ([IO.File]::Exists($paths.UserConfig) -and -not $Force) { return $paths.UserConfig }

  $content = @'
#Requires -Version 7.0
# PSProfile かんたん設定
# どれか1つだけ選んでコメント # を外してください。

# 会社PC: px-on / px-off で PC 全体を切り替える
# $global:PSProfileProxyPreset = 'WorkPc'

# 会社PC + VSCode settings.json も切り替える
# $global:PSProfileProxyPreset = 'WorkPcWithVSCode'

# このPowerShellだけ切り替える
# $global:PSProfileProxyPreset = 'PowerShellOnly'

# 私用PC / プロキシを使わない
# $global:PSProfileProxyPreset = 'PrivatePc'

# Pxではなく手動プロキシURLを使う
# $global:PSProfileProxyPreset = 'ManualProxy'
# $global:PSProfileProxyUrl = 'http://proxy.example.com:8080'
'@
  [IO.File]::WriteAllText($paths.UserConfig, $content, [Text.UTF8Encoding]::new($false))
  return $paths.UserConfig
}

function Open-PSProfileConfig {
  [CmdletBinding()]
  param([switch]$NoEditor)

  $path = Initialize-PSProfileConfig
  if ($NoEditor) {
    Write-Host $path
    return
  }
  $editor = $env:EDITOR
  if (-not $editor) {
    $code = _Get-ToolExe 'code'
    if ($code) { $editor = $code }
  }
  try {
    if ($editor) { Start-Process $editor -ArgumentList @($path) | Out-Null }
    elseif ($IsWindows) { Start-Process notepad $path | Out-Null }
    else { Write-Host $path }
  } catch {
    Write-Warning "設定ファイルを開けませんでした: $($_.Exception.Message)"
    Write-Host $path
  }
}
Set-Alias pconfig Open-PSProfileConfig
Set-Alias psprofile-config Open-PSProfileConfig

function Set-PSProfileProxyPreset {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, Position=0)]
    [ValidateSet('WorkPc', 'WorkPcWithVSCode', 'PowerShellOnly', 'PrivatePc', 'ManualProxy')]
    [string]$Preset,
    [string]$ProxyUrl
  )

  $path = Initialize-PSProfileConfig
  $text = [IO.File]::ReadAllText($path)
  $line = "`$global:PSProfileProxyPreset = '$Preset'"
  if ($text -match '(?m)^\s*#?\s*\$global:PSProfileProxyPreset\s*=.*$') {
    $text = [regex]::Replace($text, '(?m)^\s*#?\s*\$global:PSProfileProxyPreset\s*=.*$', $line, 1)
  } else {
    $text = $text.TrimEnd() + "`n`n# PSProfile proxy preset`n$line`n"
  }

  if ($Preset -eq 'ManualProxy' -and $ProxyUrl) {
    $urlLine = "`$global:PSProfileProxyUrl = '$ProxyUrl'"
    if ($text -match '(?m)^\s*#?\s*\$global:PSProfileProxyUrl\s*=.*$') {
      $text = [regex]::Replace($text, '(?m)^\s*#?\s*\$global:PSProfileProxyUrl\s*=.*$', $urlLine, 1)
    } else {
      $text += "`n$urlLine`n"
    }
    $global:PSProfileProxyUrl = $ProxyUrl
  }

  [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
  $global:PSProfileProxyPreset = $Preset
  Write-Host "PSProfile proxy preset: $Preset" -ForegroundColor Green
  Write-Host "設定ファイル: $path" -ForegroundColor DarkGray
  Write-Host '現在のターミナルではこの設定を反映済みです。必要なら px-on / px-off を実行してください。' -ForegroundColor DarkGray
}
Set-Alias ppreset Set-PSProfileProxyPreset
Set-Alias psprofile-preset Set-PSProfileProxyPreset

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
      @{ c = 'px-on'; d = 'proxy が必要な時に、Env/System/VSCode など指定 target を ON' }
      @{ c = 'px-off'; d = '指定 target の proxy を解除/復元。Px プロセスは既定で残す' }
      @{ c = 'px-off -StopProcess'; d = 'env 解除に加えて、このプロファイルが記録した Px プロセスを停止' }
      @{ c = 'px-restart'; d = 'Px と env proxy を再読み込み' }
    )
  }

  if ($Topic -in @('All', 'Config')) {
    $sections['端末固有設定'] = @(
      @{ c = 'pconfig'; d = 'user-config.ps1 を作成してエディタで開く' }
      @{ c = 'ppreset WorkPc'; d = 'かんたん設定を1コマンドで保存 (WorkPc 等)' }
      @{ c = '~/.psprofile/user-config.ps1'; d = '職場PC / 私用PC / macOS など端末ごとの設定置き場' }
      @{ c = '$global:PSProfileProxyPreset'; d = 'かんたん設定: WorkPc / WorkPcWithVSCode / PowerShellOnly / PrivatePc / ManualProxy' }
      @{ c = '$global:PSProfileDeviceRole'; d = '上級者向け: Work / Private' }
      @{ c = '$global:PSProfileProxyMode'; d = '上級者向け: WorkPx / Manual / None' }
      @{ c = '$global:PSProfileProxyTargets'; d = '上級者向け: Env / System / VSCode' }
      @{ c = '$global:PSProfileProxyUrl'; d = 'macOS / Manual モードで使う proxy URL' }
      @{ c = '$global:PSProfileSyncVSCodeProxy'; d = 'true の時だけ VSCode settings.json を連動' }
      @{ c = '$global:PSProfileNoProxy'; d = 'NO_PROXY / no_proxy / Windows proxy override の値を上書き' }
      @{ c = '$global:PSProfileStopPxProcessOnOff'; d = 'true の時だけ px-off で Px プロセスも停止' }
    )
    $sections['安全設計'] = @(
      @{ c = 'VSCode'; d = '既定では settings.json を変更しない。Settings Sync 事故を避ける' }
      @{ c = 'Git / npm / pip'; d = '既定では global proxy を変更しない。px-state / px-doctor で確認する' }
      @{ c = 'Windows'; d = 'System target 有効時は Windows system proxy も px-on/off に連動' }
      @{ c = 'macOS'; d = 'Px 起動はしない。必要なら PSProfileProxyUrl を明示して env だけ設定' }
    )
  }

  if ($Topic -in @('All', 'Examples')) {
    $sections['よく使う流れ'] = @(
      @{ c = '社内LAN'; d = 'px-doctor → px-on → 作業 → px-off' }
      @{ c = 'Akamai VPN / 外出先'; d = 'プロキシ不要なら px-off。必要なら利用者判断で px-on' }
      @{ c = '初回設定'; d = 'pconfig または ppreset WorkPc / ppreset PrivatePc' }
      @{ c = '私用PC'; d = 'ppreset PrivatePc で proxy を無効化' }
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
      @{ c = 'pconfig'; d = '設定ファイルを開く' }
      @{ c = 'ppreset WorkPc'; d = 'proxy プリセットを保存' }
      @{ c = 'phelp -Topic Proxy'; d = 'Proxy 関連だけ表示' }
      @{ c = 'psprofile-version'; d = 'バージョン / 更新URL / 読み込み元パスを表示' }
      @{ c = 'psprofile-update'; d = '更新先バージョン確認後、module + profile 本体を更新' }
      @{ c = 'psprofile-update -Force'; d = '同じバージョンでも再インストールして profile 本体も入れ直す' }
      @{ c = 'psprofile-update -Branch <name>'; d = 'PR / 検証ブランチ / タグから更新' }
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
  Write-Host '  まず迷ったら: pconfig / px-doctor' -ForegroundColor DarkGray
  Write-Host ("  読み込み元: $PSScriptRoot") -ForegroundColor DarkGray
  Write-Host ("  プロファイル読み込み: $($script:ProfileLoadMs) ms") -ForegroundColor DarkGray
  Write-Host ''
}
Set-Alias phelp Show-ProfileHelp

# ───────────────────────────────────────────────────────────── 起動メッセージ
if ($global:PSProfileEnableStartupBanner -ne $false) {
  Write-Host '  カスタムコマンド: ' -NoNewline -ForegroundColor DarkGray
  Write-Host 'phelp / pconfig' -ForegroundColor Yellow
}

if ($script:_bench) {
  _mark 'rest'
  Write-Host ''
  Write-Host '── PSProfile section timings ──' -ForegroundColor Yellow
  foreach ($m in $script:_marks) { Write-Host $m -ForegroundColor DarkGray }
  Write-Host ('  {0,-22} {1,5} ms' -f 'TOTAL', $script:_sw.ElapsedMilliseconds) -ForegroundColor Yellow
}
