$p = 'C:\Program Files\PowerShell\7\pwsh.exe'
Write-Host 'WITH profile:'
1..3 | ForEach-Object { Write-Host ('  {0:N0} ms' -f (Measure-Command { & $p -NoLogo -Command 'exit' }).TotalMilliseconds) }
Write-Host 'NOPROFILE:'
1..3 | ForEach-Object { Write-Host ('  {0:N0} ms' -f (Measure-Command { & $p -NoLogo -NoProfile -Command 'exit' }).TotalMilliseconds) }
