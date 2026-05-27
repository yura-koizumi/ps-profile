#Requires -Version 7.0
# PSProfile entry point. 詳細は modules/PSProfile/PSProfile.psm1 を参照。

# %LOCALAPPDATA%\PowerShell\Modules は既定の PSModulePath に含まれないため追加
$_lapModules = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules'
if ($env:PSModulePath -notlike "*$_lapModules*") {
  $env:PSModulePath = $_lapModules + [IO.Path]::PathSeparator + $env:PSModulePath
}
Remove-Variable _lapModules -ErrorAction SilentlyContinue

Import-Module PSProfile -ErrorAction SilentlyContinue

# 端末固有設定 (任意): ~/.psprofile/user-config.ps1
$_userCfg = Join-Path $HOME '.psprofile\user-config.ps1'
if (Test-Path $_userCfg) { . $_userCfg }
Remove-Variable _userCfg -ErrorAction SilentlyContinue
