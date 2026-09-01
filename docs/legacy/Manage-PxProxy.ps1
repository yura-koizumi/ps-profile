<#
Manage-PxProxy.ps1 — 互換シム (compatibility shim)

かつての単独スクリプトは、PSProfile モジュールの px-on / px-off / px-state を
呼ぶだけの薄いラッパーになりました。番号メニュー (1 / 2 / 3) と日常の操作感は
そのままです。実体は modules/PSProfile/Proxy.ps1 です。

  & 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'        # メニュー
  & 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1' Enable # 非対話
  & 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1' Status

なぜシムにしたか:
  以前は同じ目的の proxy 切り替えが「このスクリプト」と「PSProfile モジュール」の
  2 か所にあり、挙動 (env の保存スコープ・WinINET の形式・ポート) が食い違っていた。
  モジュール側の方が高機能 (WinINET host:port + 変更通知 + 復元 + 診断) なので、
  実装をモジュールへ一本化し、このメニューは入口として残した。
#>
param(
    [ValidateSet('Enable', 'Disable', 'Status')]
    [string]$Mode
)

# プロファイル未経由 (素の pwsh から &) でも動くよう、必要ならモジュールを読み込む。
if (-not (Get-Command Get-PxState -ErrorAction SilentlyContinue)) {
    Import-Module PSProfile -ErrorAction SilentlyContinue
}
if (-not (Get-Command Get-PxState -ErrorAction SilentlyContinue)) {
    Write-Warning 'PSProfile モジュールが見つかりません。install.ps1 を実行してから再度お試しください。'
    return
}

if (-not $Mode) {
    Write-Host ''
    Write-Host '=== Px Proxy Menu ==='
    Write-Host '1. Enable  - 社内用: Px proxy を有効化 (px-on)'
    Write-Host '2. Disable - 社外用: Px proxy を無効化 (px-off)'
    Write-Host '3. Status  - 現在状態を表示 (px-state)'
    Write-Host ''

    switch (Read-Host '番号を入力してください') {
        '1' { $Mode = 'Enable' }
        '2' { $Mode = 'Disable' }
        '3' { $Mode = 'Status' }
        default {
            Write-Host '無効な番号です。処理を終了します。'
            return
        }
    }
}

switch ($Mode) {
    'Enable'  { Start-PxProxy }   # px-on
    'Disable' { Stop-PxProxy }    # px-off
    'Status'  { Get-PxState }     # px-state
}
