# SAYDO 実装ハーネス設計（チーム編成と実行プロトコル）

- 作成日: 2026-09-04
- 対象: `docs/implementation-plan.md` の task_001〜021 を、開発者 1 人 + Claude Code で実行するための体制と手順
- 前提: Fable 5.1 は限られた時間枠でのみ使える。方針は「計画・分析は Fable、実装は Opus」。Opus セッションには SessionStart フックで fable-like 規範が注入される。

---

## 1. チーム編成（役割 = セッションまたはサブエージェント）

| 役割 | 担当 | 責務 | 使うもの |
|---|---|---|---|
| プロダクトオーナー兼デバイステスター | noritaka（人間） | 企画原則の最終判断、スパイクの Go / No-Go、実機テスト、権限ダイアログ確認、TestFlight / App Store Connect 操作、7 日間ドッグフーディング | iPhone 実機、Apple Developer アカウント |
| アーキテクト（Planner） | Fable 5.1（時間枠内のみ） | 計画書と task-list の改訂、Phase ゲートでの敵対的レビュー、音声パイプラインなど最難関の設計判断（不具合調査そのものは調査班 = Opus が担当し、investigator → verifier → solver を 2 回試して解けなかった案件だけを Fable が引き取る） | `plan` スキル、`.claude/workflows/plan-review.js`、`fable-protocol` |
| 実装者（Executor） | Opus（全タスク固定。タスクの難易度や risk_level でモデルを切り替えない） | task-list.json の 1 タスクを 1 セッションで実装し、verify_commands を実行し、証拠付きで報告 | `task-executor` エージェント、serena MCP（シンボル単位の編集）、`scripts/*.sh` |
| レビュアー（Reviewer） | 実装者とは別セッション（Opus） | 差分を done_definition・企画原則・Swift 6 並行性・テスト充足の 4 観点で審査 | `/code-review high`、`code-reviewer` / `code-verifier` エージェント、`.claude/workflows/task-review.js`（作成済み） |
| 品質修復者（Fixer） | Opus | ビルド・テスト失敗を緑になるまで修復。仕様変更はしない | `quality-fixer` エージェント、`scripts/test-core.sh` / `scripts/test-ios.sh` |
| 調査班（Investigator / Verifier / Solver） | Opus | 実機で再現した不具合の観測 → 反証 → 解決案の 3 段。音声・通知の不具合はここに回す | `investigator` → `verifier` → `solver` エージェント |
| 文言監査（Copy Auditor） | Fable（分析。時間枠外は Opus） | 全ユーザー向け文字列を Guardrails（責めない）とトーンで監査 | `.claude/workflows/copy-audit.js`（作成済み。task_005 完了後は毎回の task-review で実行） |

人数は 1 人。同時に走らせる Claude Code セッションは **Executor 2 + Reviewer 1（短時間）** とする。Reviewer は PR ごとに立ち上げて審査が終わったら閉じる短命セッションで、常駐させない。人間の実機作業（権限ダイアログ、通知の到達確認、TestFlight 操作）は実装セッションの合間に行う。実機確認のためにセッションを空けて待機させない。

## 2. 1 タスクの実行プロトコル（全 Executor 共通）

1. **開始**: `CLAUDE.md`（SAYDO 直下、task_001 で作成）→ `docs/implementation-plan.md` の該当章 → `docs/task-list.json` の該当タスク → `docs/PROGRESS.md` の直近 2 エントリ、の順に読む。`files_to_read` を全て読む。
2. **ブランチ**: `task/<番号>-<短い名前>` を main から切る。並列作業は git worktree（`EnterWorktree`）で分離する。**worktree では `.xcodeproj` を再生成しない（`xcodegen generate` を実行しない）。`project.yml` を変更したタスクだけが main で `xcodegen generate` を実行し、生成された `.xcodeproj` をコミットする。** worktree 側は main で再生成された `.xcodeproj` を rebase / merge で取り込む。
3. **実装**: `scope` の範囲だけを実装する。`non_scope` に触れない。文言はすべて `DialogueCopy` / `NotificationCopy` に置き、画面や ViewModel に直書きしない。
4. **検証**: `verify_commands` を全て実行する。出力の全文は `docs/logs/<task_id>-<n>.txt`（`<n>` は同一タスク内の実行回数）に保存し、`docs/PROGRESS.md` には **exit code と出力の末尾 30 行だけ** を貼り、全文ログのパスを添える。要約や書き換えはしない。失敗はそのまま記録して Fixer に回すか、自分で直す。
5. **自己監査**: `done_definition` を 1 行ずつ「証拠（コマンド出力・ファイルパス・スクリーンショット）」付きでチェックする。実機でしか確認できない項目は「人間の確認待ち」と明記し、確認手順を書く。
6. **コミット**: メッセージ先頭に `task_007:` のように task_id を付ける。`.xcodeproj` は XcodeGen の生成物なので `.gitignore` に入れ、コミット対象は `project.yml` のみとする（各 scripts/*.sh は実行前に `xcodegen generate` を自動実行する）。
7. **PR**: main への PR を作り、Reviewer セッションが `/code-review high` と task-review ワークフローを実行する。**task_005 の完了直後から、task-review には毎回 copy-audit を組み込む**（ユーザー向け文字列が 1 文字でも増減したタスクは例外なく実行する）。あわせて `scripts/lint-principles.sh` を実行し、check_016（外部通信ゼロ）と check_025（concurrency 警告 0 件）を毎回確認する。指摘の修正は同じブランチで行い、人間がマージする。
8. **記録**: `docs/PROGRESS.md` に「task_id / 状態（done・blocked・needs-device）/ 証拠 / 未解決」を追記する。task-list.json は仕様であり、進捗を書き込まない。

### Executor への固定指示（タスク指示の末尾に貼る）

```
- 企画原則 §22 を破る実装をしない。特に「責めない」「開いた瞬間に会話」「タスク管理アプリにしない」。
- ネットワーク API（URLSession 等）を追加しない。追加が必要だと思ったら止まって報告する。
- Guardrails の禁止語リストとテストを弱めない。
- Swift 6 strict concurrency の警告を @unchecked Sendable や nonisolated(unsafe) で黙らせない。理由を書いて報告する。
- テストを通すためのハードコード・分岐をしない。
- 完了報告は verify_commands の出力と done_definition の対応表で行う。未検証は未検証と書く。
```

## 3. モデル割り当て

| タスク | モデル | 理由 |
|---|---|---|
| task_001〜021 の実装すべて | Opus | 実装は Opus に固定する（ユーザー方針） |
| task_003, 004, 007, 008, 014, 015 で行き詰まった時の設計判断 | Fable 5.1（時間枠内） | Apple の新 API と実機挙動に依存する最難関 |
| 計画改訂、スパイク結果の解釈、Phase ゲートの敵対的レビュー、リテンション分析 | Fable 5.1 | 計画・分析は Fable に固定する（ユーザー方針） |

Fable の時間枠が来たら優先順: (1) 直前 Phase のゲートレビュー、(2) blocked タスクの設計判断、(3) 次 Phase の task-list 改訂。実装の手作業には使わない。

**Fable の枠が 2 日以内に来ない場合の代替**: ゲートレビューは Opus が `plan-review.js` / `phase-gate.js` を実行して**仮承認**とし、次の Fable 枠で再確認する（仮承認であることを `docs/PROGRESS.md` に明記する）。blocked タスクは investigator → verifier → solver（すべて Opus）を 2 回試し、それでも解けない場合にだけ Fable に回す。

**1 枠の上限**: 1 つの Fable 枠で扱うのは上の優先順の上から 1 件だけ（ゲートレビュー 1 つ、または blocked 1 件の設計判断、または task-list 改訂 1 回）。複数を 1 枠に詰めない。残りは次の枠か、上の代替ルールに回す。

## 4. 並列実行の計画

| 並列グループ | 同時に走らせるタスク | 条件 |
|---|---|---|
| P0 | task_003 ∥ task_004 | task_001 が Saydo / SaydoTests / SpeechSpike / fm-probe の 4 ターゲットをプレースホルダのソース付きで先に作るため、**両者が `project.yml` を同時に編集する衝突は起きない**。task_003 は task_002 完了後、task_004 は task_001 完了後に着手できる。fm-probe は Mac、SpeechSpike は実機 |
| P1 | task_005 ∥ task_006 | task_002 完了後。パッケージと App 側で衝突しない |
| P2 | task_007（task_004 完了後）∥ task_005b | 音声スタックはフローと独立。task_005b（TemplateDialogueEngine / ShrinkLadder / JapaneseTimeParser）は task_005 完了後 |
| P3 | task_014 ∥ task_021（任意） → その後に task_019 | task_013b（TestFlight 内部配布 #2）完了後。task_014 と task_021 はドッグフーディング期間に並行して走らせる。**task_019（書き出し・全削除・バックアップ復元）はドッグフーディング 7 日間が終わった後に実施する**（7 日分の実データが端末に溜まってから復元を確認するため） |
| P4 | task_017 ∥ task_018 | task_016 完了後 |

直列必須: task_008 → 009 → 010 → 011 → 012 → 013（SessionViewModel を共有するため）。`project.yml` を変更するタスク（task_001 / 002 / 003 / 014 など）は、同じ並列グループ内で 2 つ同時に走らせない。

## 5. 品質ゲート

| ゲート | 時期 | 判定者 | 合格条件 |
|---|---|---|---|
| G0 スパイク判定 | task_003・004 完了時 | 人間（Fable のレビュー付き） | `docs/spikes/*.md` に Go / No-Go と数値がある。No-Go ならその場で task_014・015 を Tier B 固定に書き換える |
| G1 コアループ | task_013b 完了時（TestFlight 内部配布 #2） | `.claude/workflows/phase-gate.js`（各 acceptance check を 1 エージェントが pass / fail / needs-human 判定）+ 人間の実機チェック | **check_001〜004・008〜013・015・024** が pass または人間確認済み。check_005 は **テンプレート文言のみ**（`DialogueCopy` / `NotificationCopy`）を対象に判定する。TestFlight 内部配布済み |
| G2 AI 層 | task_017 完了時 | 同上 + fm-probe の通過率 | **check_005（LLM 出力を含む全文言）・006・007・014** が pass。**自動判定の通過率 90% 以上**（同じ 90% を task_017 の done_definition にも書く）、置換率が記録されている |
| G3 リリース | **task_020 の外部テスト完了後、App Store 提出前** | 人間 + `/security-review` | check_016〜025 が pass。外部テスト 1 週間の記録あり |

ゲートで fail が出た場合、修正タスクを task-list.json に `task_0xx-fix-<n>` として追加してから着手する（無記録の修正をしない）。

check_026〜039（昼フローの入口・話せない時モード・通知の再計画とリテンション策・週次分析の入力範囲）は上の合格条件には含めず、各 check の `verification_method` が指すタスクの task-review で個別に判定する。ゲート割り当ては次のとおり（Fable 判定 2026-09-04）: check_026〜037（昼フローの入口 3 状態・少しやった・話せない時モード・再生前確認・割り込み・7 日分トリガー・既定通知・今日は休む・再入場・特にない）は G1、check_038（3 件目インサイト）と check_039（週次分析の入力制限）は G2。

## 6. リポジトリ内のハーネス部品

| 部品 | 作成タスク | 内容 |
|---|---|---|
| `CLAUDE.md`（SAYDO 直下） | task_001 | モジュール構成、検証コマンド一式（test-core.sh / build-ios.sh / test-ios.sh / build-mac.sh / lint-principles.sh）、Executor 固定指示、企画原則 §22 の要約 |
| `scripts/test-core.sh` / `build-ios.sh` / `test-ios.sh` / `build-mac.sh` | task_001 | 唯一の検証コマンド。エージェントは xcodebuild を直接叩かない。build-ios.sh / test-ios.sh / build-mac.sh はスキーム名を第 1 引数で受ける（既定 Saydo） |
| `scripts/lint-principles.sh` | task_001 | `URLSession` / `import Network` / `@unchecked Sendable` / `nonisolated(unsafe)` / Copy ファイル外の日本語リテラルを検出。test-core.sh と test-ios.sh の末尾から呼ばれ、毎回の task-review でも実行する（check_016・check_025） |
| `docs/PROGRESS.md` | task_001 | セッション間の状態引き継ぎ。1 タスク 1 エントリ。検証出力は exit code + 末尾 30 行だけを貼り、全文は `docs/logs/<task_id>-<n>.txt` に置く |
| `.claude/workflows/plan-review.js` | 作成済み | 計画書の敵対的レビュー（5 レンズ → 統合 → 反証検証）。`Workflow({name: "plan-review"})` で再実行 |
| `.claude/workflows/task-review.js` | 作成済み | PR 差分を 4 観点（正しさ / 企画原則 / Swift 6 並行性 / テスト充足）で並列レビューし、各指摘を反証検証 |
| `.claude/workflows/copy-audit.js` | 作成済み | `DialogueCopy` / `NotificationCopy` / 画面の全文字列を抽出し、Guardrails とトーンを監査。task_005 完了直後から毎回の task-review に組み込む |
| `.claude/workflows/phase-gate.js` | 作成済み | `docs/acceptance-checks.json` の各 check を 1 エージェントが判定し、needs-human を人間向けチェックリストとして出力 |
| `.claude/settings.json` の hook（任意） | task_001 | `Packages/SaydoCore` 配下の編集後に `scripts/test-core.sh` を自動実行する PostToolUse フック。遅いと感じたら外す |

## 7. 人間にしかできない作業（エージェントはここでブロックせず「needs-device」で報告する）

- 実機へのインストールと権限ダイアログの操作（マイク・通知）
- Apple Intelligence の有効化とオフ切替（Tier A / B の検証）
- 通知の到達確認（ロック画面・集中モード・消音）
- TestFlight 配布、外部テスターの招待、App Store Connect のメタデータ入力と提出
- ドッグフーディングの記録（`docs/dogfood/week1.md`）
- スパイクの Go / No-Go と、Phase ゲートの最終承認

エージェントは上記が必要になった時点で、手順を箇条書きにして `docs/PROGRESS.md` に「人間の確認待ち」として残し、次のタスクに進む。

## 8. 7〜8 週間の運用リズム

- 毎朝: `docs/PROGRESS.md` を読み、その日のタスク（最大 2 並列）を決める。
- 実装セッション: 2 章のプロトコルどおり。1 セッション 1 タスク。
- 夕方: 実機確認（needs-device の消化）。
- Phase 終端: ゲートレビュー。Fable の枠があればそれに合わせる。Phase 終端から 2 日以内に枠が来ない場合は §3 の代替ルールに従い、Opus が `phase-gate.js`（G1・G2）または `plan-review.js` を実行して仮承認とし、次 Phase に着手する。仮承認である旨を `docs/PROGRESS.md` に書く。
- 週 1 回: `memory-governance` と `docs/implementation-plan.md` の見直し。実装が計画から外れた箇所は計画側を先に直す。
