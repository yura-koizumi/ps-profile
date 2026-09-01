# Px Proxy 管理スクリプト運用メモ

> **【v2.5 更新】`Manage-PxProxy.ps1` は互換シムになりました。**
> 番号メニュー (1=Enable / 2=Disable / 3=Status) と操作感はそのままですが、実体は PSProfile モジュールの
> `px-on` / `px-off` / `px-state` を呼びます。`px-on` は **User 環境変数にも永続化**するため、以前は手動だった
> 新ターミナルへの反映が自動になりました。また WinINET の変更通知を出すので、**1Password などの GUI アプリは
> 原則再起動不要**です（反映が怪しいときのみ再起動）。本書の Px 本体・px.ini・自動起動・撤去手順は引き続き有効です。

## 目的

社内ネットワークでは、外部通信に社内プロキシ認証が必要になる。
一部の CLI / 開発ツール / 1Password などを安定して通信させるため、ローカル認証中継プロキシとして Px を使用する。

この運用では、以下を切り替える。

* User 環境変数

  * `HTTP_PROXY`
  * `HTTPS_PROXY`
  * `ALL_PROXY`
  * `NO_PROXY`
* Windows Internet Proxy

  * `inetcpl.cpl`
  * WinINet 系アプリ向け
  * 1Password など

## スクリプト

対象スクリプト:

```powershell
C:\LocalGit\ps-profile\Manage-PxProxy.ps1
```

実行方法:

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

モードを忘れてもよいように、スクリプト実行時に番号メニューを表示する。

```text
=== Px Proxy Menu ===
1. Enable  - 社内用: Px proxy を有効化
2. Disable - 社外用: Px proxy を無効化
3. Status  - 現在状態を表示
```

## モードの意味

### 1. Enable

社内ネットワークで使用する。

実施内容:

* User 環境変数を Px に向ける
* Windows Internet Proxy も Px に向ける
* Px 本体の起動停止はしない
* WinHTTP は変更しない
* Machine 環境変数は変更しない

設定される主な値:

```text
HTTP_PROXY=http://127.0.0.1:3128
HTTPS_PROXY=http://127.0.0.1:3128
ALL_PROXY=http://127.0.0.1:3128
NO_PROXY=localhost,127.0.0.1,::1,169.254.169.254
```

Windows Internet Proxy:

```text
ProxyEnable=1
ProxyServer=http://127.0.0.1:3128
```

用途:

* PowerShell
* Git
* CLI ツール
* Codex / VS Code 系
* 1Password など WinINet / Internet Options を見るアプリ

### 2. Disable

社外、テザリング、自宅など、社内プロキシが不要な環境で使用する。

実施内容:

* User 環境変数の Proxy 設定を削除する
* Windows Internet Proxy を無効化する
* `ProxyServer` / `ProxyOverride` / `AutoConfigURL` は基本的に削除しない
* Px 本体は停止しない

Windows Internet Proxy:

```text
ProxyEnable=0
```

用途:

* 社外ネットワーク
* テザリング
* 自宅ネットワーク
* Px を通す必要がない場合

### 3. Status

現在状態を確認する。

確認する内容:

* Px が `127.0.0.1:3128` で Listen しているか
* Px のプロセスが `python.exe` または `pythonw.exe` か
* User / Process / Machine の Proxy 環境変数
* Windows Internet Proxy の状態

期待される社内利用時の状態:

```text
Px State: 使用中
```

```text
Px Listener:
127.0.0.1:3128 Listen
```

```text
HTTP_PROXY=http://127.0.0.1:3128
HTTPS_PROXY=http://127.0.0.1:3128
ALL_PROXY=http://127.0.0.1:3128
NO_PROXY=localhost,127.0.0.1,::1,169.254.169.254
```

```text
ProxyEnable=1
ProxyServer=http://127.0.0.1:3128
```

## Px 本体について

このスクリプトは Px 本体を起動・停止しない。

Px が起動しているかは、Status で確認する。

```text
127.0.0.1:3128 Listen
```

プロセス例:

```text
pythonw.exe
```

Px が起動していない状態で Enable だけされている場合、通信は失敗する。
その場合は Px の自動起動設定または手動起動を確認する。

## Windows Internet Proxy も切り替える理由

1Password は User 環境変数だけでは Px 経由にならないことがあった。
検証の結果、1Password は Windows Internet Options / WinINet 系の設定を見る可能性が高い。

そのため、Enable 時には User 環境変数だけでなく、Windows Internet Proxy も Px に向ける。

```text
ProxyEnable=1
ProxyServer=http://127.0.0.1:3128
```

Disable 時は社外利用を想定し、Windows Internet Proxy を無効化する。

```text
ProxyEnable=0
```

## 触らないもの

このスクリプトでは以下を変更しない。

* WinHTTP
* Machine 環境変数
* Px 本体の起動停止
* Windows Firewall
* Azure Arc
* Tailscale
* サービス環境変数

## Tailscale について

Tailscale は検証の結果、社内 LAN では controlplane / DERP / UDP 経路が成立しなかった。

テザリングでは正常に動作したため、Windows Firewall や端末側の問題ではなく、社内ネットワーク経路・プロキシ・出口制御側の問題と判断した。

現在は Tailscale をアンインストール済み。
サーバー管理は Azure Arc 経由 SSH を使用する。

## Azure Arc について

サーバー管理は Azure Arc 経由で実施する。

Azure Arc はこのスクリプトの管理対象外。
Px Proxy の Enable / Disable で Azure Arc の設定は変更しない。

## 日常運用

### 社内にいるとき

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

メニューで `1` を選択。

```text
1. Enable
```

### 社外にいるとき

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

メニューで `2` を選択。

```text
2. Disable
```

### 状態確認

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

メニューで `3` を選択。

```text
3. Status
```

## 注意点

* PowerShell / VS Code / CLI は、User 環境変数変更後に新しく起動する。
* 1Password など GUI アプリは、Proxy 設定変更後に再起動する。
* 反映が怪しい場合はサインアウト / サインインする。
* `TimeWait` や `FinWait2` は TCP の終了処理なので、Status では `Listen` のみを見る。
* `ProxyOverride` は会社標準設定が長いため、原則変更しない。

# 環境構築手順

## 前提

この手順は、社内ネットワークで Px を使って認証付き社内プロキシを中継するための環境構築手順である。

想定する社内プロキシ:

```text
proxy-ski.jp.sharp:3080
```

ローカル Px の待受:

```text
127.0.0.1:3128
```

Px 管理スクリプト:

```powershell
C:\LocalGit\ps-profile\Manage-PxProxy.ps1
```

## 1. Px をインストールする

winget で Px をインストールする。

```powershell
winget install genotrance.px
```

インストール後、`px` コマンドが見えるか確認する。

```powershell
Get-Command px
```

## 2. px.ini を設定する

Px の設定ファイルを開く。

代表的な配置例:

```text
%USERPROFILE%\.px\px.ini
```

設定例:

```ini
[proxy]
server = proxy-ski.jp.sharp:3080
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

重要点:

```text
allow = 127.0.0.1
```

外部端末から使わせる目的ではないため、Px は localhost のみに閉じる。

## 3. Px を起動する

手動起動する場合:

```powershell
px
```

または、Windows Terminal / PowerShell から起動して、別ウィンドウで待受確認する。

```powershell
Get-NetTCPConnection `
    -LocalAddress 127.0.0.1 `
    -LocalPort 3128 `
    -State Listen
```

期待値:

```text
127.0.0.1  3128  Listen
```

## 4. Px をサインイン時に自動起動する

必要に応じて、タスクスケジューラーで Px をサインイン時に自動起動する。

```powershell
$PxPath = (Get-Command px).Source

$Command = @"
if (-not (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 3128 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process -FilePath '$PxPath' -WindowStyle Hidden
}
"@

$Action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command $Command"

$Trigger = New-ScheduledTaskTrigger -AtLogOn

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0)

Register-ScheduledTask `
    -TaskName 'Start Px Proxy at Logon' `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description 'Start Px local proxy at user logon if not already running.' `
    -Force
```

確認:

```powershell
Get-ScheduledTask -TaskName 'Start Px Proxy at Logon'
```

## 5. Manage-PxProxy.ps1 を配置する

スクリプトを以下に配置する。

```text
C:\LocalGit\ps-profile\Manage-PxProxy.ps1
```

スクリプトの役割:

```text
Enable:
  User 環境変数を Px に向ける
  Windows Internet Proxy を Px に向ける

Disable:
  User 環境変数を削除する
  Windows Internet Proxy を無効化する

Status:
  現在状態を表示する
```

実行:

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

メニュー:

```text
1. Enable  - 社内用: Px proxy を有効化
2. Disable - 社外用: Px proxy を無効化
3. Status  - 現在状態を表示
```

## 6. 社内利用時に Enable する

社内ネットワークでは、スクリプトを実行して `1` を選択する。

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

```text
1
```

期待される状態:

```text
HTTP_PROXY=http://127.0.0.1:3128
HTTPS_PROXY=http://127.0.0.1:3128
ALL_PROXY=http://127.0.0.1:3128
NO_PROXY=localhost,127.0.0.1,::1,169.254.169.254
```

Windows Internet Proxy:

```text
ProxyEnable=1
ProxyServer=http://127.0.0.1:3128
```

## 7. 社外利用時に Disable する

社外、テザリング、自宅では、スクリプトを実行して `2` を選択する。

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

```text
2
```

期待される状態:

```text
User 環境変数の Proxy 設定なし
ProxyEnable=0
```

## 8. 状態確認する

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

```text
3
```

社内利用時の期待値:

```text
Px State: 使用中
```

```text
127.0.0.1:3128 Listen
```

```text
ProxyEnable=1
ProxyServer=http://127.0.0.1:3128
```

# 壊し方・撤去手順

## 目的

Px 関連の設定を無効化し、端末を通常のネットワーク利用状態に戻す。

この手順では、以下を順に実施する。

```text
1. スクリプトで Proxy を無効化
2. 自動起動タスクを削除
3. Px プロセスを停止
4. Px をアンインストール
5. 残存設定を確認
```

## 1. まずスクリプトで Disable する

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

メニューで `2` を選択する。

```text
2
```

これにより、以下が実施される。

```text
User 環境変数の Proxy 設定を削除
Windows Internet Proxy を無効化
```

確認:

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

メニューで `3` を選択する。

期待値:

```text
ProxyEnable=0
```

## 2. Px 自動起動タスクを削除する

タスクスケジューラーに登録している場合は削除する。

```powershell
Unregister-ScheduledTask `
    -TaskName 'Start Px Proxy at Logon' `
    -Confirm:$false `
    -ErrorAction SilentlyContinue
```

確認:

```powershell
Get-ScheduledTask `
    -TaskName 'Start Px Proxy at Logon' `
    -ErrorAction SilentlyContinue
```

何も返らなければ削除済み。

## 3. Px プロセスを停止する

`127.0.0.1:3128` を Listen しているプロセスを確認する。

```powershell
$PxProcessIds = Get-NetTCPConnection `
    -LocalAddress 127.0.0.1 `
    -LocalPort 3128 `
    -State Listen `
    -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique

$PxProcessIds | ForEach-Object {
    Get-Process -Id $_
}
```

Px の `python.exe` または `pythonw.exe` であることを確認して停止する。

```powershell
$PxProcessIds | ForEach-Object {
    Stop-Process -Id $_ -Force
}
```

再確認:

```powershell
Get-NetTCPConnection `
    -LocalAddress 127.0.0.1 `
    -LocalPort 3128 `
    -State Listen `
    -ErrorAction SilentlyContinue
```

何も返らなければ停止済み。

## 4. Px をアンインストールする

winget でアンインストールする。

```powershell
winget uninstall genotrance.px
```

確認:

```powershell
Get-Command px -ErrorAction SilentlyContinue
```

何も返らなければ、`px` コマンドは削除済み。

## 5. User 環境変数の残存確認

```powershell
'HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY' | ForEach-Object {
    [pscustomobject]@{
        Name    = $_
        User    = [Environment]::GetEnvironmentVariable($_, 'User')
        Machine = [Environment]::GetEnvironmentVariable($_, 'Machine')
    }
}
```

期待値:

```text
User 側に HTTP_PROXY / HTTPS_PROXY / ALL_PROXY / NO_PROXY が残っていない
Machine 側にも意図しない proxy がない
```

残っている場合は削除する。

```powershell
'HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY' | ForEach-Object {
    [Environment]::SetEnvironmentVariable($_, $null, 'User')
}
```

## 6. Windows Internet Proxy の確認

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
    Select-Object ProxyEnable, ProxyServer, ProxyOverride, AutoDetect, AutoConfigURL |
    Format-List
```

期待値:

```text
ProxyEnable=0
```

`ProxyServer` や `ProxyOverride` が残っていても、`ProxyEnable=0` なら通常は使用されない。

完全に削除したい場合のみ、以下を実施する。

```powershell
Remove-ItemProperty `
    -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' `
    -Name ProxyServer `
    -ErrorAction SilentlyContinue
```

ただし、会社標準設定があるため、通常は `ProxyServer` や `ProxyOverride` は削除しない。

## 7. スクリプト自体を削除する

不要になった場合のみ削除する。

```powershell
Remove-Item 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1' -Force
```

README も不要なら削除する。

```powershell
Remove-Item 'C:\LocalGit\ps-profile\README-PxProxy.md' -Force
```

## 8. 最終確認

```powershell
Get-NetTCPConnection `
    -LocalAddress 127.0.0.1 `
    -LocalPort 3128 `
    -State Listen `
    -ErrorAction SilentlyContinue
```

何も返らないこと。

```powershell
Get-Command px -ErrorAction SilentlyContinue
```

何も返らないこと。

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' |
    Select-Object ProxyEnable, ProxyServer |
    Format-List
```

`ProxyEnable=0` であること。

# 切り戻し方

Px を再利用する場合は、以下の順で戻す。

```text
1. winget install genotrance.px
2. px.ini を設定
3. Px を起動
4. Manage-PxProxy.ps1 を配置
5. スクリプトを実行して Enable
6. Status で確認
```

確認コマンド:

```powershell
& 'C:\LocalGit\ps-profile\Manage-PxProxy.ps1'
```

メニューで `3` を選択し、以下を確認する。

```text
Px State: 使用中
127.0.0.1:3128 Listen
ProxyEnable=1
ProxyServer=http://127.0.0.1:3128
```
