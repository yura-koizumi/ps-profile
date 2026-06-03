# PSProfile

軽量で高速な PowerShell 7 プロファイル一式。コールド起動 ~2 秒、ウォーム ~1 秒。

## 特徴

- **単一モジュール構成** (`PSProfile.psd1` / `psm1` / `Proxy.ps1`)
- **Px プロキシ統合** (`px-on` / `px-off` / `px-state` / `px-restart`)
- **eza / zoxide / starship** をオンデマンドで読み込み
- **VSCode / Git のグローバル proxy 設定は既定で変更しない安全設計**
- **`~/.psprofile/user-config.ps1`** で端末固有設定を分離
- **移行クリーンアップ** で旧モジュール・旧キャッシュ・旧 profile 読み込み口を整理

## 1 行インストール

```powershell
iex (irm 'https://cdn.jsdelivr.net/gh/yura-koizumi/ps-profile@main/install.ps1')
```

オプション:

```powershell
.\install.ps1 -SkipDeps   # winget 依存ツールをスキップ
.\install.ps1 -Update     # モジュールだけ更新
.\install.ps1 -Uninstall  # 完全削除
```

## コマンド

| コマンド | エイリアス | 説明 |
|---|---|---|
| `Show-ProfileHelp` | `phelp` | コマンド一覧表示 |
| `Update-PSProfile` | `psprofile-update` | 最新版に更新 |
| `Start-PxProxy` | `px-on` | Px 起動 + 現セッションの環境変数を設定 |
| `Stop-PxProxy` | `px-off` | 環境変数解除 + 管理中 Px 停止 |
| `Get-PxState` | `px-state` | Px / env / VSCode / Git / npm / pip の状態確認 |
| `Invoke-PxDoctor` | `px-doctor` | Px / VPN / Windows proxy の詳細診断 |
| `Restart-PxProxy` | `px-restart` | 再起動 |
| `ls` / `ll` / `lt` | — | eza ベース一覧 |

## Proxy 運用ポリシー

`px-on` / `px-off` は既定で現在の PowerShell セッションだけを変更します。
VSCode Settings Sync や `git config --global` へ影響しないよう、VSCode / Git のグローバル設定は自動変更しません。

Windows の職場 PC で社内ネットワーク上は Px を使い、VSCode の `http.proxy` も明示的に同期したい場合だけ、`~/.psprofile/user-config.ps1` に以下を設定してください。

```powershell
$global:PSProfileDeviceRole = 'Work'
$global:PSProfileProxyMode = 'WorkPx'
$global:PSProfileProxyTargets = @('Env', 'VSCode')
```

macOS や私用PCでは Px を起動しません。Proxy が不要なら以下を設定します。

```powershell
$global:PSProfileDeviceRole = 'Private'
$global:PSProfileProxyMode = 'None'
$global:PSProfileProxyTargets = @('Env')
```

macOS で一時的に手動proxyを使う場合だけ、明示URLを設定します。

```powershell
$global:PSProfileProxyMode = 'Manual'
$global:PSProfileProxyUrl = 'http://proxy.example.com:8080'
```

Git / npm / pip proxy は環境や接続先ごとの差が大きいため自動変更しません。`px-state` で現在値を確認できます。

`px-state` は設定を変更せず、`px.exe`、`px.ini` 候補、ini port、実 listen port、env、VSCode、Git、npm、pip を表示します。
`px-doctor` はさらに Akamai VPN らしき接続、Windows/macOS system proxy / PAC、ローカル port 疎通を診断し、次の推奨アクションを表示します。

状態をログ化したい場合は JSON 出力できます。

```powershell
px-state -Json
px-doctor -Json
```

運用例:

```powershell
# Windows職場PC + 社内ネットワーク: Px を使う
px-on

# 職場PC + Akamai VPN / 外出先、または macOS/私用PC: Proxy を外す
px-off

# どの設定が残っているか確認
px-state
px-doctor
```

私用PCでは `~/.psprofile/user-config.ps1` に以下のように置き、Proxy連動を無効寄りにします。

```powershell
$global:PSProfileDeviceRole = 'Private'
$global:PSProfileProxyMode = 'None'
$global:PSProfileProxyTargets = @('Env')
```

`PSProfileDeviceRole = 'Private'` または `PSProfileProxyMode = 'None'` の場合、`px-on` は proxy を有効化しません。

## 依存ツール

`install.ps1` が winget で以下を自動インストール (`-SkipDeps` で抑止可):

- `genotrance.px` — Px プロキシ
- `Starship.Starship` — プロンプト
- `ajeetdsouza.zoxide` — スマート cd
- `eza-community.eza` — ls 代替

別途お好みで Nerd Fonts (例: `Microsoft.RobotoMono`) を入れると starship のアイコンが綺麗に出ます。

## 移行クリーンアップ

インストール / 更新 / アンインストール時に、リファクタリング前の旧ファイルを整理します。

- 旧モジュール `PSProfile.Core` / `PSProfile.Proxy` / `PSProfile.DevTools` は削除
- 古い起動キャッシュと Px 管理記録は削除
- 旧 profile 読み込み口は PSProfile 由来と判定できる場合だけ `~/.psprofile/backups/` へ退避
- `~/.psprofile/user-config.ps1` は端末固有設定として維持
- VSCode / Git / npm / pip の global proxy 設定は自動変更しない

Git / npm / pip の global proxy は、意図して設定されている可能性があるため自動削除しません。
ただし `px-doctor` は現セッション proxy と矛盾する global proxy を検出し、必要な解除コマンドを表示します。

## アンインストール

```powershell
iex (irm 'https://cdn.jsdelivr.net/gh/yura-koizumi/ps-profile@main/install.ps1') -Uninstall
```

または:

```powershell
.\install.ps1 -Uninstall
```

## ライセンス

MIT License — [LICENSE](LICENSE)

## 設計ドキュメント

詳細は [DESIGN.md](DESIGN.md) を参照。
