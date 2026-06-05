#Requires -Version 7.0
<#
.SYNOPSIS
    PSProfile v2 セットアップスクリプト (リモート / ローカル両対応)

.DESCRIPTION
    ローカル実行: clone したリポジトリ内から呼び出すとローカルファイルをコピー。
    リモート実行: irm | iex でも動作。GitHub raw からファイルを取得して配置。

.PARAMETER Update
    プロファイル本体は触らずモジュールのみ最新化する。

.PARAMETER Uninstall
    プロファイルとモジュールを削除する。

.PARAMETER SkipDeps
    winget での依存ツールインストールをスキップ。

.PARAMETER Branch
    リモート取得時のブランチ/タグ (既定: main)

.EXAMPLE
    # 任意端末に1行インストール:
    irm 'https://raw.githubusercontent.com/yura-koizumi/ps-profile/main/install.ps1' | iex

.EXAMPLE
    # ローカル clone から:
    .\install.ps1            # フルインストール
    .\install.ps1 -SkipDeps  # プロファイル+モジュールのみ
    .\install.ps1 -Update    # モジュールだけ更新
    .\install.ps1 -Uninstall # 完全削除
#>
[CmdletBinding()]
param(
    [switch]$Update,
    [switch]$Uninstall,
    [switch]$SkipDeps,
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$PSProfileInstallerVersion = '2.4.2'

# ───────────────────────────────────────────────────────────── パス定数
$ModulesRoot = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules'
$ModuleDir   = Join-Path $ModulesRoot 'PSProfile'
$ProfileSrc  = $null  # 後で決定
$UserCfgDir  = Join-Path $HOME '.psprofile'
$UserCfg     = Join-Path $UserCfgDir 'user-config.ps1'
$BackupDir   = Join-Path $UserCfgDir 'backups'
$CacheDir    = Join-Path $env:LOCALAPPDATA 'PSProfile'

$BaseUrl = "https://raw.githubusercontent.com/yura-koizumi/ps-profile/$Branch"
$CacheBust = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
# モジュール構成ファイル (相対パスはローカル src/ からの位置)
$ModuleFiles = @(
    'modules/PSProfile/PSProfile.psd1'
    'modules/PSProfile/PSProfile.psm1'
    'modules/PSProfile/Proxy.ps1'
    'modules/PSProfile/Private/Px.Platform.ps1'
    'modules/PSProfile/Private/Px.Discovery.ps1'
    'modules/PSProfile/Private/Px.Env.ps1'
    'modules/PSProfile/Private/Px.Apps.ps1'
    'modules/PSProfile/Private/Px.Runtime.ps1'
    'modules/PSProfile/Private/Px.Diagnostics.ps1'
    'modules/PSProfile/Private/Px.Commands.ps1'
    'modules/PSProfile/starship.toml'
)
$ProfileFile = 'Microsoft.PowerShell_profile.ps1'
$UserCfgTpl  = 'user-config.template.ps1'

# ───────────────────────────────────────────────────────────── ローカル/リモート検出
$MyDir = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $null }
$IsLocal = $false
if ($MyDir) {
    $probe = Join-Path $MyDir 'modules\PSProfile\PSProfile.psm1'
    if (Test-Path $probe) { $IsLocal = $true }
}

function Get-PSProfileFile {
    param([Parameter(Mandatory)][string]$Relative, [Parameter(Mandatory)][string]$Destination)
    if ($IsLocal) {
        $src = Join-Path $MyDir $Relative
        if (-not (Test-Path $src)) { throw "ローカルファイル不在: $src" }
        $dstDir = Split-Path $Destination -Parent
        if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        Copy-Item $src $Destination -Force
    } else {
        $url = "$BaseUrl/$Relative`?cacheBust=$CacheBust"
        $dstDir = Split-Path $Destination -Parent
        if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
        Invoke-WebRequest -Uri $url -OutFile $Destination -Headers @{ 'Cache-Control' = 'no-cache' } -UseBasicParsing
    }
}

# ───────────────────────────────────────────────────────────── プロファイル配置先
$ProfilePath = $PROFILE.CurrentUserCurrentHost
$ProfileDir  = Split-Path $ProfilePath -Parent
$TargetProfiles = @(
    $ProfilePath
    (Join-Path $ProfileDir 'Microsoft.VSCode_profile.ps1')
) | Select-Object -Unique

# ───────────────────────────────────────────────────────────── 移行クリーンアップ
# 旧構成のファイルが有効な profile / module path に残ると、起動遅延や proxy 誤設定の原因になる。
# user-config.ps1 は端末固有設定なので削除しない。旧 profile は PSProfile 由来と判定できる場合だけ退避する。
$LegacyModuleNames = @('PSProfile.Core', 'PSProfile.Proxy', 'PSProfile.DevTools')
$LegacyProfileFiles = @(
    (Join-Path $ProfileDir 'profile.ps1')
    (Join-Path $ProfileDir 'Microsoft.PowerShellISE_profile.ps1')
) | Select-Object -Unique
$LegacyProfilePatterns = @(
    'PSProfile\.Core'
    'PSProfile\.Proxy'
    'PSProfile\.DevTools'
    'Bootstrap\.cmd'
    'dev-install'
    'px-env'
    'px-config'
    'px-ini'
    'WinINET'
)

function Test-PSProfileLegacyContent {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    } catch {
        return $false
    }
    foreach ($pattern in $LegacyProfilePatterns) {
        if ($raw -match $pattern) { return $true }
    }
    return $false
}

function Move-PSProfileLegacyProfile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-PSProfileLegacyContent -Path $Path)) { return }
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $leaf = Split-Path $Path -Leaf
    $dest = Join-Path $BackupDir "$stamp.$leaf.legacy"
    Move-Item -LiteralPath $Path -Destination $dest -Force
    Write-Host "  - legacy profile 退避: $Path -> $dest" -ForegroundColor Yellow
}

function Remove-PSProfilePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Recurse,
        [string]$Label = 'cleanup'
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        if ($Recurse) {
            Remove-Item -LiteralPath $Path -Recurse -Force
        } else {
            Remove-Item -LiteralPath $Path -Force
        }
    } catch {
        Write-Host "  ! $Path ($Label) 削除スキップ: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }
    Write-Host "  - $Path ($Label)" -ForegroundColor DarkGray
}

function Invoke-PSProfileMigrationCleanup {
    Write-Host '■ 移行クリーンアップ' -ForegroundColor Cyan

    foreach ($old in $LegacyModuleNames) {
        Remove-PSProfilePath -Path (Join-Path $ModulesRoot $old) -Recurse -Label 'legacy module'
    }

    foreach ($p in $LegacyProfileFiles) {
        Move-PSProfileLegacyProfile -Path $p
    }

    Remove-PSProfilePath -Path (Join-Path $CacheDir 'exe-cache.ps1') -Label 'cache'
    Remove-PSProfilePath -Path (Join-Path $CacheDir 'exe-cache.json') -Label 'legacy cache'
    Remove-PSProfilePath -Path (Join-Path $CacheDir 'init-cache') -Recurse -Label 'init cache'
    Remove-PSProfilePath -Path (Join-Path $CacheDir 'PSProfile.Proxy.px-process.json') -Label 'runtime record'

    Write-Host '  user-config.ps1 は維持します' -ForegroundColor DarkGray
}

# ───────────────────────────────────────────────────────────── Uninstall
if ($Uninstall) {
    Write-Host '■ PSProfile アンインストール' -ForegroundColor Cyan
    Write-Host "  installer v$PSProfileInstallerVersion" -ForegroundColor DarkGray
    foreach ($p in $TargetProfiles) {
        if (Test-Path $p) { Remove-Item $p -Force; Write-Host "  - $p" }
    }
    if (Test-Path $ModuleDir) { Remove-Item $ModuleDir -Recurse -Force; Write-Host "  - $ModuleDir" }
    Invoke-PSProfileMigrationCleanup
    Write-Host '完了。PowerShell を再起動してください。' -ForegroundColor Green
    return
}

Invoke-PSProfileMigrationCleanup

# ───────────────────────────────────────────────────────────── モジュール配置
Write-Host '■ PSProfile モジュール' -ForegroundColor Cyan
Write-Host "  installer v$PSProfileInstallerVersion" -ForegroundColor DarkGray
if (-not $IsLocal) {
    Write-Host "  source: $BaseUrl" -ForegroundColor DarkGray
}
if (Test-Path $ModuleDir) { Remove-Item $ModuleDir -Recurse -Force }
New-Item -ItemType Directory -Path $ModuleDir -Force | Out-Null
foreach ($f in $ModuleFiles) {
    $dest = Join-Path $ModulesRoot $f.Replace('modules/', '')
    Get-PSProfileFile -Relative $f -Destination $dest
}
Write-Host "  → $ModuleDir"

# ───────────────────────────────────────────────────────────── Update モード: モジュールだけで終了
if ($Update) {
    $manifestPath = Join-Path $ModuleDir 'PSProfile.psd1'
    $installedVersion = $null
    try {
        $installedVersion = (Import-PowerShellDataFile -Path $manifestPath).ModuleVersion
    } catch {}
    if ($installedVersion) {
        Write-Host "  installed version: v$installedVersion" -ForegroundColor Green
    }
    Write-Host "  module path: $ModuleDir" -ForegroundColor DarkGray
    Write-Host '完了 (-Update)。新しい PowerShell ターミナルを開いてください。' -ForegroundColor Green
    return
}

# ───────────────────────────────────────────────────────────── プロファイル本体配置
Write-Host '■ プロファイル本体' -ForegroundColor Cyan
foreach ($tp in $TargetProfiles) {
    New-Item -ItemType Directory -Path (Split-Path $tp -Parent) -Force | Out-Null
    Get-PSProfileFile -Relative $ProfileFile -Destination $tp
    Write-Host "  → $tp"
}

# ───────────────────────────────────────────────────────────── user-config 初回コピー
Write-Host '■ user-config' -ForegroundColor Cyan
if (-not (Test-Path $UserCfgDir)) { New-Item -ItemType Directory -Path $UserCfgDir -Force | Out-Null }
if (-not (Test-Path $UserCfg)) {
    Get-PSProfileFile -Relative $UserCfgTpl -Destination $UserCfg
    Write-Host "  → $UserCfg (template)"
} else {
    Write-Host "  既存維持: $UserCfg"
}

# ───────────────────────────────────────────────────────────── 依存ツール (winget)
if ($SkipDeps) {
    Write-Host '完了 (-SkipDeps)。新しい PowerShell ターミナルを開いてください。' -ForegroundColor Green
    return
}

Write-Host '■ winget 依存ツール' -ForegroundColor Cyan
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host '  winget が見つかりません。Microsoft Store から「アプリ インストーラー」をインストールしてください。' -ForegroundColor Yellow
} else {
    $pkgs = @(
        'genotrance.px'         # Px プロキシ
        'Starship.Starship'     # プロンプト
        'ajeetdsouza.zoxide'    # スマート cd
        'eza-community.eza'     # ls 代替
    )
    $wgArgs = @('--silent', '--accept-source-agreements', '--accept-package-agreements')
    foreach ($id in $pkgs) {
        winget install --id $id -e @wgArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -in 0, -1978335189) {
            Write-Host "  ✓ $id" -ForegroundColor Green
        } else {
            Write-Host "  ! $id (exit $LASTEXITCODE)" -ForegroundColor Yellow
        }
    }
}

Write-Host ''
Write-Host '■ 次のステップ' -ForegroundColor Cyan
Write-Host '  1. 新しい PowerShell ターミナルを開く'
Write-Host '  2. phelp でコマンド一覧を確認'
Write-Host '  3. (任意) Nerd Fonts: winget install Microsoft.RobotoMono など'
Write-Host '  4. (任意) ~/.psprofile/user-config.ps1 を編集して端末固有設定'
Write-Host ''
Write-Host '完了。' -ForegroundColor Green

