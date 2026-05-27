#Requires -Version 7.0
# PSProfile v2.0 — 単一モジュール構成 / 起動時間最優先
# 目標: コールド起動でも 1 秒未満。Proxy 系は初回呼び出しまで実体ロード遅延。

# ───────────────────────────────────────────────────────────── 起動時間計測
$script:_sw = [System.Diagnostics.Stopwatch]::StartNew()

# ───────────────────────────────────────────────────────────── エンコーディング
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# ───────────────────────────────────────────────────────────── PSReadLine 遅延適用
# 初回 Set-PSReadLineOption は ~1s かかる。プロンプト表示後の OnIdle で設定する。
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    try {
        Set-PSReadLineOption -EditMode Windows -PredictionSource History -PredictionViewStyle ListView
        Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
        Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    } catch {}
}

# ───────────────────────────────────────────────────────────── 高速ツール探索
# Get-Command は ModuleAnalysisCache の影響で初回 ~50ms/件。
# $env:PATH を 1 回パースして Hashtable に展開する方が速い。
$script:_pathExt = @('.exe', '.cmd', '.bat', '.com')
function _Find-Exe {
    param([string]$Name)
    foreach ($dir in ($env:PATH -split ';')) {
        if (-not $dir) { continue }
        foreach ($ext in $script:_pathExt) {
            $p = Join-Path $dir ($Name + $ext)
            if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
        }
    }
    return $null
}

# ───────────────────────────────────────────────────────────── 外部ツール init キャッシュ
$script:_initCacheDir = Join-Path $env:LOCALAPPDATA 'PSProfile\init-cache'

function _Use-CachedInit {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][scriptblock]$Generate
    )
    if (-not (Test-Path $script:_initCacheDir)) {
        New-Item -ItemType Directory -Path $script:_initCacheDir -Force | Out-Null
    }
    $cache = Join-Path $script:_initCacheDir "$Tool.ps1"
    $regen = $true
    if ((Test-Path -LiteralPath $cache) -and (Test-Path -LiteralPath $ExePath)) {
        if ((Get-Item $cache).LastWriteTimeUtc -ge (Get-Item $ExePath).LastWriteTimeUtc) { $regen = $false }
    }
    if ($regen) {
        try {
            $content = (& $Generate) -join "`n"
            Set-Content -LiteralPath $cache -Value $content -Encoding UTF8
        } catch {
            Write-Warning ("{0} init キャッシュ生成失敗: {1}" -f $Tool, $_.Exception.Message)
            return
        }
    }
    . $cache
}

# ───────────────────────────────────────────────────────────── 1回限りツール検出
$script:_exe = @{
    starship = _Find-Exe 'starship'
    zoxide   = _Find-Exe 'zoxide'
    eza      = _Find-Exe 'eza'
    mise     = _Find-Exe 'mise'
}

# ───────────────────────────────────────────────────────────── starship
if ($script:_exe.starship) {
    $env:STARSHIP_CONFIG = Join-Path $PSScriptRoot 'starship.toml'
    _Use-CachedInit -Tool 'starship' -ExePath $script:_exe.starship -Generate {
        & $script:_exe.starship init powershell --print-full-init
    }
}

# ───────────────────────────────────────────────────────────── zoxide
if ($script:_exe.zoxide) {
    _Use-CachedInit -Tool 'zoxide' -ExePath $script:_exe.zoxide -Generate {
        & $script:_exe.zoxide init powershell
    }
}

# ───────────────────────────────────────────────────────────── eza (ls/ll/lt)
if ($script:_exe.eza) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza --icons --group-directories-first @args }
    function ll { eza -la --icons --group-directories-first --git @args }
    function lt { eza --tree --level=2 --icons --group-directories-first @args }
}

# ───────────────────────────────────────────────────────────── mise (opt-in)
# 起動時間を ~1.5s 消費するため既定では無効。user-config.ps1 で
# $global:PSProfileEnableMise = $true としたときのみ有効化する。
if ($script:_exe.mise -and $global:PSProfileEnableMise) {
    _Use-CachedInit -Tool 'mise' -ExePath $script:_exe.mise -Generate {
        & $script:_exe.mise activate pwsh
    }
}

# ───────────────────────────────────────────────────────────── Proxy 本体
# Proxy.ps1 を直接 dot-source（モジュールスコープに関数を展開する必要があるため、
# 関数内 dot-source ではなく psm1 トップレベルで読み込む）。
# パース時間は概ね 10–30ms 程度で、起動目標の許容範囲内。
$_proxyScript = Join-Path $PSScriptRoot 'Proxy.ps1'
if (Test-Path -LiteralPath $_proxyScript) {
    . $_proxyScript
}
Remove-Variable _proxyScript -ErrorAction SilentlyContinue

Set-Alias px-on      Start-PxProxy
Set-Alias px-off     Stop-PxProxy
Set-Alias px-state   Get-PxState
Set-Alias px-restart Restart-PxProxy

# ───────────────────────────────────────────────────────────── Update
function Update-PSProfile {
    <#
    .SYNOPSIS
        PSProfile を GitHub から最新版に更新する。
    .DESCRIPTION
        jsdelivr CDN 経由で install.ps1 を取得し -Update モードで実行する。
        $env:PSPROFILE_UPDATE_URL で取得元 URL を上書き可能。
    #>
    [CmdletBinding()]
    param([switch]$Prerelease)

    $url = if ($env:PSPROFILE_UPDATE_URL) { $env:PSPROFILE_UPDATE_URL }
    elseif ($Prerelease) { 'https://cdn.jsdelivr.net/gh/yura-koizumi/ps-profile@main/install.ps1' }
    else { 'https://cdn.jsdelivr.net/gh/yura-koizumi/ps-profile@main/install.ps1' }

    Write-Host "  PSProfile update: $url" -ForegroundColor DarkGray
    try {
        $script = Invoke-RestMethod -Uri $url -ErrorAction Stop
    } catch {
        Write-Warning "更新スクリプト取得失敗: $($_.Exception.Message)"
        return
    }
    & ([scriptblock]::Create($script)) -Update
}
Set-Alias psprofile-update Update-PSProfile

# ───────────────────────────────────────────────────────────── phelp
$script:_sw.Stop()
$script:ProfileLoadMs = $script:_sw.ElapsedMilliseconds

function Show-ProfileHelp {
    Write-Host ''
    Write-Host '  PSProfile' -NoNewline -ForegroundColor White
    Write-Host ' ─── コマンド一覧 ─────────────────────────────────' -ForegroundColor DarkGray
    Write-Host ''
    $sections = [ordered]@{
        'ファイル / 移動'       = @(
            @{ c = 'ls / ll / lt'; d = 'eza ベースの一覧 (eza)' }
            @{ c = 'z <dir> / zi'; d = 'zoxide — スマート cd (zoxide)' }
        )
        'プロキシ (Px)'        = @(
            @{ c = 'px-on'; d = 'px 起動 + 環境変数 + VSCode 同期' }
            @{ c = 'px-off'; d = 'px 停止 + 環境変数 + VSCode 解除' }
            @{ c = 'px-state'; d = 'px 状態確認 (Edit で px.ini 編集)' }
            @{ c = 'px-restart'; d = 'px-off → px-on で再読み込み' }
        )
        'プロファイル管理'      = @(
            @{ c = 'phelp'; d = 'このコマンド一覧を表示' }
            @{ c = 'psprofile-update'; d = 'GitHub から最新版に更新' }
        )
    }
    foreach ($title in $sections.Keys) {
        Write-Host '  ' -NoNewline
        Write-Host '❯ ' -NoNewline -ForegroundColor Yellow
        Write-Host $title -ForegroundColor Cyan
        foreach ($i in $sections[$title]) {
            Write-Host '    · ' -NoNewline -ForegroundColor DarkGray
            Write-Host ('{0,-20}' -f $i.c) -NoNewline -ForegroundColor White
            Write-Host $i.d -ForegroundColor DarkGray
        }
        Write-Host ''
    }
    Write-Host ('  ' + '─' * 50) -ForegroundColor DarkGray
    Write-Host ("  プロファイル読み込み: $($script:ProfileLoadMs) ms") -ForegroundColor DarkGray
    Write-Host ''
}
Set-Alias phelp Show-ProfileHelp

# ───────────────────────────────────────────────────────────── 起動メッセージ
Write-Host '  カスタムコマンド一覧: ' -NoNewline -ForegroundColor DarkGray
Write-Host 'phelp' -ForegroundColor Yellow

