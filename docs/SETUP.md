# Px セットアップ / 撤去手順

社内ネットワークで認証付き社内プロキシを中継するため、ローカル認証中継プロキシ **Px** を使う。
PSProfile の `px-on` / `px-off` / `px-state` は **環境変数と Windows Internet Proxy の切り替えだけ**を行う。
`px-on` は Windows Internet Proxy を
`ProxyEnable=0` から `ProxyEnable=1` に戻して、宛先をローカル Px に向けるだけで、Px 本体は起動しない。
Px 本体の起動はここで設定するログオン時タスクが担当する。

想定: 社内プロキシ `proxy.example.internal:8080` / ローカル Px 待受 `127.0.0.1:3128`

---

## 1. Px をインストール

```powershell
winget install genotrance.px
Get-Command px            # 確認
```

## 2. px.ini を設定

`%USERPROFILE%\.px\px.ini`（代表例）:

```ini
[proxy]
server = proxy.example.internal:8080
listen = 127.0.0.1
port = 3128
gateway = 0
hostonly = 0
allow = 127.0.0.1
noproxy = localhost,127.0.0.1,::1,169.254.169.254
kerberos = 0

[client]
client_auth = NONE
client_nosspi = 0

[settings]
workers = 1
threads = 32
idle = 30
socktimeout = 20.0
proxyreload = 60
foreground = 0
log = 0
```

`server` はサンプル名。実運用では各環境のプロキシホスト名とポートに置き換える。
`allow = 127.0.0.1` で Px を localhost のみに閉じる（外部端末から使わせない）。
`port` を変える場合は `modules/PSProfile/Proxy.ps1` の `Get-PSProfilePxConfig` も合わせる。

## 3. ログオン時に Px を自動起動（タスクスケジューラ）

```powershell
$PxPath = (Get-Command px).Source
$Command = @"
if (-not (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 3128 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath '$PxPath' -WindowStyle Hidden
}
"@
$Action  = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command $Command"
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 0)
Register-ScheduledTask -TaskName 'Start Px Proxy at Logon' -Action $Action -Trigger $Trigger -Settings $Settings `
    -Description 'Start Px local proxy at user logon if not already running.' -Force
```

確認:

```powershell
Get-ScheduledTask -TaskName 'Start Px Proxy at Logon'
Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 3128 -State Listen   # 127.0.0.1:3128 Listen
```

## 4. 日常運用

```powershell
px-on      # 社内: env を設定し、Windows Internet Proxy を ProxyEnable=1 に戻して Px に向ける
px-off     # 社外: 解除
px-state   # 状態確認 (Px 待受 / env / Windows Internet Proxy)
```

メモ:
- PowerShell / VS Code / CLI は User 環境変数の反映に**新規起動**が必要。
- 1Password など GUI アプリは反映が怪しければ再起動。
- `px-state` で `使用中` にならない時は、Px が待受しているか（タスクが動いているか）を確認。

---

## 撤去手順

```powershell
# 1) proxy を無効化
px-off

# 2) 自動起動タスクを削除
Unregister-ScheduledTask -TaskName 'Start Px Proxy at Logon' -Confirm:$false -ErrorAction SilentlyContinue

# 3) Px プロセスを停止 (python.exe / pythonw.exe であることを確認してから)
$ids = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 3128 -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique
$ids | ForEach-Object { Get-Process -Id $_ }          # 確認
$ids | ForEach-Object { Stop-Process -Id $_ -Force }  # 停止

# 4) アンインストール
winget uninstall genotrance.px

# 5) User 環境変数の残存確認 / 削除
'HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY' | ForEach-Object {
    [Environment]::SetEnvironmentVariable($_, $null, 'User')
}

# 6) Windows Internet Proxy
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
    Select-Object ProxyEnable, ProxyServer, ProxyOverride, AutoConfigURL | Format-List
#   ProxyEnable=0 ならOK。会社標準の ProxyServer / ProxyOverride は通常そのまま残す。
```

## 触らないもの

WinHTTP / Machine 環境変数 / Windows Firewall / Azure Arc / サービス環境変数は本運用では変更しない。
サーバー管理は Azure Arc 経由 SSH を使用（Px の対象外）。
