# PSProfile

軽量を狙った PowerShell 7 プロファイル一式。Px プロキシの社内/社外切り替えを 1 コマンドで行い、
starship / zoxide / eza をオンデマンドで読み込みます。

> 起動時間は端末依存（企業 AV・OneDrive 等で変動）。自己計測は `$env:PSPROFILE_BENCH=1`、
> 詳細は [`docs/STARTUP-TUNING.md`](docs/STARTUP-TUNING.md) 参照。

## 特徴

- **Px プロキシ切り替え**：`px-on` / `px-off` / `px-state` の 3 コマンド（実体は `Proxy.ps1` 1 本）
- **px-on は User 環境変数にも永続化**：新しいターミナルや 1Password などの GUI アプリにも反映
- **プロンプト UI**：`user@host: path` を常時表示し、作業ユーザー・端末・現在パスを判別しやすくする
- **eza / zoxide / starship** をオンデマンドで読み込み（init をキャッシュ）
- **設定ファイルなし**：proxy 値などはコードの定数で決め打ち（`Proxy.ps1`）
- **移行クリーンアップ**で旧モジュール・旧キャッシュ・旧 profile 読み込み口を整理

## インストール

```powershell
# 1 行 (リモート: tar.gz を 1 回取得→展開→配置)
irm 'https://raw.githubusercontent.com/yura-koizumi/ps-profile/main/install.ps1' | iex

# ローカル clone から
.\install.ps1            # フルインストール
.\install.ps1 -SkipDeps  # winget 依存をスキップ
.\install.ps1 -Update    # モジュールだけ更新
.\install.ps1 -Uninstall # 完全削除
```

モジュールは一時ディレクトリにステージングしてから入替えるため、途中で失敗しても既存環境を壊しません。

## コマンド

| コマンド | エイリアス | 説明 |
|---|---|---|
| `Start-PxProxy` | `px-on` | 社内用: 環境変数を設定し、Windows Internet Proxy を `ProxyEnable=1` に戻して Px に向ける |
| `Stop-PxProxy` | `px-off` | 社外用: 環境変数を解除し Windows Internet Proxy を無効化 |
| `Get-PxState` | `px-state` | Px の待受 / 環境変数 / Windows Internet Proxy を表示 |
| `Show-ProfileHelp` | `phelp` | コマンド一覧 |
| `Get-PSProfileVersion` | `psprofile-version` | バージョン / 更新URL / 読み込み元 |
| `Update-PSProfile` | `psprofile-update` / `ps-update` | GitHub から最新版に更新 |
| `ls` / `ll` / `lt` | — | eza ベース一覧（eza がある時のみ） |

## Proxy 運用

Px 本体（ローカル認証中継プロキシ）は **ログオン時のタスクスケジューラ**が起動・常駐させます。
`px-on` / `px-off` は **環境変数と Windows Internet Proxy を切り替えるだけ**で、Px の起動停止はしません。
特に `px-on` は、`px-off` で `ProxyEnable=0` にした Windows Internet Proxy を `ProxyEnable=1` に戻し、
`ProxyServer` をローカル Px に向ける操作です。

```powershell
# 社内ネットワーク (プロキシが要る)
px-on

# 社外 / テザリング / 自宅 (プロキシ不要)
px-off

# いまの状態を確認
px-state
```

設定される値（既定）:

```text
HTTP_PROXY / HTTPS_PROXY / ALL_PROXY = http://127.0.0.1:3128   (User + Process)
NO_PROXY = localhost,127.0.0.1,::1,169.254.169.254
Windows Internet Proxy: ProxyEnable=1, ProxyServer=http://127.0.0.1:3128
```

`px-off` は環境変数を消し `ProxyEnable=0` にします。会社標準が入っていることがある
`ProxyServer` / `ProxyOverride` / `AutoConfigURL` は**消しません**。

> Px の初回セットアップ（インストール / px.ini / ログオン時自動起動 / 撤去手順）は **[docs/SETUP.md](docs/SETUP.md)** を参照。

### 設定（コード定数）

設定ファイル（user-config.ps1）はありません。値はコードに直接書いてあります。

- proxy の URL / ポート / NO_PROXY → `modules/PSProfile/Proxy.ps1` の `Get-PSProfilePxConfig`
- px-on を現セッションのみにしたい → 同ファイルの `Test-PSProfilePersistProxyEnv` を `$false`

## 依存ツール

`install.ps1` が Windows では winget で導入（`-SkipDeps` で抑止）。非 Windows では brew / apt 等で各自。

- `genotrance.px` — Px プロキシ
- `Starship.Starship` — プロンプト
- `ajeetdsouza.zoxide` — スマート cd
- `eza-community.eza` — ls 代替

Nerd Fonts（例 `Microsoft.RobotoMono`）を入れると starship のアイコンが綺麗に出ます。

## 構成

```
install.ps1                         # セットアップ (tar.gz 一括取得 + ステージング入替)
Microsoft.PowerShell_profile.ps1     # $PROFILE 本体 (Import-Module)
modules/PSProfile/
├── PSProfile.psd1 / .psm1          # Core + phelp + update + px スタブ
├── Proxy.ps1                       # px-on/off/state の実体 (遅延ロード)
└── starship.toml                   # tokyo-night テーマ
tests/PSProfile.Tests.ps1           # 最小テスト
tools/                              # 開発ツール導入 + 起動計測ベンチ
docs/                               # 設計・変更履歴・セットアップ手順
```

- 単一モジュール構成。Px エンジン（`Proxy.ps1`）は **px-* を初めて使うまで読み込まない**（遅延ロード）。
- これにより起動時にプロキシ関連のコストを払いません。

## 起動速度の調べ方

```powershell
$env:PSPROFILE_BENCH = '1'; pwsh -NoLogo -Command exit   # section 別の内訳
pwsh -File tools\bench-startup.ps1                        # WITH / NOPROFILE 比較
```

`WITH − NOPROFILE` が大きいのに section 合計が小さい場合、原因はプロファイル外（AV・OneDrive 同期）の
可能性が高く、コードを触っても下がりません。まず内訳で切り分けてください。

## 変更履歴（要点）

- **v2.5** — 二重実装を一本化し、Proxy 操作を `px-on` / `px-off` / `px-state` の 3 コマンドに集約。
  `Proxy.ps1` 1 本へ整理（`Private/Px.*.ps1` と番号入力メニューを廃止）。px はタスク任せ
  （モジュールは起動停止しない）。既定ポート 3128 統一、User 永続化、`install.ps1` を tar.gz 一括
  + ステージング入替に。起動時間の固定値表記を撤廃し実測へ。
- **v2.0** — 旧 3 モジュール（Core/Proxy/DevTools）を単一 `PSProfile` へ統合、init キャッシュ、1 行インストール。

## ライセンス

MIT License
