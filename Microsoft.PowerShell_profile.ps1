#Requires -Version 7.0
# PSProfile entry point. 詳細は modules/PSProfile/PSProfile.psm1 を参照。
# このファイルは $PROFILE として毎回実行されるため、極力薄く保つ。
# 重い処理、proxy 切替、外部ツール初期化は PSProfile モジュール側へ寄せる。

if ($env:PSPROFILE_BENCH -eq '1') { $_t0 = [Environment]::TickCount }

# %LOCALAPPDATA%\PowerShell\Modules は既定の PSModulePath に含まれないため追加 (Windows のみ)。
# 文字列演算のみで cmdlet 呼び出しゼロ → 初回 cmdlet 解決オーバーヘッド (~1.5s) を回避。
# 非 Windows は LOCALAPPDATA が無く、~/.local/share/powershell/Modules が既定で入るため不要。
if ($env:LOCALAPPDATA) {
  # install.ps1 は PSProfile を %LOCALAPPDATA%\PowerShell\Modules に配置する。
  # 端末によってはこのパスが PSModulePath に入っていないため、Import-Module 前に先頭へ足す。
  $_lapModules = $env:LOCALAPPDATA + '\PowerShell\Modules'
  if ($env:PSModulePath -notlike "*$_lapModules*") {
    $env:PSModulePath = $_lapModules + ';' + $env:PSModulePath
  }
  $_lapModules = $null
}

if ($env:PSPROFILE_BENCH -eq '1') { $_t1 = [Environment]::TickCount }

# -ErrorAction SilentlyContinue にしている理由:
# 初回インストール前やモジュール破損時でも PowerShell 起動自体は止めないため。
# 失敗時は phelp 等が出ないので、install.ps1 を再実行して復旧する。
Import-Module PSProfile -ErrorAction SilentlyContinue

if ($env:PSPROFILE_BENCH -eq '1') {
  # $PROFILE 自体の薄さを確認するための計測。
  # モジュール内部の詳細 section は PSProfile.psm1 側で別途表示する。
  $_t2 = [Environment]::TickCount
  Write-Host ''
  Write-Host '── $PROFILE timings ──' -ForegroundColor Yellow
  Write-Host ("  PSModulePath setup      {0,5} ms" -f ($_t1 - $_t0)) -ForegroundColor DarkGray
  Write-Host ("  Import-Module PSProfile {0,5} ms" -f ($_t2 - $_t1)) -ForegroundColor DarkGray
  Remove-Variable _t0, _t1, _t2 -ErrorAction SilentlyContinue
}
