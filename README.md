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
irm 'https://raw.githubusercontent.com/yura-koizumi/ps-profile/main/install.ps1' | iex
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
| `Open-PSProfileConfig` | `pconfig` | 設定ファイルを作成して開く |
| `Set-PSProfileProxyPreset` | `ppreset` | `ppreset WorkPc` のようにかんたん設定を保存 |
| `Get-PSProfileVersion` | `psprofile-version` | バージョン / 更新URL / 読み込み元パスを表示 |
| `Update-PSProfile` | `psprofile-update` | 最新版に更新 |
| `Update-PSProfile` | `ps-update` | `psprofile-update` の短縮 alias |
| `Start-PxProxy` | `px-on` | Px 起動 + 指定 target の proxy を設定 |
| `Stop-PxProxy` | `px-off` | 指定 target の proxy を解除/復元 (Px は既定で維持) |
| `Get-PxState` | `px-state` | Px / env / VSCode / Git / npm / pip の状態確認 |
| `Invoke-PxDoctor` | `px-doctor` | Px / VPN / Windows proxy の詳細診断 |
| `Restart-PxProxy` | `px-restart` | 再起動 |
| `ls` / `ll` / `lt` | — | eza ベース一覧 |

## Proxy 運用ポリシー

非IT系ユーザーは **`pconfig` で設定ファイルを開く** か、**`ppreset WorkPc` のように1コマンドで保存** できます。直接編集する場合も `~/.psprofile/user-config.ps1` で `PSProfileProxyPreset` を1つ選ぶだけです。

| プリセット | 使う場面 | `px-on` / `px-off` の影響範囲 |
|---|---|---|
| `WorkPc` | 会社PCの標準 | PowerShell + Windows system proxy (ブラウザー / VSCode / 1Password / Codex など) |
| `WorkPcWithVSCode` | 会社PCで VSCode settings.json も明示同期したい | `WorkPc` + VSCode settings.json |
| `PowerShellOnly` | このPowerShellだけ試したい | PowerShell の環境変数のみ |
| `PrivatePc` | 私用PC / プロキシ不要 | `px-on` は有効化しない |
| `ManualProxy` | Pxではなく手動URLを使う | PowerShell + Windows system proxy を指定URLへ向ける |

例: 会社PCで「PC全体」を切り替える標準設定:

```powershell
ppreset WorkPc
# または user-config.ps1 に以下を書く
$global:PSProfileProxyPreset = 'WorkPc'
```

例: 会社PCで VSCode settings.json も切り替える場合:

```powershell
$global:PSProfileProxyPreset = 'WorkPcWithVSCode'
```

例: 私用PC / プロキシ不要:

```powershell
$global:PSProfileProxyPreset = 'PrivatePc'
```

例: 手動プロキシURLを使う場合:

```powershell
$global:PSProfileProxyPreset = 'ManualProxy'
$global:PSProfileProxyUrl = 'http://proxy.example.com:8080'
```

`WorkPc` では `px-on` が Windows system proxy も Px に向け、`px-off` が直前の system proxy / PAC / override 状態へ復元します。これにより「PowerShell は通るが、VSCode / 1Password / Codex / ブラウザーは通らない」またはその逆の状態を避けやすくします。

VSCode Settings Sync や `git config --global` へ影響しないよう、VSCode / Git / npm / pip のグローバル設定は既定では変更しません。VSCode settings.json も切り替えたい場合だけ `WorkPcWithVSCode` を選んでください。

業務PCで VPN / 社内LAN / 外出先を切り替える際は、プロキシが必要かどうかを利用者が判断して `px-on` / `px-off` を明示実行します。

```powershell
# プロキシが必要なネットワーク
px-on

# プロキシ不要のネットワーク / VPN 側で直接つながる状態
px-off

# Px プロセス自体も再起動したい場合だけ明示的に停止
px-off -StopProcess

# どの設定が残っているか確認
px-state
px-doctor
```

### 上級者向け: target を直接指定する

プリセットを使わずに細かく制御したい場合だけ `PSProfileProxyTargets` を使います。

```powershell
$global:PSProfileDeviceRole = 'Work'
$global:PSProfileProxyMode = 'WorkPx'
$global:PSProfileProxyTargets = @('Env', 'System') # Env / System / VSCode
```

`PSProfileDeviceRole = 'Private'` または `PSProfileProxyMode = 'None'` の場合、`px-on` は proxy を有効化しません。`px-off` は他のターミナルやツールの通信を壊さないよう、既定では Px プロセスを止めず、指定 target の proxy 状態だけを解除・復元します。

起動速度を優先するため、`starship` / `zoxide` / `eza` は起動時にまとめて初期化しません。`zoxide` と `eza` は初回利用時に解決し、`starship` は見た目用途のため opt-in です。Windows 起動直後のシェル起動をさらに軽くしたい場合は、同じ `user-config.ps1` で任意機能を省略できます。

```powershell
$global:PSProfileSkipPSReadLine = $true        # PSReadLine のキー設定を省略
$global:PSProfileEnableStartupBanner = $false # "phelp" バナーを非表示
$global:PSProfileEnableStarship = $true       # starship が必要な場合だけ有効化
```

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

## バージョン確認 / 更新

現在読み込まれている PSProfile のバージョン、更新URL、モジュールパスは以下で確認できます。

```powershell
psprofile-version
```

`psprofile-update` は GitHub raw から `install.ps1` を取得し、更新先の `ModuleVersion` を確認してから実行します。`-Update` ではモジュールだけでなく管理対象の PowerShell profile 本体も更新するため、`user-config.ps1` の早期読み込みなどの修正も反映されます。

```powershell
psprofile-update
```

取得先が現在と同じバージョンの場合は誤更新を避けるため停止します。同じバージョンを再インストールして profile 本体も入れ直したい場合は `-Force` を付けます。

```powershell
psprofile-update -Force
```

PR / 検証ブランチ / 社内 fork から更新したい場合は branch または URL を明示します。

```powershell
psprofile-update -Branch main
$env:PSPROFILE_UPDATE_BRANCH = 'main'
# $env:PSPROFILE_UPDATE_URL = 'https://raw.githubusercontent.com/<owner>/<repo>/<branch>/install.ps1'
```

もし古い `psprofile-update` 自体が残っている場合は、次の 1 行で直接更新できます。

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/yura-koizumi/ps-profile/main/install.ps1'))) -Update
```


### `psprofile-update` しても古いバージョンのままの場合

表示が次のように `installer v2.1.0` / `installed version: v2.4.1` のままなら、PC 側の問題ではなく **取得先の `main` がまだ v2.4.1** です。

```text
PSProfile current: v2.4.1
PSProfile update:  https://raw.githubusercontent.com/yura-koizumi/ps-profile/main/install.ps1
installer v2.1.0
installed version: v2.4.1
```

この場合、`psprofile-update` は `main` の raw ファイルを正しく取得していますが、`main` 側に新しい修正がまだ入っていないため更新されません。修正 PR / 検証ブランチを先に試す場合は、古い `psprofile-update` を使わずに次の 1 行で branch を明示します。

```powershell
$branch = '<修正が入っているブランチ名>'
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/yura-koizumi/ps-profile/$branch/install.ps1?cacheBust=$(Get-Date -Format yyyyMMddHHmmss)"))) -Update -Branch $branch
```

新しい `psprofile-update` が入った後は、通常の `psprofile-update -Branch <branch>` または `psprofile-update -Force` が使えます。

## アンインストール

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/yura-koizumi/ps-profile/main/install.ps1'))) -Uninstall
```

または:

```powershell
.\install.ps1 -Uninstall
```

## ライセンス

MIT License — [LICENSE](LICENSE)

## 設計ドキュメント

詳細は [DESIGN.md](DESIGN.md) を参照。
