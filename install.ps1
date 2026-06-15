#Requires -Version 7.0
<#
.SYNOPSIS
    PSProfile v2.5 セットアップスクリプト (リモート / ローカル両対応)

.DESCRIPTION
    ローカル実行: clone したリポジトリ内から呼び出すとローカルファイルをコピー。
    リモート実行: irm | iex でも動作。GitHub の tar.gz を 1 回で取得→展開してから配置する
    (個別ファイルを多数 fetch しないので、プロキシ必須の不安定ネットワークでも壊れにくい)。
    モジュールは一時ディレクトリにステージングしてから入替えるため、途中失敗で既存環境を壊さない。

.PARAMETER Update
    プロファイル本体は触らずモジュールのみ最新化する。

.PARAMETER Uninstall
    プロファイルとモジュールを削除する。

.PARAMETER SkipDeps
    依存ツールインストール (Windows: winget) をスキップ。

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
$PSProfileInstallerVersion = '2.5.0'

# ───────────────────────────────────────────────────────────── プラットフォーム
# $IsWindows は PS6+ の自動変数。PS5.1 では未定義なので true 扱いにフォールバック。
# ただし正式対象は PowerShell 7 以上。PS5.1 は UTF-8 BOM なし日本語を誤読する可能性がある。
$OnWindows = if ($null -ne $IsWindows) { [bool]$IsWindows } else { $true }

# ───────────────────────────────────────────────────────────── パス定数 (OS 別)
if ($OnWindows) {
    $ModulesRoot = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules'
    $CacheDir    = Join-Path $env:LOCALAPPDATA 'PSProfile'
} else {
    $ModulesRoot = Join-Path $HOME '.local/share/powershell/Modules'
    $CacheDir    = Join-Path $HOME '.cache/PSProfile'
}
$ModuleDir   = Join-Path $ModulesRoot 'PSProfile'
$UserCfgDir  = Join-Path $HOME '.psprofile'   # 旧 profile 退避用。user-config / 旧メニュー入口は v2.5 では使わない。
$BackupDir   = Join-Path $UserCfgDir 'backups'

$RepoSlug = 'yura-koizumi/ps-profile'

# ───────────────────────────────────────────────────────────── ローカル/リモート検出
$MyDir = if ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { $null }
$IsLocal = $false
if ($MyDir -and (Test-Path (Join-Path $MyDir 'modules/PSProfile/PSProfile.psm1'))) { $IsLocal = $true }

$script:DownloadTmp = $null

function Get-PSProfileSourceDir {
    # modules/PSProfile/PSProfile.psm1 を含む source root を返す。
    # v2.5 では root レイアウトが正本。過去の src/ レイアウトから更新される場合もあるため、
    # リモート tar 展開後は PSProfile.psm1 の実在位置から source root を逆算する。
    if ($IsLocal) { return $MyDir }

    $tarUrl  = "https://codeload.github.com/$RepoSlug/tar.gz/refs/heads/$Branch"
    $tmpRoot = Join-Path ([IO.Path]::GetTempPath()) ('psprofile-dl-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
    $script:DownloadTmp = $tmpRoot
    $tgz = Join-Path $tmpRoot 'src.tar.gz'

    Write-Host "  download: $tarUrl" -ForegroundColor DarkGray
    # raw ファイルを多数取る方式はプロキシ環境で途中失敗しやすい。
    # tar.gz を 1 回だけ取得し、ローカル展開後にまとめてコピーする。
    Invoke-WebRequest -Uri $tarUrl -OutFile $tgz -Headers @{ 'Cache-Control' = 'no-cache' } -UseBasicParsing

    if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
        throw 'tar が見つかりません。リポジトリを clone して .\install.ps1 をローカル実行してください。'
    }
    tar -xzf $tgz -C $tmpRoot
    if ($LASTEXITCODE -ne 0) { throw "アーカイブ展開に失敗しました (tar exit $LASTEXITCODE)" }

    $psm1 = Get-ChildItem -Path $tmpRoot -Recurse -File -Filter 'PSProfile.psm1' -ErrorAction SilentlyContinue |
        Where-Object { ($_.FullName -replace '\\', '/') -match 'modules/PSProfile/PSProfile\.psm1$' } |
        Select-Object -First 1
    if (-not $psm1) { throw 'ダウンロードしたアーカイブ内に modules/PSProfile が見つかりません' }

    # .../<root>/modules/PSProfile/PSProfile.psm1 → modules を含む source root。
    # 旧 src/ レイアウトからの更新も、PSProfile.psm1 の位置を基準にすれば同じ式で拾える。
    return (Split-Path (Split-Path (Split-Path $psm1.FullName -Parent) -Parent) -Parent)
}

function Remove-PSProfileDownloadTmp {
    # リモート取得で使った一時ディレクトリを最後に必ず消す。
    # 削除失敗はインストール結果に影響させない。
    if ($script:DownloadTmp -and (Test-Path $script:DownloadTmp)) {
        Remove-Item $script:DownloadTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ───────────────────────────────────────────────────────────── プロファイル配置先
$ProfilePath = $PROFILE.CurrentUserCurrentHost
$ProfileDir  = Split-Path $ProfilePath -Parent

function Get-PSProfileProfileDirs {
    # PowerShell の $PROFILE は通常の string に NoteProperty が付いた特殊値。
    # 実行コンテキストによって Documents が OneDrive 配下に解決される場合と、
    # C:\Users\<user>\Documents に解決される場合がある。
    # 片側に旧 profile が残ると「インストール成功なのに旧モジュール警告が出る」ため、
    # 現在の $PROFILE と、MyDocuments\PowerShell と、存在する OneDrive\Documents 系を候補にする。
    $dirs = [System.Collections.Generic.List[string]]::new()

    if ($ProfileDir) { $dirs.Add($ProfileDir) }

    $myDocs = [Environment]::GetFolderPath('MyDocuments')
    if ($myDocs) { $dirs.Add((Join-Path $myDocs 'PowerShell')) }

    if ($HOME) {
        foreach ($docName in 'Documents', 'ドキュメント') {
            $docDir = Join-Path $HOME $docName
            $dirs.Add((Join-Path $docDir 'PowerShell'))
        }
    }

    if ($OnWindows -and $env:USERPROFILE -and (Test-Path -LiteralPath $env:USERPROFILE)) {
        $oneDrives = Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Filter 'OneDrive*' -ErrorAction SilentlyContinue
        foreach ($od in $oneDrives) {
            foreach ($docName in 'Documents', 'ドキュメント') {
                $docDir = Join-Path $od.FullName $docName
                if (Test-Path -LiteralPath $docDir) {
                    $dirs.Add((Join-Path $docDir 'PowerShell'))
                }
            }
        }
    }

    $dirs | Where-Object { $_ } | Select-Object -Unique
}

$TargetProfileDirs = Get-PSProfileProfileDirs
$TargetProfiles = foreach ($dir in $TargetProfileDirs) {
    Join-Path $dir 'Microsoft.PowerShell_profile.ps1'
    Join-Path $dir 'Microsoft.VSCode_profile.ps1'
}
$TargetProfiles = $TargetProfiles | Select-Object -Unique

# ───────────────────────────────────────────────────────────── 移行クリーンアップ
# 旧構成のファイルが有効な profile / module path に残ると、起動遅延や proxy 誤設定の原因になる。
# 旧 profile は PSProfile 由来と判定できる場合だけ退避する。
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
    # ユーザーが自分で書いた profile を勝手に消さないため、旧 PSProfile の痕跡がある時だけ true。
    # 文字列マッチだけにして、未知の profile 構文を実行しない。
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
        # install/update/uninstall の整理対象だけを呼び出し側で明示する。
        # 汎用削除関数として広く使わない。ユーザーデータ削除を避けるため。
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
}

# ───────────────────────────────────────────────────────────── Uninstall
if ($Uninstall) {
    Write-Host '■ PSProfile アンインストール' -ForegroundColor Cyan
    Write-Host "  installer v$PSProfileInstallerVersion" -ForegroundColor DarkGray
    foreach ($p in $TargetProfiles) {
        # このインストーラーが配置する CurrentUserCurrentHost と VSCode profile だけを削除する。
        # profile.ps1 など汎用名は MigrationCleanup 側で「旧 PSProfile 由来」と判定できた時だけ退避する。
        if (Test-Path $p) { Remove-Item $p -Force; Write-Host "  - $p" }
    }
    if (Test-Path $ModuleDir) { Remove-Item $ModuleDir -Recurse -Force; Write-Host "  - $ModuleDir" }
    # v2.5.0 以前の一部構成では旧メニュー入口を置いていた。
    # 現行設計では公開入口を px-on / px-off / px-state に絞るため、残っていれば撤去する。
    Remove-PSProfilePath -Path (Join-Path $UserCfgDir 'Manage-PxProxy.ps1') -Label 'legacy shim'
    Invoke-PSProfileMigrationCleanup
    Write-Host '完了。PowerShell を再起動してください。' -ForegroundColor Green
    return
}

# ───────────────────────────────────────────────────────────── モジュール配置 (ステージング→入替)
function Install-PSProfileModule {
    param([Parameter(Mandatory)][string]$SourceDir)
    $srcModule = Join-Path $SourceDir 'modules/PSProfile'
    if (-not (Test-Path (Join-Path $srcModule 'PSProfile.psm1'))) {
        throw "module ソースが不正です: $srcModule"
    }
    if (-not (Test-Path $ModulesRoot)) { New-Item -ItemType Directory -Path $ModulesRoot -Force | Out-Null }

    # 一時ディレクトリに作ってから入替える。途中で失敗しても既存モジュールは無傷。
    # Move-Item による入替は「コピー途中の半端なモジュール」を Import-Module されるリスクを下げる。
    $staging = $ModuleDir + '.new-' + [Guid]::NewGuid().ToString('N')
    $backup  = $ModuleDir + '.old-' + [Guid]::NewGuid().ToString('N')
    if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
    Copy-Item $srcModule $staging -Recurse -Force

    if (Test-Path $ModuleDir) { Move-Item $ModuleDir $backup -Force }
    try {
        Move-Item $staging $ModuleDir -Force
    } catch {
        # 新モジュールへの切替に失敗した場合は旧モジュールを戻す。
        # ここでロールバックできないと、次回 PowerShell 起動時に PSProfile が見つからない。
        if (Test-Path $backup) { Move-Item $backup $ModuleDir -Force }      # ロールバック
        if (Test-Path $staging) { Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue }
        throw
    }
    if (Test-Path $backup) { Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue }
}

try {
    Invoke-PSProfileMigrationCleanup

    Write-Host '■ PSProfile モジュール' -ForegroundColor Cyan
    Write-Host "  installer v$PSProfileInstallerVersion" -ForegroundColor DarkGray
    $SourceDir = Get-PSProfileSourceDir
    if (-not $IsLocal) { Write-Host "  source: $RepoSlug@$Branch (tar.gz)" -ForegroundColor DarkGray }
    Install-PSProfileModule -SourceDir $SourceDir
    Write-Host "  → $ModuleDir"

    # Update モード: モジュールだけで終了
    if ($Update) {
        $installedVersion = $null
        try { $installedVersion = (Import-PowerShellDataFile -Path (Join-Path $ModuleDir 'PSProfile.psd1')).ModuleVersion } catch {}
        if ($installedVersion) { Write-Host "  installed version: v$installedVersion" -ForegroundColor Green }
        Write-Host "  module path: $ModuleDir" -ForegroundColor DarkGray
        Write-Host '完了 (-Update)。新しい PowerShell ターミナルを開いてください。' -ForegroundColor Green
        return
    }

    # ───────────────────────────────────────── プロファイル本体
    Write-Host '■ プロファイル本体' -ForegroundColor Cyan
    $profileSrc = Join-Path $SourceDir 'Microsoft.PowerShell_profile.ps1'
    if (-not (Test-Path -LiteralPath $profileSrc)) {
        throw "profile ソースが見つかりません: $profileSrc"
    }
    foreach ($tp in $TargetProfiles) {
        New-Item -ItemType Directory -Path (Split-Path $tp -Parent) -Force | Out-Null
        Copy-Item $profileSrc $tp -Force
        Write-Host "  → $tp"
    }

    # ───────────────────────────────────────── 依存ツール
    if ($SkipDeps) {
        Write-Host '完了 (-SkipDeps)。新しい PowerShell ターミナルを開いてください。' -ForegroundColor Green
        return
    }

    if (-not $OnWindows) {
        # 非 Windows では winget 前提にしない。
        # profile 本体は動くが、依存ツールは各 OS の標準手段で入れる。
        Write-Host '■ 依存ツール' -ForegroundColor Cyan
        Write-Host '  非 Windows では winget を使いません。starship / zoxide / eza / px は' -ForegroundColor Yellow
        Write-Host '  brew / apt など各 OS のパッケージマネージャで導入してください。' -ForegroundColor Yellow
    } else {
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
                # 既にインストール済みの場合、winget は -1978335189 を返すことがある。
                # それは成功相当として扱い、インストールを冪等にする。
                winget install --id $id -e @wgArgs 2>&1 | Out-Null
                if ($LASTEXITCODE -in 0, -1978335189) {
                    Write-Host "  ✓ $id" -ForegroundColor Green
                } else {
                    Write-Host "  ! $id (exit $LASTEXITCODE)" -ForegroundColor Yellow
                }
            }
        }
    }

    Write-Host ''
    Write-Host '■ 次のステップ' -ForegroundColor Cyan
    Write-Host '  1. 新しい PowerShell ターミナルを開く'
    Write-Host '  2. phelp でコマンド一覧を確認'
    Write-Host '  3. (任意) Nerd Fonts: winget install Microsoft.RobotoMono など'
    Write-Host '  4. px はログオン時タスクで起動 (docs/SETUP.md 参照)。切替は px-on / px-off / px-state'
    Write-Host ''
    Write-Host '完了。' -ForegroundColor Green
}
finally {
    Remove-PSProfileDownloadTmp
}
