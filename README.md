# PSProfile

軽量で高速な PowerShell 7 プロファイル一式。コールド起動 ~2 秒、ウォーム ~1 秒。

## 特徴

- **単一モジュール構成** (`PSProfile.psd1` / `psm1` / `Proxy.ps1`)
- **Px プロキシ統合** (`px-on` / `px-off` / `px-state` / `px-restart`)
- **eza / zoxide / starship** をオンデマンドで読み込み
- **VSCode の `http.proxy` を自動同期**
- **`~/.psprofile/user-config.ps1`** で端末固有設定を分離

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
| `Start-PxProxy` | `px-on` | Px 起動 + 環境変数 + VSCode 同期 |
| `Stop-PxProxy` | `px-off` | Px 停止 + 環境変数解除 |
| `Get-PxProxyState` | `px-state` | 状態確認 |
| `Restart-PxProxy` | `px-restart` | 再起動 |
| `ls` / `ll` / `lt` | — | eza ベース一覧 |

## 依存ツール

`install.ps1` が winget で以下を自動インストール (`-SkipDeps` で抑止可):

- `genotrance.px` — Px プロキシ
- `Starship.Starship` — プロンプト
- `ajeetdsouza.zoxide` — スマート cd
- `eza-community.eza` — ls 代替

別途お好みで Nerd Fonts (例: `Microsoft.RobotoMono`) を入れると starship のアイコンが綺麗に出ます。

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
