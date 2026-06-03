#Requires -Version 7.0
# ─────────────────────────────────────────────────────────────
# PSProfile 端末固有設定テンプレート
# このファイルを ~/.psprofile/user-config.ps1 にコピーして編集してください。
# install.ps1 は既存ファイルを上書きしません。
# ─────────────────────────────────────────────────────────────

# ── 機能フラグ ───────────────────────────────────────────────
# mise (ランタイムバージョン管理) を有効化すると起動が ~1.5s 遅くなる
# $global:PSProfileEnableMise = $true

# ── Proxy 運用モード ────────────────────────────────────────
# 既定では px-on / px-off は現 PowerShell セッションの環境変数だけを変更します。
# VSCode Settings Sync や Git global proxy への影響を避けるため、
# VSCode / Git のグローバル設定は自動変更しません。
# $global:PSProfileDeviceRole = 'Work'      # Work / Private
# $global:PSProfileProxyMode = 'WorkPx'
# $global:PSProfileProxyTargets = @('Env')  # Env / VSCode
# $global:PSProfileSyncVSCodeProxy = $false # または ProxyTargets に VSCode を追加
# $global:PSProfileNoProxy = 'localhost,127.0.0.1'
# $global:PSProfileSetLowercaseProxyEnv = $true
#
# 例: 職場PC + 社内ネットワークで VSCode も明示同期したい場合
# $global:PSProfileDeviceRole = 'Work'
# $global:PSProfileProxyMode = 'WorkPx'
# $global:PSProfileProxyTargets = @('Env', 'VSCode')
#
# 例: 私用PCでは Proxy を使わない
# $global:PSProfileDeviceRole = 'Private'
# $global:PSProfileProxyMode = 'None'
# $global:PSProfileProxyTargets = @('Env')
#
# 例: macOS で一時的に手動 proxy を env にだけ設定する
# $global:PSProfileProxyMode = 'Manual'
# $global:PSProfileProxyUrl = 'http://proxy.example.com:8080'

# ── プロキシ URL の上書き (Px が使えない環境向け) ──
# Px を使う場合は不要。手動でプロキシを指定したい場合のみ設定する。
# $env:HTTP_PROXY  = 'http://proxy.example.com:8080'
# $env:HTTPS_PROXY = $env:HTTP_PROXY
# $env:NO_PROXY    = 'localhost,127.0.0.1,.example.com'

# ── psprofile-update の取得元 URL を上書き (社内 fork など) ──
# $env:PSPROFILE_UPDATE_URL = 'https://internal.example.com/psprofile/install.ps1'

# ── 任意のカスタムエイリアス / 関数 ──
# Set-Alias g git
# function gs { git status @args }
