# 起動速度の調べ方・直し方

> 看板は「軽い起動」ですが、同梱の `bench-startup.log` は **WITH profile 6.4〜7.6 秒**でした。
> section 単位の内訳が無いと犯人を特定できません。**推測で直さず、まず計測**してください。
> （PowerShell の実行が必要なので、お手元の Windows で実施します）

## 0. ゴール

- まず「今、何秒かかっているか」「どの section が支配的か」を**数字で**出す。
- 支配項を1つ特定 → 対策を1つ入れる → 同じベンチで再計測。これを繰り返す。
- 受け入れ目安は計測後に決める（例: warm 起動のプロファイル上乗せ < 1.5 秒）。

## 1. 全体（WITH / NOPROFILE）

```powershell
pwsh -File .\tools\bench-startup.ps1
```

- `WITH profile` − `NOPROFILE` が「プロファイルの上乗せ」。ここが大きいほど改善余地。
- 1 回目は cold（キャッシュ生成）、2〜3 回目が warm。両方を見る。

## 2. $PROFILE / モジュール内の section 内訳（いちばん重要）

```powershell
$env:PSPROFILE_BENCH = '1'
pwsh -NoLogo -Command exit
```

`$PROFILE timings`（PSModulePath / Import-Module）と
`PSProfile section timings`（encoding / PSReadLine / exe-cache / starship / zoxide / eza / Proxy stubs）が出ます。
**どの行が一番大きいか**をメモする。

補助:

```powershell
pwsh -File .\tools\bench-detail.ps1      # PATH 走査 / init キャッシュ読み込み / Proxy.ps1 の内訳
pwsh -File .\tools\bench-sections.ps1    # 各 section を素の状態で再計測
```

## 3. 支配項別の対策

数字を見て、大きい所だけ手を入れる。

| 支配項 | ありがちな原因 | 対策 |
|---|---|---|
| `PSReadLine` | `-PredictionViewStyle ListView` 等の初期化 | `modules/PSProfile/PSProfile.psm1` の PSReadLine block を一時的にコメントアウトして差分を測る |
| `exe-cache` / PATH 走査 | OneDrive 配下を含む PATH を毎回走査、AV スキャン | 走査対象 dir を実在する数本に絞る／不要 PATH を整理。cold のみ重いなら許容 |
| `starship` / `zoxide` | init 出力が未キャッシュ、または更新で再生成 | v2.5 で exe 指紋による自動再生成に対応済み。初回だけ重いのは正常 |
| `Import-Module PSProfile` | マニフェスト処理・関数 export | export を実際に使う関数だけに絞る。差が小さければ触らない |
| WITH は重いが section 合計は軽い | 企業 AV が pwsh 起動時に各ファイルをスキャン | IT に pwsh / モジュールパスの除外を相談（端末ポリシー側の問題） |

> ヒント: 「section 合計は小さいのに WITH-NOPROFILE が大きい」場合、原因はプロファイル外（AV・
> ディスク・OneDrive 同期）の可能性が高い。コードをいじっても下がりません。まず切り分けを。

## 4. 記録

before / after を `bench-startup.log` に残し、どの対策が何ミリ秒効いたかを書き添えると、
次に触るときに迷いません（`bench-startup.log` は `.gitignore` 済みなのでコミットされません）。
