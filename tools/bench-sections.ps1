# Re-bench with current module logic (matches updated psm1).
# 目的:
#   PSProfile.psm1 の主要 section を、モジュール import なしで手動再現して時間を測る。
# 注意:
#   起動速度の診断用。proxy env / Windows Internet Proxy は変更しない。
#   Proxy.ps1 は dot-source 時間だけ測る。px-on / px-off は呼ばない。
$total = [Diagnostics.Stopwatch]::StartNew()
$marks = [System.Collections.Generic.List[object]]::new()

if ($env:LOCALAPPDATA) {
    $cacheRoot = Join-Path $env:LOCALAPPDATA 'PSProfile'
    $moduleRoot = Join-Path $env:LOCALAPPDATA 'PowerShell\Modules\PSProfile'
} else {
    $cacheRoot = Join-Path (Join-Path $HOME '.cache') 'PSProfile'
    $moduleRoot = Join-Path (Join-Path (Join-Path $HOME '.local') 'share/powershell/Modules') 'PSProfile'
}

function mark($name, $sw) {
    # section 名と経過 ms を保存し、次 section 用に stopwatch をリセットする。
    $marks.Add([pscustomobject]@{ Section = $name; Ms = $sw.ElapsedMilliseconds })
    $sw.Restart()
}

$sw = [Diagnostics.Stopwatch]::StartNew()

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
mark 'encoding' $sw

# PSReadLine inline。
# 実プロファイルと同じ Set-PSReadLineOption / KeyHandler のコストを見る。
try {
    Set-PSReadLineOption -EditMode Windows -PredictionSource History -PredictionViewStyle ListView
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
} catch {}
mark 'PSReadLine inline' $sw

# exe-cache via .ps1。
# 実プロファイルでは starship/zoxide/eza の 3 ツールだけを対象にする。
$cacheFile = Join-Path $cacheRoot 'exe-cache.ps1'
$exe = @{}
if (Test-Path -LiteralPath $cacheFile) {
    $cached = . $cacheFile
    foreach ($t in 'starship', 'zoxide', 'eza') {
        $p = $cached.exes[$t]
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf)) { $exe[$t] = $p } else { $exe[$t] = $null }
    }
}
mark 'exe-cache load (ps1)' $sw

# starship init。
# キャッシュ済み init を dot-source するだけ。starship.exe は起動しない。
if ($exe.starship) {
    $env:STARSHIP_CONFIG = Join-Path $moduleRoot 'starship.toml'
    . (Join-Path (Join-Path $cacheRoot 'init-cache') 'starship.ps1')
}
mark 'starship init' $sw

# zoxide init。
# zoxide.exe は起動せず、キャッシュ済みの PowerShell 初期化コードだけを読む。
if ($exe.zoxide) { . (Join-Path (Join-Path $cacheRoot 'init-cache') 'zoxide.ps1') }
mark 'zoxide init' $sw

# eza aliases。
# Alias:ls を消して function ls/ll/lt を定義する時間だけを見る。
if ($exe.eza) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza --icons --group-directories-first @args }
    function ll { eza -la --icons --group-directories-first --git @args }
    function lt { eza --tree --level=2 --icons --group-directories-first @args }
}
mark 'eza' $sw

# Proxy.ps1 dot-source。
# px-on/px-off は呼ばないため、Internet Proxy の enable/disable は発生しない。
. (Join-Path $moduleRoot 'Proxy.ps1')
mark 'Proxy.ps1' $sw

$total.Stop()
Write-Host ''
Write-Host '== Section timings (post-fix) =='
foreach ($m in $marks) { Write-Host ('  {0,-22} {1,5} ms' -f $m.Section, $m.Ms) }
Write-Host ('  {0,-22} {1,5} ms' -f 'TOTAL', $total.ElapsedMilliseconds)
Write-Host ('  exe resolved: starship={0} zoxide={1} eza={2}' -f [bool]$exe.starship, [bool]$exe.zoxide, [bool]$exe.eza)
