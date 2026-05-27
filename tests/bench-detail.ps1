$tot = [Diagnostics.Stopwatch]::StartNew()

# manual PATH scan timing
$sw = [Diagnostics.Stopwatch]::StartNew()
$dirs = $env:PATH -split ';'
$exts = '.exe', '.cmd', '.bat', '.com'
$found = @{}
foreach ($t in 'starship', 'zoxide', 'eza', 'mise') {
    foreach ($d in $dirs) {
        if (-not $d) { continue }
        foreach ($e in $exts) {
            $p = Join-Path $d ($t + $e)
            if (Test-Path -LiteralPath $p -PathType Leaf) { $found[$t] = $p; break }
        }
        if ($found[$t]) { break }
    }
}
Write-Host ('_Find-Exe x4   : {0,6} ms (PATH dirs: {1})' -f $sw.ElapsedMilliseconds, $dirs.Count)

# init cache load timing
$sw.Restart()
$cacheDir = Join-Path $env:LOCALAPPDATA 'PSProfile\init-cache'
foreach ($f in 'starship', 'zoxide') {
    $c = Join-Path $cacheDir "$f.ps1"
    if (Test-Path $c) {
        $s = [Diagnostics.Stopwatch]::StartNew()
        . $c
        Write-Host ('  load {0,-8}: {1,6} ms (size {2} KB)' -f $f, $s.ElapsedMilliseconds, [int]((Get-Item $c).Length / 1KB))
    }
}
Write-Host ('init cache load: {0,6} ms (combined)' -f $sw.ElapsedMilliseconds)

# Proxy.ps1 dot-source timing
$sw.Restart()
. 'c:\LocalGit\Code-Repository\012_ps-profile\src\modules\PSProfile\Proxy.ps1'
Write-Host ('Proxy.ps1      : {0,6} ms' -f $sw.ElapsedMilliseconds)

Write-Host ('────────────────────────────')
Write-Host ('Total (excl Import-Module)  : {0,6} ms' -f $tot.ElapsedMilliseconds)
