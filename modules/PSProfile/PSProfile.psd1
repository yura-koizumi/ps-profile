@{
  RootModule        = 'PSProfile.psm1'
  ModuleVersion     = '2.5.0'
  GUID              = '07b0e020-9afb-4cda-9f42-bc5be07ab535'
  Author            = 'PSProfile'
  Description       = 'Minimal PowerShell 7 profile: UTF-8, PSReadLine, starship, zoxide, eza, lazy Px proxy (px-on/off/state), phelp, psprofile-update.'
  PowerShellVersion = '7.0'

  # 公開関数は意図的に最小化する。
  # Proxy 系は Start/Stop/Get の 3 関数だけを export し、doctor/restart 系は v2.5 では公開しない。
  # px-on は Start-PxProxy という名前だが、Px プロセス起動ではなく proxy 設定を ON にする関数。
  FunctionsToExport = @(
    'Show-ProfileHelp',
    'Get-PSProfileVersion',
    'Update-PSProfile',
    'Start-PxProxy', 'Stop-PxProxy', 'Get-PxState',
    'ls', 'll', 'lt'
  )
  # 日常操作は alias を主入口にする。
  # px-on / px-off / px-state は短いが、実体は PSProfile.psm1 の薄い stub 経由で Proxy.ps1 に委譲される。
  AliasesToExport   = @('phelp', 'psprofile-version', 'psprofile-update', 'ps-update', 'px-on', 'px-off', 'px-state')
  CmdletsToExport   = @()
  VariablesToExport = @('ProfileLoadMs', 'PSProfileVersion')
}
