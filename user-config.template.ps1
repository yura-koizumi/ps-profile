#Requires -Version 7.0
# ─────────────────────────────────────────────────────────────
# PSProfile 端末固有設定テンプレート
# このファイルを ~/.psprofile/user-config.ps1 にコピーして編集してください。
# install.ps1 は既存ファイルを上書きしません。
# ─────────────────────────────────────────────────────────────

# ── まずはここだけ選べばOK ─────────────────────────────────
# 使っているPCに合わせて、次のどれか1つだけコメントを外してください。
#
# 1) 会社PC: px-on / px-off で PC 全体 (PowerShell + ブラウザー + VSCode + 1Password + Codex など) を切り替える
# $global:PSProfileProxyPreset = 'WorkPc'
#
# 2) 会社PC + VSCode設定も明示的に切り替えたい
#    ※ Settings Sync の影響が分かっている場合だけ使ってください
# $global:PSProfileProxyPreset = 'WorkPcWithVSCode'
#
# 3) このPowerShellだけ切り替えたい (デスクトップアプリはWindows側の設定に任せる)
# $global:PSProfileProxyPreset = 'PowerShellOnly'
#
# 4) 私用PC / プロキシを使わない
# $global:PSProfileProxyPreset = 'PrivatePc'
#
# 5) Pxではなく手動プロキシURLを使う (PC全体をそのURLへ向ける)
# $global:PSProfileProxyPreset = 'ManualProxy'
# $global:PSProfileProxyUrl = 'http://proxy.example.com:8080'

# ── よく使う追加設定 ───────────────────────────────────────
# 社内でプロキシを通さない宛先がある場合だけ編集してください。
# $global:PSProfileNoProxy = 'localhost,127.0.0.1,.example.com'

# 起動速度を最優先する端末では、以下を有効にできます。
# $global:PSProfileSkipPSReadLine = $true
# $global:PSProfileEnableStartupBanner = $false

# mise (ランタイムバージョン管理) を有効化すると起動が ~1.5s 遅くなる
# $global:PSProfileEnableMise = $true

# ── 上級者向け: プリセットを使わず細かく指定する場合 ───────
# 通常は PSProfileProxyPreset だけで十分です。
# $global:PSProfileDeviceRole = 'Work'      # Work / Private
# $global:PSProfileProxyMode = 'WorkPx'     # WorkPx / Manual / None
# $global:PSProfileProxyTargets = @('Env', 'System') # Env / System / VSCode
# $global:PSProfileSyncVSCodeProxy = $false # または ProxyTargets に VSCode を追加
# $global:PSProfileSetLowercaseProxyEnv = $true
# $global:PSProfileStopPxProcessOnOff = $false # px-offでPxプロセスも止める場合だけtrue

# ── psprofile-update の取得元 URL を上書き (社内 fork など) ──
# $env:PSPROFILE_UPDATE_URL = 'https://internal.example.com/psprofile/install.ps1'

# ── 任意のカスタムエイリアス / 関数 ──
# Set-Alias g git
# function gs { git status @args }
