@{
  RootModule        = 'PSProfile.psm1'
  ModuleVersion     = '2.4.2'
  GUID              = '07b0e020-9afb-4cda-9f42-bc5be07ab535'
  Author            = 'PSProfile'
  Description       = 'Minimal PowerShell 7 profile: UTF-8, PSReadLine, starship, zoxide, eza, safe lazy Px proxy (px-on/off/state/doctor/restart), phelp, psprofile-update.'
  PowerShellVersion = '7.0'
  FunctionsToExport = @(
    'Show-ProfileHelp',
    'Get-PSProfileVersion',
    'Update-PSProfile',
    'Start-PxProxy', 'Stop-PxProxy', 'Get-PxState', 'Invoke-PxDoctor', 'Restart-PxProxy',
    'ls', 'll', 'lt'
  )
  AliasesToExport   = @('phelp', 'psprofile-version', 'psprofile-update', 'ps-update', 'px-on', 'px-off', 'px-state', 'px-doctor', 'px-restart')
  CmdletsToExport   = @()
  VariablesToExport = @('ProfileLoadMs', 'PSProfileVersion')
}
