# ps-profile 設計書 (v2.0)

> 最小構成・高速起動・どの端末にも 1 行でインストール可能を目標とした PowerShell 7 カスタムプロファイル。

---

## 構成方針

- **単一モジュール**: 旧 3 モジュール (Core/Proxy/DevTools) を `PSProfile` 1 モジュールに統合
- **Proxy 遅延ロード**: `px-on` 等は初回呼び出し時に `Proxy.ps1` を dot-source するスタブ
- **DevTools 分離**: プロファイル起動に依存しないスタンドアロンスクリプト `tools/Install-DevTools.ps1`
- **プロキシ同期は 2 層のみ**: 環境変数 + VSCode `settings.json` (WinINET 廃止)
- **端末固有設定**: `~/.psprofile/user-config.ps1` (Git 追跡対象外)
- **インストール**: `iex (irm ...)` 1 行で完結。`psprofile-update` で自己更新

---

## ディレクトリ構成

```
src/
├── install.ps1                       # セットアップ (リモート/ローカル両対応)
├── Microsoft.PowerShell_profile.ps1  # $PROFILE 本体 (Import-Module + user-config)
├── user-config.template.ps1          # 端末固有設定テンプレ
├── DESIGN.md                         # 本書
├── modules/
│   └── PSProfile/
│       ├── PSProfile.psd1
│       ├── PSProfile.psm1            # Core + Proxy スタブ + phelp + update
│       ├── Proxy.ps1                 # 遅延ロード本体 (px-on/off/state/restart)
│       └── starship.toml             # tokyo_night テーマ
├── tools/
│   ├── Install-DevTools.ps1          # 開発ツール一括インストーラー (スタンドアロン)
│   └── devtools.json
└── tests/
    └── PSProfile.Tests.ps1
```

インストール先: `%LOCALAPPDATA%\PowerShell\Modules\PSProfile\`

---

## 公開コマンド

| コマンド | エイリアス | 説明 |
|---|---|---|
| `Show-ProfileHelp` | `phelp` | コマンド一覧表示 |
| `Update-PSProfile` | `psprofile-update` | jsdelivr 経由で `install.ps1 -Update` を実行 |
| `Start-PxProxy` | `px-on` | px 起動 + 環境変数 + VSCode 同期 (lazy) |
| `Stop-PxProxy` | `px-off` | px 停止 + 環境変数解除 (lazy, `-KeepProcess` でプロセス維持) |
| `Get-PxState` | `px-state` | 状態表示 (`-Edit` で px.ini を開く) |
| `Restart-PxProxy` | `px-restart` | px-off → px-on (lazy) |
| `ls` / `ll` / `lt` | — | eza ベース一覧 (eza インストール時のみ) |

## 起動高速化

| 施策 | 効果 (目安) |
|---|---|
| Import-Module 1 回のみ (旧 3 回) | 約 -400ms |
| PSReadLine を OnIdle 遅延 | 約 -1000ms |
| starship/zoxide init をキャッシュ化 | 約 -3000ms |
| mise を opt-in | 約 -1500ms |
| `$env:PATH` 直接走査 | 約 -200ms |
| Proxy 関数を遅延ロード | 約 -50ms |

目標: 10000ms 超 → 1000ms 未満。

---

## 旧コマンドからの移行

| 旧 | 新 |
|---|---|
| `px-env` | `px-on` (環境変数だけ再設定する挙動を内包) |
| `px-config` | `px-state -Edit` |
| `px-ini` | `px-state` (ini path / port を同一表示) |
| WinINET 系 | **廃止** (env + VSCode のみに簡素化) |
| `which` / `fh` / `h` | **廃止** (`Get-Command` / `Get-History` / `Ctrl+R` で代替) |
| `dev-install` | `pwsh -File <repo>/src/tools/Install-DevTools.ps1` |

---

## install.ps1

| パラメータ | 説明 |
|---|---|
| (なし) | フルインストール (モジュール + プロファイル + winget 4 本) |
| `-Update` | モジュールのみ更新 |
| `-Uninstall` | 全削除 |
| `-SkipDeps` | winget をスキップ |
| `-Branch <name>` | リモート取得時のブランチ/タグ (既定: main) |

リモート/ローカル自動判定: スクリプト隣接に `modules/PSProfile/PSProfile.psm1` があればローカルコピー、無ければ jsdelivr CDN から取得。

### winget 依存ツール (4 本)

`genotrance.px` / `Starship.Starship` / `ajeetdsouza.zoxide` / `eza-community.eza`

Nerd Fonts は **手動インストール推奨**。Windows Terminal 設定の自動改変も行わない。

---

## user-config.ps1 (端末固有)

`Microsoft.PowerShell_profile.ps1` 末尾で `~/.psprofile/user-config.ps1` を条件付き dot-source。初回 install 時に `user-config.template.ps1` がコピーされる (既存は維持)。

主な用途:
- `$global:PSProfileEnableMise = $true` で mise opt-in
- プロキシ URL の上書き
- `$env:PSPROFILE_UPDATE_URL` で fork からの更新
- カスタムエイリアス / 関数

---

## CHANGELOG

### v2.0 (大規模再設計)

- 3 モジュール → 単一 `PSProfile` モジュールへ統合
- Proxy / DevTools / WinINET / `which` / `fh` / `h` / `px-env` / `px-ini` / `px-config` 等を整理 (上の移行表参照)
- starship/zoxide init をキャッシュ化、PSReadLine を OnIdle 遅延、mise opt-in 化
- `install.ps1` 全面書き直し: `-Update` / `-Uninstall` / `-SkipDeps` / `-Branch`、jsdelivr 経由リモート対応
- `psprofile-update` 自己更新コマンドを追加
- `user-config.ps1` 仕組みを導入 (端末固有設定の分離)
- Bootstrap.cmd / Nerd Fonts 自動 DL / WT settings.json 自動改変を削除
- `$PROFILE` 本体を 5 行に短縮 (`Import-Module PSProfile` + user-config 読込のみ)
