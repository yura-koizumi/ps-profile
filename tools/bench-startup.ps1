# PowerShell 起動全体のベンチ。
# WITH profile:
#   実際の $PROFILE + PSProfile モジュールを読み込む時間。
# NOPROFILE:
#   pwsh.exe 自体の起動時間。WITH - NOPROFILE がプロファイル由来の上乗せ目安。
# 注意:
#   ここでは設定を変更しない。3 回測って cold/warm のばらつきを見るだけ。
$cmd = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $cmd) {
    throw 'pwsh が見つかりません。PowerShell 7 をインストールしてから実行してください。'
}
$p = $cmd.Source

Write-Host "pwsh: $p"
Write-Host 'WITH profile:'
1..3 | ForEach-Object {
    Write-Host ('  {0:N0} ms' -f (Measure-Command { & $p -NoLogo -Command 'exit' }).TotalMilliseconds)
}

Write-Host 'NOPROFILE:'
1..3 | ForEach-Object {
    Write-Host ('  {0:N0} ms' -f (Measure-Command { & $p -NoLogo -NoProfile -Command 'exit' }).TotalMilliseconds)
}
