@{
  RootModule        = 'PSProfile.psm1'
  ModuleVersion     = '2.0.0'
  GUID              = '07b0e020-9afb-4cda-9f42-bc5be07ab535'
  Author            = 'PSProfile'
  Description       = 'Minimal PowerShell 7 profile: UTF-8, PSReadLine, starship, zoxide, eza, Px proxy (px-on/off/state/restart), phelp, psprofile-update.'
  PowerShellVersion = '7.0'
  FunctionsToExport = @(
    'Show-ProfileHelp',
    'Update-PSProfile',
    'Start-PxProxy', 'Stop-PxProxy', 'Get-PxState', 'Restart-PxProxy',
    'ls', 'll', 'lt'
  )
  AliasesToExport   = @('phelp', 'psprofile-update', 'px-on', 'px-off', 'px-state', 'px-restart')
  CmdletsToExport   = @()
  VariablesToExport = @('ProfileLoadMs')
}
