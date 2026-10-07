# SAYDO — Claude Code 向けリポジトリ規約

SAYDO は「今日の約束を自分の声で言い、やるまで自分の声で追いかけてもらう」ための iOS ネイティブアプリ。
本質は後追い。朝に約束と最初にやることを声にすると、朝・昼・晩のアラームがその約束の声で鳴り、
アプリで答える（やった / 少しやった / まだ / 今日はやめる）まで追いかける（実装計画 §17）。
サーバー・アカウント・クラウド LLM を持たない。データは端末内、音声認識もオンデバイス。

- 計画: `docs/implementation-plan.md`（章番号はこの文書から参照する）
- タスク仕様: `docs/task-list.json`（仕様。進捗は書かない）
- 進捗と証拠: `docs/PROGRESS.md`（1 タスク 1 エントリ。全文ログは `docs/logs/<task_id>-<n>.txt`）
- 実行体制: `docs/harness-design.md`
- レビュー採否: `docs/review/fix-decisions-2026-09-04.md`（task-list.json より優先する）

---

## 1. モジュール構成（実装計画 §7.1）

```
SAYDO/
  project.yml                      XcodeGen 定義（Saydo / SaydoTests / スパイク 3 本: SpeechSpike, AlarmSpike, fm-probe）
  Saydo.xcodeproj                  XcodeGen の生成物。コミットしない（scripts が毎回生成する）
  App/                             iOS アプリ本体（SwiftUI）
    SaydoApp.swift, AppDelegate.swift, AppRouter.swift, RootView.swift, RootCopy.swift
    Alarms/       AlarmScheduler（AlarmKit）, AlarmSoundStore（約束の録音をアラーム音にする）,
                  ChaseRules, ChaseCoordinator（朝・昼・晩の 3 回で追う段取り）, AlarmIntents
    Audio/        AudioSessionController, VoiceCapture, TranscriptionService, VoicePlayer, WaveformSampler
    Data/         Schema (VersionedSchema), Models/*, AudioFileStore, AppSettings,
                  Repository（+Promise / +FollowUp / +Insight / +Developer）
    Notifications/ NotificationScheduler（旧い版が登録した通知の後始末と、そのタップの見分けだけ。通知は登録しない）
    Features/     Promise（約束する）, FollowUp（答える）, Today（今日）, Timeline（記録）,
                  Insight（週次）, Onboarding, Settings（+ DataExporter）,
                  Shared（SaydoTheme, WaveformView, TextAnswerField）
    Resources/    Assets.xcassets, Info.plist（XcodeGen 生成）
  Packages/
    SaydoCore/    純 Swift パッケージ（macOS で swift test 可能）
                  Domain（CommitmentOutcome ほか）, Dialogue（Guardrails, CopyLine, PromiseCopy*）,
                  Insight, Notifications（AlarmPlan）
  Spikes/
    fm-probe/     macOS CLI。Foundation Models の日本語品質検証（S-A / S-D。検証の記録として残す）
    SpeechSpike/  iOS アプリ。SpeechAnalyzer + 録音 + 無音停止 + TTS 半二重（S-B / S-C。同上）
    AlarmSpike/   iOS アプリ。AlarmKit の実機検証（docs/spikes/alarm-spike.md）
  Tests/SaydoTests/                アプリ側のユニットテスト
  scripts/                         検証コマンド（下記）
  docs/                            計画・進捗・ログ・スパイク記録
```

- 画面は、約束する（Promise）/ 答える（FollowUp）/ 今日（Today）/ 記録（Timeline。週次の Insight を含む）/ Onboarding / Settings。
  開くと、約束が無ければ約束する画面、答えがまだなら答える画面を全画面で出し、そうでなければ今日・記録の 2 タブ。
- ネットワーク層は存在しない。SwiftData と端末内の音声ファイルだけを使う。
- ユーザー向け文言は `*Copy`（`PromiseCopy` / `InsightCopy` / `SettingsCopy` ほか）に置き、View と ViewModel に直書きしない。lint は名前が `Copy.swift` で終わるファイルだけを除外する。

## 2. 検証コマンド（5 本 + 実機・配布 2 本。エージェントは xcodebuild を直接叩かない）

| コマンド | 内容 |
|---|---|
| `scripts/build-ios.sh [scheme]` | iOS ターゲットをシミュレータ SDK でビルド（既定 Saydo、他に SpeechSpike） |
| `scripts/test-ios.sh [scheme]` | iOS 26.x の利用可能シミュレータを自動選択して `xcodebuild test` → 続けて lint-principles.sh。iOS 26.x が無ければ exit 2 |
| `scripts/build-mac.sh <scheme>` | macOS ターゲットをビルド（例: `scripts/build-mac.sh fm-probe`） |
| `scripts/test-core.sh` | `swift test --package-path Packages/SaydoCore` → 続けて lint-principles.sh |
| `scripts/lint-principles.sh` | `App/` と `Packages/*/Sources` から URLSession / import Network / @unchecked Sendable / nonisolated(unsafe) を検出して exit 1。Copy 以外の日本語リテラルは警告 |
| `SAYDO_TEAM_ID=… scripts/build-device.sh [scheme] [--no-launch]` | 繋いだ iPhone に Debug ビルドをインストールして起動（Automatic 署名。Xcode の Apple ID か App Store Connect API キーが要る） |
| `SAYDO_TEAM_ID=… scripts/archive-testflight.sh [build-number]` | Release でアーカイブし App Store Connect にアップロード（TestFlight 内部配布）。`scripts/ExportOptions-testflight.plist` を使う |

`Saydo.xcodeproj` は `project.yml` からの生成物で、リポジトリには含めない。`build-ios.sh` / `test-ios.sh` / `build-mac.sh` が先頭で `scripts/generate-project.sh` を呼んで毎回作り直す（xcodegen が無ければ exit 3）。手で作りたいときは `xcodegen generate`。

### 環境の履歴（task_001 時点のブロッカーは 2026-09-04 に解消）

- iOS 26.3.1 のシミュレータランタイム（23D8133）が導入済み。`scripts/build-ios.sh` は本来の `generic/platform=iOS Simulator` 経路で動き、`scripts/test-ios.sh` は iPhone 17 / iOS 26.3 でテストを実行できる（初回成功の証拠は `docs/PROGRESS.md` の integration エントリ）。
- ランタイム未導入の環境では `build-ios.sh` が `-target` 形式（コンパイルとリンクのみ）へ自動で切り替わり、`test-ios.sh` は exit 2 で止まる。その場合の導入手順は task_001 エントリを参照。

## 3. Executor への固定指示（harness-design.md §2 より転記）

```
- 企画原則 §22 を破る実装をしない。特に「責めない」「開いた瞬間に話せる」「タスク管理アプリにしない」。
- ネットワーク API（URLSession 等）を追加しない。追加が必要だと思ったら止まって報告する。
- Guardrails の禁止語リストとテストを弱めない。
- Swift 6 strict concurrency の警告を @unchecked Sendable や nonisolated(unsafe) で黙らせない。理由を書いて報告する。
- テストを通すためのハードコード・分岐をしない。
- 完了報告は verify_commands の出力と done_definition の対応表で行う。未検証は未検証と書く。
```

1 タスクの手順: CLAUDE.md → 計画の該当章 → task-list.json の該当タスク → PROGRESS.md 直近 2 件を読む → `task/<番号>-<名前>` ブランチ → scope だけ実装 → verify_commands を実行し出力を要約せず記録 → done_definition を証拠付きで自己監査 → `task_0NN:` 始まりのメッセージでコミット → PROGRESS.md に追記。

## 4. 企画原則 §22（10 項目・要約）

1. ユーザーを責めない（禁止句を Guardrails で機械的に弾く）
2. 入力を面倒にしない（約束は押して話す。答えは 1 タップ。タップを増やさない）
3. 開いた瞬間に話せる（開いたら押して話すボタンがある。アプリは質問を読み上げない）
4. できない日はタスクではなく設計を疑う（「まだ」でも責めず、次の回でまた聞く。追うのは 1 日 3 回まで）
5. 行動を極端に小さくする（質問は「最初にやることは？」の 1 つ。5 分以下を目安に本人が決める）
6. AI より本人の言葉を大切にする（約束と最初にやることは、本人の発話をそのまま文字にして使う）
7. 未達成より「少し進んだ」を評価する（「少しやった」は前進として扱う）
8. タスク管理アプリにしない（一覧・チェックボックス・進捗率を作らない。約束は 1 日 1 つ）
9. 音声を単なる入力方式にしない（声そのものを記録として残す）
10. 自分の声を自分に返す（約束の声を、朝・昼・晩のアラームで返す。アプリで答えるまで追う）

## 5. フック

PostToolUse フックは導入しない（編集のたびに `scripts/test-core.sh` が走ると遅延が大きいため）。検証は各タスクの verify_commands で明示的に実行する。
