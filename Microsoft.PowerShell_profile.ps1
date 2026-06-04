#Requires -Version 7.0
# PSProfile entry point. 詳細は modules/PSProfile/PSProfile.psm1 を参照。

if ($env:PSPROFILE_BENCH -eq '1') { $_t0 = [Environment]::TickCount }

# %LOCALAPPDATA%\PowerShell\Modules は既定の PSModulePath に含まれないため追加
# 文字列演算のみで cmdlet 呼び出しゼロ → 初回 cmdlet 解決オーバーヘッド (~1.5s) を回避
$_lapModules = $env:LOCALAPPDATA + '\PowerShell\Modules'
if ($env:PSModulePath -notlike "*$_lapModules*") {
  $env:PSModulePath = $_lapModules + ';' + $env:PSModulePath
}
$_lapModules = $null

if ($env:PSPROFILE_BENCH -eq '1') { $_t1 = [Environment]::TickCount }

# 端末固有設定 (任意): ~/.psprofile/user-config.ps1
# PSProfileEnableMise / PSProfileEnableStartupBanner など、モジュール読み込み時に
# 参照される設定があるため Import-Module より先に読み込む。
$_userCfg = $HOME + '\.psprofile\user-config.ps1'
if ([IO.File]::Exists($_userCfg)) { . $_userCfg }
$_userCfg = $null

if ($env:PSPROFILE_BENCH -eq '1') { $_t2 = [Environment]::TickCount }

Import-Module PSProfile -ErrorAction SilentlyContinue

if ($env:PSPROFILE_BENCH -eq '1') {
  $_t3 = [Environment]::TickCount
  Write-Host ''
  Write-Host '── $PROFILE timings ──' -ForegroundColor Yellow
  Write-Host ("  PSModulePath setup     {0,5} ms" -f ($_t1 - $_t0)) -ForegroundColor DarkGray
  Write-Host ("  user-config            {0,5} ms" -f ($_t2 - $_t1)) -ForegroundColor DarkGray
  Write-Host ("  Import-Module PSProfile{0,5} ms" -f ($_t3 - $_t2)) -ForegroundColor DarkGray
  Remove-Variable _t0, _t1, _t2, _t3 -ErrorAction SilentlyContinue
}

