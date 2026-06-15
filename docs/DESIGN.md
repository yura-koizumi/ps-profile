# ps-profile 設計書 (v2.5)

> PowerShell 7 向けの軽量プロファイル。Proxy 切り替えは `px-on` / `px-off` / `px-state` の 3 コマンドに絞り、実装を `Proxy.ps1` 1 本へ集約する。

---

## 構成方針

- **単一モジュール**: 旧 `PSProfile.Core` / `PSProfile.Proxy` / `PSProfile.DevTools` を `PSProfile` 1 モジュールに統合。
- **Proxy 遅延ロード**: 起動時は stub だけを定義し、`px-on` / `px-off` / `px-state` の初回呼び出し時に `Proxy.ps1` を dot-source する。
- **Proxy 実装は最小化**: `Proxy.ps1` が env / Windows Internet Proxy / 状態表示を直接担当する。旧 `Private/Px.*.ps1` は廃止。
- **Px 本体はタスク任せ**: モジュールは Px を起動/停止しない。`px-on` は Windows Internet Proxy を `ProxyEnable=1` に戻すだけで、Px の常駐はログオン時タスクや利用者の運用で担保する。
- **設定はコード定数**: proxy URL / port / NO_PROXY は `Proxy.ps1` の `Get-PSProfilePxConfig` を編集する。`user-config.ps1` は使わない。
- **インストールは tar.gz 一括取得 + ステージング入替**: リモート更新時の個別ファイル fetch を避け、途中失敗で既存モジュールを壊さない。
- **DevTools 分離**: 開発ツール導入は `tools/Install-DevTools.ps1` のスタンドアロン処理に分離する。

---

## ディレクトリ構成

```text
install.ps1                         # セットアップ (リモート/ローカル両対応)
README.md
Microsoft.PowerShell_profile.ps1     # $PROFILE 本体 (Import-Module)
docs/
├── DESIGN.md
├── CHANGES.md
├── SETUP.md
└── STARTUP-TUNING.md
modules/PSProfile/
├── PSProfile.psd1
├── PSProfile.psm1                  # 起動高速化 + Proxy stub + phelp + update
├── Proxy.ps1                       # px-on/off/state の実体
└── starship.toml
tools/
├── Install-DevTools.ps1
├── devtools.json
├── bench-startup.ps1
├── bench-sections.ps1
└── bench-detail.ps1
tests/
└── PSProfile.Tests.ps1
```

インストール先:

- Windows: `%LOCALAPPDATA%\PowerShell\Modules\PSProfile\`
- 非 Windows: `~/.local/share/powershell/Modules/PSProfile/`

---

## 公開コマンド

| コマンド | エイリアス | 説明 |
|---|---|---|
| `Show-ProfileHelp` | `phelp` | コマンド一覧表示 |
| `Get-PSProfileVersion` | `psprofile-version` | バージョン / 更新URL / 読み込み元パスを表示 |
| `Update-PSProfile` | `psprofile-update` / `ps-update` | GitHub raw 経由で `install.ps1 -Update` を実行 |
| `Start-PxProxy` | `px-on` | env を設定し、Windows Internet Proxy を `ProxyEnable=1` に戻して Px に向ける |
| `Stop-PxProxy` | `px-off` | env を解除し Windows Internet Proxy を無効化する |
| `Get-PxState` | `px-state` | Px 待受 / env / Windows Internet Proxy を表示 |
| `ls` / `ll` / `lt` | なし | eza がある時だけ定義する一覧コマンド |

`px-doctor`, `px-restart`, `Invoke-PxDoctor`, `Restart-PxProxy` は v2.5 の公開 API ではない。

---

## install.ps1

| パラメータ | 説明 |
|---|---|
| なし | フルインストール (モジュール + プロファイル + 依存ツール案内/導入) |
| `-Update` | モジュールのみ更新 |
| `-Uninstall` | プロファイル / モジュールを削除し、旧シムが残っていれば撤去 |
| `-SkipDeps` | winget 依存導入をスキップ |
| `-Branch <name>` | リモート取得時のブランチ/タグ (既定: `main`) |

ローカル実行時はスクリプト隣接の `modules/PSProfile/PSProfile.psm1` を検出してコピーする。リモート実行時は GitHub の tar.gz を 1 回取得し、展開後に `modules/PSProfile` を探して配置する。

### 移行クリーンアップ

削除対象:

- `%LOCALAPPDATA%\PowerShell\Modules\PSProfile.Core`
- `%LOCALAPPDATA%\PowerShell\Modules\PSProfile.Proxy`
- `%LOCALAPPDATA%\PowerShell\Modules\PSProfile.DevTools`
- `%LOCALAPPDATA%\PSProfile\exe-cache.ps1`
- `%LOCALAPPDATA%\PSProfile\exe-cache.json`
- `%LOCALAPPDATA%\PSProfile\init-cache`
- `%LOCALAPPDATA%\PSProfile\PSProfile.Proxy.px-process.json`

退避対象:

- `$PROFILE` と同じディレクトリにある `profile.ps1`
- `$PROFILE` と同じディレクトリにある `Microsoft.PowerShellISE_profile.ps1`

退避は、旧 PSProfile の痕跡がある場合だけ `~/.psprofile/backups/` に移動する。ユーザー独自 profile は触らない。

---

## 起動速度

固定の起動時間目標は書かない。端末差が大きいため、実測は次を正とする。

```powershell
$env:PSPROFILE_BENCH = '1'; pwsh -NoLogo -Command exit
pwsh -File .\tools\bench-startup.ps1
```

詳細手順は `docs/STARTUP-TUNING.md`。

---

## CHANGELOG

### v2.5

- `src/` の新設計を root layout へ昇格し、二重管理を解消。
- 番号入力メニューを廃止し、実行入口を `px-on` / `px-off` / `px-state` に一本化。
- Proxy 実装を `Proxy.ps1` 1 本に集約し、旧 `Private/Px.*.ps1` を廃止。
- 公開 Proxy API を `px-on` / `px-off` / `px-state` の 3 つに整理。
- `px-on` は Process/User の proxy env と Windows Internet Proxy を設定する。
- `px-off` は Process/User の proxy env を削除し、Windows Internet Proxy を無効化する。
- 既定ポートを `3128` に統一し、`ALL_PROXY` と小文字 env も扱う。
- `install.ps1` を tar.gz 一括取得 + ステージング入替に変更。
