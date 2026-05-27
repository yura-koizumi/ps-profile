$sw = [Diagnostics.Stopwatch]::StartNew()
Import-Module PSProfile -Force
$elapsed = $sw.ElapsedMilliseconds
Write-Host ('Import-Module: {0} ms' -f $elapsed)
Write-Host ('Internal load: {0} ms' -f $ProfileLoadMs)
