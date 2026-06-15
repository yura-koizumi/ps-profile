# 詳細ベンチ。
# 目的:
#   起動遅延の候補を PATH 走査 / init キャッシュ読み込み / Proxy.ps1 dot-source に分ける。
# 注意:
#   px-on / px-off は呼ばない。Windows Internet Proxy の ProxyEnable は変更しない。
$tot = [Diagnostics.Stopwatch]::StartNew()
if ($env:LOCALAPPDATA) {
    $cacheRoot = Join-Path $env:LOCALAPPDATA 'PSProfile'
    $moduleRoot = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules\PSProfile'
} else {
    $cacheRoot = Join-Path (Join-Path $HOME '.cache') 'PSProfile'
    $moduleRoot = Join-Path (Join-Path (Join-Path $HOME '.local') 'share/powershell/Modules') 'PSProfile'
}

# manual PATH scan timing。
# 実プロファイルの _Find-Exe-Raw に近い方法で starship/zoxide/eza の探索コストを見る。
$sw = [Diagnostics.Stopwatch]::StartNew()
$dirs = $env:PATH -split [regex]::Escape([string][IO.Path]::PathSeparator)
$exts = if ($env:LOCALAPPDATA) { '.exe', '.cmd', '.bat', '.com' } else { '', '.exe', '.cmd', '.bat', '.com' }
$found = @{}
foreach ($t in 'starship', 'zoxide', 'eza') {
    foreach ($d in $dirs) {
        if (-not $d) { continue }
        foreach ($e in $exts) {
            $p = Join-Path $d ($t + $e)
            if (Test-Path -LiteralPath $p -PathType Leaf) { $found[$t] = $p; break }
        }
        if ($found[$t]) { break }
    }
}
Write-Host ('_Find-Exe x3   : {0,6} ms (PATH dirs: {1})' -f $sw.ElapsedMilliseconds, $dirs.Count)

# init cache load timing。
# キャッシュファイルを dot-source する時間だけを見る。外部 exe の init 生成時間は含めない。
$sw.Restart()
$cacheDir = Join-Path $cacheRoot 'init-cache'
foreach ($f in 'starship', 'zoxide') {
    $c = Join-Path $cacheDir "$f.ps1"
    if (Test-Path $c) {
        $s = [Diagnostics.Stopwatch]::StartNew()
        . $c
        Write-Host ('  load {0,-8}: {1,6} ms (size {2} KB)' -f $f, $s.ElapsedMilliseconds, [int]((Get-Item $c).Length / 1KB))
    }
}
Write-Host ('init cache load: {0,6} ms (combined)' -f $sw.ElapsedMilliseconds)

# Proxy.ps1 dot-source timing。
# 関数定義の読み込み時間だけを見る。px-on/px-off は実行しない。
$sw.Restart()
. (Join-Path $moduleRoot 'Proxy.ps1')
Write-Host ('Proxy.ps1      : {0,6} ms' -f $sw.ElapsedMilliseconds)

Write-Host ('────────────────────────────')
Write-Host ('Total (excl Import-Module)  : {0,6} ms' -f $tot.ElapsedMilliseconds)
