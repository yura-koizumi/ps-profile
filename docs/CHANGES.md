# 変更サマリー — v2.4.2 → v2.5.0

v2.5.0 は、旧実装と `src/` 新設計の二重管理を解消し、Proxy 周りを最小構成へ整理するリリースです。

---

## 0. 追記 — 標準導入の固定化

- 標準導入を `install.ps1` の固定 manifest に一本化し、`Git` / `GitHub CLI` / `Visual Studio Code` / `Node.js LTS` / `Python 3` / `.NET SDK` / `Px` を共通基盤として扱うようにした。
- `starship` / `zoxide` / `eza` / `fzf` / `mise` のような shell 拡張は標準導入から外し、別インストーラーも削除した。
- `tools/Install-DevTools.ps1` / `tools/devtools.json` / `tools/bench-detail.ps1` / `tools/bench-sections.ps1` を削除し、標準導入の入口を 1 本化した。

---

## 1. `src/` を root layout へ昇格

- `src/` の新設計を root layout に昇格し、実行入口は `install.ps1`、profile 雛形は root、文書は `docs/` に整理。
- 昇格後の `src/` は削除し、正本を root layout に一本化。
- バージョンを `2.5.0` に統一。

## 2. Proxy 実装を 1 本化

- 番号入力メニューを廃止し、公開入口を `Start-PxProxy` / `Stop-PxProxy` / `Get-PxState` と alias に一本化。
- `Proxy.ps1` を px-on/off/state の実体にし、旧 `modules/PSProfile/Private/Px.*.ps1` を削除。
- 公開 Proxy API は次の 3 つに整理。
  - `px-on`
  - `px-off`
  - `px-state`
- `px-doctor` / `px-restart` は v2.5.0 では公開しない。

## 3. Proxy 動作の整理

- `px-on` は Process/User の `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `NO_PROXY` と小文字版 env を設定。
- Windows では `ProxyEnable=1` と `ProxyServer` を設定。`px-on` は Px 起動ではなく、`px-off` で無効化した Internet Proxy を有効化し直すだけ。
- `px-off` は Process/User の proxy env を削除し、Windows では `ProxyEnable=0` にする。
- `ProxyServer` / `ProxyOverride` / `AutoConfigURL` は会社標準値の可能性があるため削除しない。
- 既定値は `http://127.0.0.1:3128` と `localhost,127.0.0.1,::1,169.254.169.254` に統一。
- Px 本体の起動停止は行わない。ログオン時タスクなど利用者側の運用に任せる。

## 4. install.ps1 の堅牢化

- リモート取得は GitHub tar.gz を 1 回だけ取得し、展開後に `modules/PSProfile` を探す方式へ変更。
- モジュール配置は一時ディレクトリへステージングしてから入れ替える。
- 旧 `~/.psprofile/Manage-PxProxy.ps1` が残っている場合は uninstall 時に撤去する。新規配置はしない。
- Windows / 非 Windows でモジュールパスと依存ツール案内を分岐。

## 5. ドキュメントと検証

- 起動時間の固定値表記をやめ、`$env:PSPROFILE_BENCH=1` と `tools/bench-startup.ps1` による実測へ統一。
- `user-config.template.ps1` を削除し、Proxy 設定は `Proxy.ps1` の `Get-PSProfilePxConfig` を編集する方針に変更。
- `DESIGN.md` / `README.md` / `SETUP.md` を v2.5.0 の最小 API に合わせて更新。

---

## 検証

```powershell
# 構文チェック
pwsh -NoProfile -NonInteractive -Command '$paths = @(".\install.ps1",".\Microsoft.PowerShell_profile.ps1",".\modules\PSProfile\PSProfile.psm1",".\modules\PSProfile\Proxy.ps1",".\tests\PSProfile.Tests.ps1"); foreach ($p in $paths) { $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $p), [ref]$tokens, [ref]$errors) | Out-Null; if ($errors.Count) { $errors | ForEach-Object { $_.Message }; exit 1 } }; "Parse OK"'

# テスト
pwsh -NoProfile -NonInteractive -File .\tests\PSProfile.Tests.ps1

# 公開 API
Import-Module .\modules\PSProfile -Force
Get-Command px-on, px-off, px-state, phelp, psprofile-version
Get-Command px-doctor, px-restart -ErrorAction SilentlyContinue
```
