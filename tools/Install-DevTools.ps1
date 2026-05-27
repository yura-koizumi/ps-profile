#Requires -Version 7.0
<#
.SYNOPSIS
    開発ツール一括インストーラー (旧 dev-install)
.DESCRIPTION
    スタンドアロンスクリプト。PSProfile 本体に依存しない。
    ツールカタログは同フォルダの devtools.json で管理する。

    リモート実行:
        iex (irm 'https://cdn.jsdelivr.net/gh/yura-koizumi/ps-profile@main/tools/Install-DevTools.ps1')
#>
[CmdletBinding()]
param(
    [string]$CatalogUrl = 'https://cdn.jsdelivr.net/gh/yura-koizumi/ps-profile@main/tools/devtools.json'
)

$ErrorActionPreference = 'Stop'

# カタログ取得: ローカル優先、無ければリモート
$catalogPath = Join-Path $PSScriptRoot 'devtools.json'
if (Test-Path $catalogPath) {
    $catalog = Get-Content $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    try {
        $catalog = Invoke-RestMethod -Uri $CatalogUrl -ErrorAction Stop
    } catch {
        Write-Error "カタログ取得失敗: $($_.Exception.Message)"
        return
    }
}

$n = 1; $prev = ''
Write-Host ''
Write-Host '  Install-DevTools' -NoNewline -ForegroundColor White
Write-Host ' ─── 開発ツール一括インストーラー ────────────────' -ForegroundColor DarkGray
foreach ($p in $catalog) {
    if ($p.Cat -ne $prev) {
        Write-Host ''
        Write-Host '  ❯ ' -NoNewline -ForegroundColor Yellow
        Write-Host $p.Cat -ForegroundColor Cyan
        $prev = $p.Cat
    }
    Write-Host ('  {0,3}  ' -f $n) -NoNewline -ForegroundColor DarkGray
    if ($p.Admin) { Write-Host '* ' -NoNewline -ForegroundColor Red } else { Write-Host '  ' -NoNewline }
    Write-Host $p.Name -ForegroundColor Gray
    $n++
}
Write-Host ''
Write-Host '  * = 管理者権限必須' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  入力 › ' -NoNewline -ForegroundColor Yellow
Write-Host '番号をスペース区切り (例: 1 3 5) / all で全部 / Enter でキャンセル' -ForegroundColor DarkGray
$answer = Read-Host '  '
if ([string]::IsNullOrWhiteSpace($answer)) { Write-Host 'キャンセル'; return }

$selected = if ($answer.Trim() -eq 'all') {
    $catalog
} else {
    $answer -split '[\s,]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object {
        $idx = [int]$_ - 1
        if ($idx -ge 0 -and $idx -lt $catalog.Count) { $catalog[$idx] }
    }
}
if (-not $selected) { Write-Host '  有効な番号がありません。'; return }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
$wgArgs = @('--silent', '--accept-source-agreements', '--accept-package-agreements')

Write-Host ''
foreach ($p in $selected) {
    if ($p.Admin -and -not $isAdmin) {
        Write-Host ("  SKIP  {0} — 管理者権限で実行してください" -f $p.Name) -ForegroundColor Yellow
        continue
    }
    Write-Host ("  → {0}..." -f $p.Name) -NoNewline
    if ($p.Type -eq 'winget') {
        winget install --id $p.Id -e @wgArgs 2>&1 | Out-Null
        if ($LASTEXITCODE -in 0, -1978335189) { Write-Host ' OK' -ForegroundColor Green }
        else { Write-Host (" 失敗 (exit $LASTEXITCODE)") -ForegroundColor Red }
    } else {
        try {
            Install-Module $p.Id -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
            Write-Host ' OK' -ForegroundColor Green
        } catch {
            Write-Host (" 失敗: $($_.Exception.Message)") -ForegroundColor Red
        }
    }
}
Write-Host ''
Write-Host '  完了。必要に応じて PowerShell を再起動してください。' -ForegroundColor Green

