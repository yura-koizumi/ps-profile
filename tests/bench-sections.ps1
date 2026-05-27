# Re-bench with current module logic (matches updated psm1)
$total = [Diagnostics.Stopwatch]::StartNew()
$marks = [System.Collections.Generic.List[object]]::new()
function mark($name, $sw) { $marks.Add([pscustomobject]@{ Section = $name; Ms = $sw.ElapsedMilliseconds }); $sw.Restart() }
$sw = [Diagnostics.Stopwatch]::StartNew()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
mark 'encoding' $sw

# PSReadLine inline
try {
    Set-PSReadLineOption -EditMode Windows -PredictionSource History -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
} catch {}
mark 'PSReadLine inline' $sw

# exe-cache via .ps1
$cacheFile = Join-Path $env:LOCALAPPDATA 'PSProfile\exe-cache.ps1'
$exe = @{}
if (Test-Path -LiteralPath $cacheFile) {
    $cached = . $cacheFile
    foreach ($t in 'starship', 'zoxide', 'eza', 'mise') {
        $p = $cached.exes[$t]
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { $exe[$t] = $p } else { $exe[$t] = $null }
    }
}
mark 'exe-cache load (ps1)' $sw

# starship init
if ($exe.starship) {
    $env:STARSHIP_CONFIG = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules\PSProfile\starship.toml'
    . (Join-Path $env:LOCALAPPDATA 'PSProfile\init-cache\starship.ps1')
}
mark 'starship init' $sw

if ($exe.zoxide) { . (Join-Path $env:LOCALAPPDATA 'PSProfile\init-cache\zoxide.ps1') }
mark 'zoxide init' $sw

if ($exe.eza) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza --icons --group-directories-first @args }
    function ll { eza -la --icons --group-directories-first --git @args }
    function lt { eza --tree --level=2 --icons --group-directories-first @args }
}
mark 'eza' $sw

. 'c:\LocalGit\Code-Repository\012_ps-profile\src\modules\PSProfile\Proxy.ps1'
mark 'Proxy.ps1' $sw

$total.Stop()
Write-Host ''
Write-Host '== Section timings (post-fix) =='
foreach ($m in $marks) { Write-Host ('  {0,-22} {1,5} ms' -f $m.Section, $m.Ms) }
Write-Host ('  {0,-22} {1,5} ms' -f 'TOTAL', $total.ElapsedMilliseconds)
Write-Host ('  exe resolved: starship={0} zoxide={1} eza={2} mise={3}' -f [bool]$exe.starship, [bool]$exe.zoxide, [bool]$exe.eza, [bool]$exe.mise)
