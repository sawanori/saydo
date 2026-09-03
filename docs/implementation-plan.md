# Implementation Plan: SAYDO — 音声主体の現実逃避伴走アプリ（iOS ネイティブ）

- 作成日: 2026-09-04
- 元資料: `voice_avoidance_companion_app_concept.md`（MVP 定義は §17、禁止事項は §9・§18・§22）
- 計画の性質: 実装前の戦略と実行計画。本書の作成時点でアプリコードは 1 行も存在しない。
- 実行者の前提: Claude Code セッション（1 タスク = 1 セッション）と開発者本人（noritaka）。

---

## 0. Development Strategy（開発戦略）

### 0.1 結論（推奨は 1 つ）

1. **iOS 先行。Swift 6.2 / SwiftUI / 最小 iOS 26.0。** サーバー・アカウント・自前バックエンド・クラウド LLM は持たない。
2. **コア体験「本人の声を本人に返す」（録音 → ローカル通知 → 再生）を AI なしで先に完成させる。** AI は `DialogueEngine` プロトコルの背後に後から差し込む層にする。
3. **会話は決定的な状態機械（FlowMachine）が主導し、LLM は型付きの穴埋め（`@Generable`）だけを担当する。** 会話履歴を LLM に丸投げしない。
4. **AI 実行はオンデバイス（Foundation Models）。** 利用不可の端末では同じフローがテンプレート＋選択肢で動く（Tier B）。UI は Tier に依らず同一。
5. **Android は iOS で体験検証を終えた後（Phase 5）。** 本計画では非スコープ。

製品名は作業ディレクトリ名に合わせて **SAYDO**（Say → Do。「声に出して、動く」）とする。

### 0.2 根拠

| # | 根拠 | 計画への反映 |
|---|---|---|
| 1 | 企画書 §20 の象徴体験（朝の宣言を昼に自分の声で聞く）は録音・通知・再生だけで成立し、LLM を必要としない。 | Phase 1 は AI ゼロで TestFlight 配布まで到達させる。LLM の日本語品質が期待以下でも製品は成立する。 |
| 2 | 「機種依存で完結」に必要な部品が iOS 26 で全て標準 API として揃う（下表）。 | 外部 SDK・自前サーバーをゼロにする。 |
| 3 | Foundation Models のセッション上限は 4,096 トークンで、日本語は概ね 1 文字 = 1 トークン（Apple 公式ドキュメント `exceededContextWindowSize` の記述）。 | 会話全文を渡す設計は不可能。ステップごとに「指示 ≤600 文字・入力 ≤400 文字・出力 ≤200 文字」の独立呼び出しに分解する。 |
| 4 | 「責めない」（§9・§22-1）は確率的生成に委ねると保証できない。 | 全 LLM 出力を `Guardrails`（禁止語・長さ・形式）に通し、違反時はテンプレート文に置換する。 |
| 5 | SpeechAnalyzer はオンデバイス処理で Apple サーバーに音声を送らないため、音声認識の権限ダイアログが不要（Apple 公式「Asking Permission to Use Speech Recognition」）。 | 権限プロンプトはマイクと通知の 2 つだけ。「開いた瞬間に話す」体験を初回以降ノータップで実現できる。 |
| 6 | 開発者本人がターゲット像に近い。 | Phase 1 完了時点で TestFlight 配布し、7 日間ドッグフーディングして会話文言を磨く（Phase 1.5）。 |
| 7 | クロスプラットフォーム FW（Flutter / React Native / Expo）は、音声セッション制御・SpeechAnalyzer・Foundation Models が全てネイティブ API のため、ブリッジ実装が本体より重くなる。 | 純 Swift。Android 着手時に Kotlin Multiplatform でのドメイン共有を再検討する。 |

#### 機種依存で賄う部品の対応表

| 役割 | iOS 標準部品 | 備考 |
|---|---|---|
| 音声認識（STT） | `SpeechAnalyzer` + `SpeechTranscriber`（iOS 26+） | オンデバイス。ja-JP モデルは `AssetInventory` で端末にダウンロード。権限はマイクのみ。 |
| 対話 AI（LLM） | Foundation Models `SystemLanguageModel.default` | Apple Intelligence 対応機のみ。`availability` で `deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady` を判定。 |
| 音声合成（TTS） | `AVSpeechSynthesizer` | ja-JP 音声。高品質音声は端末の設定でダウンロード可能なため設定画面から案内。 |
| 永続化 | SwiftData + アプリ領域の音声ファイル（AAC） | 自前サーバーなし。 |
| バックアップ | iCloud バックアップ（アプリデータは既定で対象） | 複数端末同期（CloudKit）は非スコープ。 |
| 通知 | `UserNotifications`（ローカル通知） | 1 日 3 回 + 行動時刻 1 回。 |
| 将来の高性能モデル | `PrivateCloudComputeLanguageModel`（iOS 27 beta で文書化） | v1 の依存にしない。Phase 4 以降の選択肢。 |

### 0.3 段階と出口条件

| Phase | 内容 | 出口条件 | 目安（1 人・Claude Code 主導） |
|---|---|---|---|
| 0 | 環境構築 + 技術スパイク（LLM 日本語品質 / 音声パイプライン） | Go / No-Go を `docs/spikes/` に記録 | 3〜4 日 |
| 1 | コアループ（Tier B、AI なし）: 朝 → 昼 → 夜 → 翌日引き継ぎ、通知、Voice Timeline、オンボーディング | 実機で 1 日分が通り、TestFlight 内部配布 | 約 10 日 |
| 1.5 | ドッグフーディング | 7 日連続使用。文言・無音閾値・通知時刻の修正リスト | 7 日（Phase 2 と並行） |
| 2 | AI 層（Foundation Models）+ 週次分析 | Tier A/B 自動切替。ガードレール通過率 100%（違反は置換される） | 約 5 日 |
| 3 | 仕上げ・審査 | App Store 提出 | 約 5 日 |

目安は実測で更新する。合計はおよそ 5〜6 週間。

### 0.4 最初の 1 週間で潰すリスク（スパイク）

| ID | リスク | 検証方法 | No-Go 時の代替 |
|---|---|---|---|
| S-A | Foundation Models の日本語品質（理由分類・5 分以下への細分化・短い追加質問） | macOS CLI `fm-probe` に 20 件のフィクスチャを流し、人手採点（採用可 / 要修正 / 不可） | Tier B 固定で出荷。Phase 4 で iOS 27 の PrivateCloudComputeLanguageModel、または Claude API + 薄いプロキシ（Cloudflare Workers）を検討 |
| S-B | SpeechAnalyzer ja-JP のライブ認識精度と遅延、録音との同時実行、無音自動停止、TTS との半二重切替 | iOS スパイクアプリを実機で計測 | `SFSpeechRecognizer`（オンデバイス指定）へフォールバック。その場合のみ音声認識権限が必要 |
| S-C | 通知タップから TTS 発話開始までの時間（目標 1.5 秒以内） | 実機でストップウォッチ計測 5 回 | 起動時にオーディオセッションと音声アセットをプリウォーム |
| S-D | Foundation Models の Mac / シミュレータでの動作可否 | Apple Intelligence を有効化した Mac 上で `fm-probe` と iOS 26.2 シミュレータを試す | 実機のみで Tier A を検証 |

---

## 1. Overview

SAYDO は、1 日 3 回（朝・昼・夜）だけ話しかけてくる音声主体の伴走アプリ。ユーザーは「逃げたいこと」を声に出し、理由を選び、5 分以下の行動に落とし、時刻を決め、自分の口で宣言する。その宣言音声が行動時刻に「朝のあなたからです」として本人へ返る。夜は前進を残し、翌日に引き継ぐ。記録は本人の声を中心にした Voice Timeline に残り、1 週間単位で「何から逃げているか」を可視化する。

iOS ネイティブ。サーバー・アカウントなし。データは端末内。AI はオンデバイス。

## 2. Goal

- ユーザーゴール: 逃げていることを自分の声で認め、今日一歩だけ動く。記録がそれ自体で現実逃避の対象にならない（朝 1〜3 分、昼 1 分、夜 1 分）。
- ビジネスゴール: 自前インフラの運用コストとプライバシーリスクをゼロに保ったまま App Store に出し、まず開発者本人と少数の TestFlight ユーザーで「本人の声を本人に返す」体験の価値を検証する。

## 3. Current State

- リポジトリ内容: 企画メモ 1 ファイルのみ。アプリコード・設定ファイル・`docs/` は存在しない（本書が最初）。
- Git: `SAYDO/` 直下に `.git` はない。親のホームディレクトリ `/Users/noritakasawada` がコミット 0 件の git リポジトリになっている。SAYDO は独立リポジトリとして `git init` する（task_001）。
- 開発機: macOS 26.5、Xcode 26.2（Build 17C52）、iOS 26.2 SDK、Swift 6.2.3、Apple M4。Foundation Models と SpeechAnalyzer を含む世代のツールチェーンが揃っている。
- シミュレータ: インストール済みランタイムは iOS 18.5 のみ。iOS 26.x ランタイムが未導入（task_001 で導入）。
- 未導入ツール: xcodegen、swiftlint、swiftformat、maestro、adb（PATH 上になし）。Android SDK は `~/Library/Android/sdk` に存在。
- 実機: Apple Intelligence 対応 iPhone（iPhone 15 Pro 以降）の有無は未確認。無い場合、Tier A は Mac / シミュレータで、Tier B は実機で検証する。

## 4. Scope

企画書 §17 の MVP 16 項目を全て含む。

| §17 | 項目 | 担当タスク |
|---|---|---|
| 1 | 朝の音声チェックイン | task_005, task_008 |
| 2 | 音声自動録音（ボタンなし） | task_007, task_008 |
| 3 | 音声 → テキスト変換 | task_004, task_007 |
| 4 | AI による追加質問 | task_005（テンプレート）, task_014, task_015（AI） |
| 5 | 逃げたい理由の整理 | task_005, task_015 |
| 6 | 行動を 5 分以下に分解 | task_005, task_015 |
| 7 | 今日の行動時間を設定 | task_005, task_008 |
| 8 | 本人による音声宣言 | task_008 |
| 9 | 昼の通知 | task_009 |
| 10 | 朝の本人音声の再生 | task_010 |
| 11 | 状態確認 | task_010 |
| 12 | 行動できていない場合の再分解 | task_010, task_015 |
| 13 | 夜の振り返り | task_011 |
| 14 | 翌日への引き継ぎ | task_011 |
| 15 | Voice Timeline | task_012 |
| 16 | 1 週間単位の簡易分析 | task_016 |

加えて: オンボーディング（権限・時刻設定）、設定、データの書き出しと全削除、App Store 提出準備。

## 5. Non-Scope

- 企画書 §18 の全項目（高機能 TODO、カレンダー、プロジェクト管理、ガントチャート、複雑な習慣管理、SNS、ランキング、競争、過剰なゲーミフィケーション）
- §16 の逃避検知（DeviceActivity / Screen Time API 連携）
- Android 版、Apple Watch、ウィジェット、Live Activity
- アカウント、サーバー、クラウド LLM、複数端末同期（CloudKit）
- 課金・サブスクリプション
- 日本語以外のローカライズ
- テキストチャット UI（テキスト入力は騒音時の補助のみ）

## 6. Assumptions

1. 最小 OS は iOS 26.0。Apple Intelligence 非対応機は Tier B（テンプレート）で全機能が動く。
2. 言語は日本語のみ（UI・音声認識・音声合成すべて ja-JP）。
3. 利用者は端末につき 1 人。
4. 音声ファイルは端末内に保存し、iCloud バックアップの対象から除外しない。復元は iOS の端末バックアップに委ねる。
5. 通知は固定 3 回（既定 8:00 / 13:00 / 21:00、変更可）+ 行動時刻 1 回。
6. Bundle ID は `com.nonturn.saydo`。Apple Developer Program 加入済みで TestFlight を使える。
7. プロジェクト定義は XcodeGen（`project.yml`）で行う。Claude Code から再生成できることを優先する。XcodeGen を使わない場合は task_001 で `.xcodeproj` を Xcode で手作成し、以降の手順は同じ。
8. Foundation Models は Apple Intelligence を有効化した Mac の macOS 26.5 上で動作する（公式ドキュメントで macOS 26.0+ と明記）。シミュレータでの動作は S-D で確認する。
9. `SpeechTranscriber.supportedLocales` に ja-JP が含まれる（S-B で実行時に確認）。
10. 宣言音声は 30 秒以内に収める（将来、通知サウンドとして使う可能性のため）。

## 7. Architecture Impact

### 7.1 モジュール構成

```
SAYDO/
  project.yml                      XcodeGen 定義（App / Spikes / Tests）
  App/                             iOS アプリ本体（SwiftUI）
    SaydoApp.swift, AppDelegate.swift, AppRouter.swift
    Audio/        AudioSessionController, VoiceCapture, SilenceDetector,
                  TranscriptionService, SpeechSynthesisService, VoicePlayer, WaveformSampler
    Data/         Schema (VersionedSchema), Models/*, AudioFileStore, Repository
    Notifications/ NotificationScheduler, DeepLink
    Features/     Session, Timeline, Insight, Onboarding, Settings, Today
    Resources/    Assets.xcassets, Localizable.xcstrings
  Packages/
    SaydoCore/    純 Swift パッケージ（macOS で `swift test` 可能）
                  Domain, Flows(Morning/Noon/Night, FlowMachine), Dialogue(DialogueEngine,
                  TemplateDialogueEngine, DialogueCopy, Guardrails), Insight, Notifications(NotificationPlan)
    SaydoAI/      Foundation Models 実装（FoundationModelsDialogueEngine, Generable 型, PromptBuilder）
  Spikes/
    fm-probe/     macOS CLI。Foundation Models の日本語品質検証
    SpeechSpike/  iOS アプリ。SpeechAnalyzer + 録音 + 無音停止 + TTS 半二重
  scripts/        build-ios.sh, test-ios.sh, test-core.sh
  docs/           本計画、spikes/、dogfood/
```

- フロントエンド: SwiftUI。画面は Today（セッション）、Timeline、Insight、Onboarding、Settings の 5 つ。
- バックエンド: なし。
- データベース: SwiftData（端末内）。
- 認証: なし。
- ストレージ: SwiftData ストア + `Application Support/Saydo/Audio/yyyy/MM/<uuid>.m4a`。ファイル保護は `completeUntilFirstUserAuthentication`（通知タップ直後の再生をロック解除後に保証するため）。
- インフラ: なし。TestFlight / App Store Connect のみ。

### 7.2 会話の制御方式（状態機械 + 穴埋め LLM）

- `FlowMachine` は `SessionType`（morning / noon / night / adhoc）ごとの `FlowStep` 列を持ち、各ステップは「発話（TTS）→ 入力（音声 / 選択肢 / テキスト）→ 処理（DialogueEngine 呼び出し or 決定的処理）→ 保存」の 4 段で構成する。
- `DialogueEngine` プロトコルに `TemplateDialogueEngine`（Tier B）と `FoundationModelsDialogueEngine`（Tier A）の 2 実装。Tier は起動時に `SystemLanguageModel.default.availability` で決める。
- LLM 呼び出しは 1 ステップ 1 回、タイムアウト 6 秒。失敗・タイムアウト・ガードレール違反はすべてテンプレート出力に置換し、会話は止めない。
- タイムボックス: 朝 3 分、昼 1 分、夜 1 分。各「聞く」区間は最長 20 秒。開始から 5 秒無音なら「長く考えなくていい。10 秒で答えて。」を 1 回だけ挟み、その後は選択肢とキーボードを出す。

#### 朝（MorningFlow）

| Step | 発話（テンプレート） | 入力 | 処理 |
|---|---|---|---|
| M0 | 「おはよう。今日、いちばん逃げたいことは何？」（前夜の引き継ぎがあれば「昨日の夜『◯◯』って言ってたね。今日はそれでいく？」+ 選択肢） | 音声 | `AvoidanceItem` 作成、`VoiceEntry(kind: avoidance)` 保存 |
| M1 | Tier A: LLM が生成した 1 文の追加質問。Tier B: 「一番近いのはどれ？」+ 選択肢 7 種（気まずい / 完璧にやりたい / 面倒 / 不安・怖い / 量が多い / 何から始めるかわからない / 期限が怖い） | 音声 or 選択肢 | `ReasonCategory` 確定（音声はキーワード照合、Tier A は LLM 分類） |
| M2 | Tier A: LLM が 5 分以下の行動を 3 案生成し、1 案目を読み上げ。Tier B: 理由 × 逃げ対象の名詞から生成したテンプレート（「まず◯◯を開くだけにしよう」）。常に「もっと小さく」の選択肢 | 音声 or 選択肢 | `MicroAction` 確定。「もっと小さく」は段階表（開く → 名前を探す → 件名だけ → 3 行だけ）を下る |
| M3 | 「今日は何時ならできそう？」+ 選択肢（1 時間後 / 午後 / 夕方 / 時刻を選ぶ） | 音声 or 選択肢 | 日本語時刻パース（「14 時」「2 時」「午後 2 時」「昼過ぎ」） |
| M4 | 「じゃあ最後に、自分に約束してください。今日やることを声に出して。」 | 音声（30 秒以内） | 宣言音声を保存、`Commitment` 作成、行動時刻の通知を登録。「受け取りました。◯時に、朝のあなたから届きます。」 |

#### 昼（NoonFlow。行動時刻通知・昼通知・手動起動で共通）

| Step | 発話 | 入力 | 処理 |
|---|---|---|---|
| N0 | 「朝のあなたからです。」→ 宣言音声を再生 | なし | 再生完了を待つ |
| N1 | 「どうだった？」+ 選択肢（やった / 少しやった / まだ） | 音声 or 選択肢 | `Commitment.outcome` 更新。「やった」なら「それを残しておくね。」で終了 |
| N2 | 「何が止めてる？」 | 音声 | `VoiceEntry(kind: blocker)` 保存 |
| N3 | Tier A: LLM が blocker を踏まえて行動を縮小。Tier B: 段階表を 1 段下る。「じゃあ今は◯◯しなくていい。△△だけにしよう。」+ 選択肢（1 時間後にもう一度 / 今日は捨てる / 明日に回す） | 音声 or 選択肢 | `MicroAction` 更新（`shrinkCount` +1）、必要なら通知を再登録 |

#### 夜（NightFlow）

| Step | 発話 | 入力 | 処理 |
|---|---|---|---|
| E0 | 「今日、少しでも前に進めたことは？」 | 音声 | `VoiceEntry(kind: progress)` 保存。「それを今日の前進として残します。」。前進がない場合は「今日は動けなかった日として残すね。責めない。明日、もっと小さくしよう。」+ §9 の 6 選択肢 |
| E1 | 「明日はどうする？」 | 音声 | `VoiceEntry(kind: tomorrow)` 保存、翌朝の M0 用に引き継ぎを作成。「明日の朝、聞くね。」で終了 |

### 7.3 音声パイプライン（1 入力 2 消費）

- `AVAudioEngine` の入力ノードにタップを 1 つ設置し、同じバッファを (a) `AVAudioFile`（AAC 32 kbps モノラル、`.m4a`）への書き込みと (b) `AnalyzerInputConverter` 経由の `AsyncStream<AnalyzerInput>`（SpeechAnalyzer）へ流す。(c) RMS を `WaveformSampler` に渡して波形描画に使う。
- 無音判定 `SilenceDetector`: RMS が閾値未満の状態が 1.5 秒（設定で 1.2 / 1.5 / 2.0 秒）続いたら発話終了。`SpeechTranscriber` の確定結果（finalized）を待って処理に進む。
- 半二重: TTS 発話中は STT へ流さない。`AVSpeechSynthesizerDelegate.didFinish` の後に聞き取りを開始する。
- `AVAudioSession`: カテゴリ `.playAndRecord`、モード `.default`、スピーカー既定出力。Bluetooth オプションは iOS 26.2 SDK の最新名を S-B で確認して使う。TTS の回り込みが認識に混入する場合は `.voiceChat` モードを S-B で比較する。
- 音声認識モデル: 初回に `AssetInventory.assetInstallationRequest(supporting:)` で ja-JP をダウンロード。オンボーディングで進捗表示。
- 通知タップからの起動時に、オーディオセッション有効化 → TTS 開始までを 1.5 秒以内に収める（S-C）。

### 7.4 通知

- 固定 3 回: `UNCalendarNotificationTrigger`（繰り返し）。文言は §15 のもの。昼は「朝、自分で言ったこと覚えてる？」「例のやつ、まだ避けてる？」を日替わりで交互に使う。
- 行動時刻 1 回: 朝の M4 完了時に登録。文言「朝のあなたからです。」。固定の昼通知と 30 分以内に重なる場合は昼通知を当日分だけスキップする。
- `userInfo` に `sessionType` と `commitmentID` を入れ、`UNUserNotificationCenterDelegate.didReceive` から `AppRouter` が該当フローを自動開始する。
- 通知本文に「未達成」「連続」などの責める語彙は使わない（`NotificationCopy` に固定し、Guardrails のテストを通す）。

### 7.5 ガードレール（責めない保証）

- 禁止語リスト（初期値）: 未達成、連続、サボ、怠、ダメ、なぜやらない、失敗、遅い、甘え、言い訳、また逃げ。
- 形式規則: 質問は 60 文字以内で「？」で終わる。行動文は 40 文字以内で動詞で終わる。URL・英語のみの出力を拒否。
- 違反時: 該当ステップのテンプレート文に置換し、`SessionLog` に `guardrailReplaced` を記録する（後で品質改善に使う）。

### 7.6 週次分析（Insight）

- `InsightCalculator` は SwiftData の集計だけで動く純関数: 逃げ対象の分野（`TaskDomain`: 人への返信 / お金 / 大きなタスク / 営業 / 書類 / 健康 / その他）別件数、理由（`ReasonCategory`）別割合、宣言の結果（やった / 少し / まだ）内訳、平均縮小回数。
- 振り返り 1 文: Tier A は集計値だけを LLM に渡して生成（原文は渡さない → トークン節約）。Tier B は上位の理由 × 分野の組み合わせ表から選ぶテンプレート。
- 分野の判定: Tier A は `@Generable enum TaskDomain` で分類。Tier B はキーワード辞書。

## 8. UI Plan

| 画面 | 役割 | 状態 |
|---|---|---|
| `SessionView`（Today タブの本体） | 朝・昼・夜・手動の会話画面。中央に大きな波形、1 行の質問、状態行（「聞いています…」「考えています…」）。選択肢チップは必要なステップだけ表示。右下に小さなキーボードボタン（騒音時の補助入力） | `idle` / `speaking`（TTS） / `listening` / `thinking`（LLM） / `choosing`（チップ） / `recordingDeclaration` / `playback` / `done` / `error(micDenied / assetDownloading)` |
| `TodayView` | 通知以外から開いたときの入口。今日の宣言カード（再生ボタン + 行動時刻）と「今話す」ボタン。宣言前は朝フロー、宣言後は手動チェックイン（NoonFlow）を開始 | 宣言前 / 宣言後 / 夜完了 |
| `TimelineView`（記録タブ） | 日ごとのセクションに 🎙️ + 時刻 + 文字起こし + 再生ボタン。上部に今週の Insight カード | 空 / 通常 / 再生中 |
| `WeeklyInsightView` | 「あなたが逃げやすいこと」上位 5、理由の割合、振り返り 1 文 | データ不足（3 日未満） / 通常 |
| `OnboardingView` | 1 画面ずつ: コンセプト 1 文 → マイク権限 → 通知権限 → 3 つの時刻 → ja-JP 音声モデルのダウンロード進捗 | 各ステップの許可 / 拒否 |
| `SettingsView` | 時刻、TTS 音声の選択、無音判定秒数、データ書き出し、全削除 | 通常 |

- ナビゲーション: `TabView` 2 タブ（今日 / 記録）。設定は「今日」の右上。チャット風の吹き出しと長い履歴は作らない（§13）。
- 通知タップ時は `TodayView` を経由せず `SessionView` を直接表示して即開始する。
- レスポンシブ: iPhone SE（3 世代、4.7 インチ）から iPhone 17 Pro Max まで、Dynamic Type の xxxLarge まで崩れないこと。波形は `Canvas` + `TimelineView(.animation)` で描き、Reduce Motion 時は振幅バーに切り替える。
- 視覚: 暗い単色背景、アクセント 1 色、質問は 28pt 相当、装飾は最小限。

## 9. API Plan

ネットワーク API は存在しない。代わりにアプリ内部の契約を定義する。

```swift
public protocol DialogueEngine: Sendable {
    func followUpQuestion(avoidance: String) async throws -> String            // M1（Tier A のみ意味を持つ）
    func classifyReason(avoidance: String, answer: String) async throws -> ReasonClassification
    func proposeMicroActions(avoidance: String, reason: ReasonCategory) async throws -> [MicroAction]  // 3 件
    func shrink(action: MicroAction, blocker: String) async throws -> MicroAction
    func classifyDomain(avoidance: String) async throws -> TaskDomain
    func weeklyReflection(stats: WeeklyStats) async throws -> String
}
```

- `@Generable` 型（SaydoAI）: `ReasonClassification { category: ReasonCategory; followUp: String(@Guide 60 文字以内・疑問形) }`、`MicroAction { text: String(@Guide 40 文字以内・5 分以内・動詞で終わる); estimatedMinutes: Int(@Guide(.range(1...5))) }`、`TaskDomain`（enum）。
- 入力の検証: 文字起こしが空、または 2 文字未満なら「もう一度、ゆっくりで大丈夫。」と再入力（最大 2 回、その後は選択肢）。
- エラー処理: `exceededContextWindowSize` → 新しい `LanguageModelSession` を作って 1 回だけ再試行。`unavailable` / `unsupportedCapability` → その場で Tier B に切替（セッション内で固定）。タイムアウト 6 秒 → テンプレート置換。
- プロンプト予算: 指示 600 文字以内、入力 400 文字以内、出力 200 文字以内。合計で 4,096 トークンを大きく下回る。

## 10. Database Plan（SwiftData、`VersionedSchema` V1）

| モデル | 主なプロパティ | 関係 |
|---|---|---|
| `AvoidanceItem` | id, title(本人の言葉), domain(TaskDomain), status(open / carriedOver / dropped / done), createdAt, lastTouchedAt | 1 → 多 `Commitment` |
| `Commitment` | id, dayKey(yyyy-MM-dd), microActionText, plannedAt, declarationAudioPath, declarationTranscript, outcome(pending / done / partial / notYet), shrinkCount, progressNote, createdAt | 多 → 1 `AvoidanceItem`、1 → 多 `VoiceEntry` |
| `VoiceEntry` | id, recordedAt, sessionType, kind(avoidance / reason / declaration / status / blocker / progress / tomorrow), audioPath, transcript, durationSec | 多 → 1 `Commitment`（任意） |
| `SessionLog` | id, sessionType, startedAt, endedAt, completed, tier(A / B), lastStep, guardrailReplacedCount | なし |
| `Carryover` | id, forDayKey, text, sourceEntryID | なし |

- インデックス: `VoiceEntry.recordedAt`、`Commitment.dayKey`（`#Index` を V1 から付ける）。
- 制約: 「1 日 1 件のアクティブな Commitment」はスキーマではなく `Repository` で保証する。
- 削除: `Commitment` / `VoiceEntry` の削除時に `AudioFileStore` が音声ファイルを削除する（孤児ファイルの掃除を起動時に 1 回走らせる）。
- 設定値（通知時刻、TTS 音声 ID、無音秒数、オンボーディング完了フラグ）は `UserDefaults`。
- 音声ファイル: AAC 32 kbps モノラル。1 日 3〜5 件 × 15 秒で年間 15〜25 MB 程度。iCloud バックアップの対象に含める。

## 11. File-by-File Plan

| ファイル | 種別 | 目的 | リスク |
|---|---|---|---|
| `.gitignore` | 作成 | Xcode / SwiftPM / DerivedData / xcuserdata を除外 | low |
| `project.yml` | 作成 | XcodeGen 定義。ターゲット: Saydo(iOS 26.0), SaydoTests, SpeechSpike(iOS), fm-probe(macOS CLI)。ローカルパッケージ SaydoCore / SaydoAI | medium |
| `scripts/test-core.sh` | 作成 | `swift test --package-path Packages/SaydoCore` を実行 | low |
| `scripts/build-ios.sh` | 作成 | 利用可能な iOS 26.x シミュレータを自動選択して `xcodebuild build` | medium |
| `scripts/test-ios.sh` | 作成 | 同上で `xcodebuild test`（SaydoTests） | medium |
| `CLAUDE.md`（SAYDO 直下） | 作成 | 検証コマンドとモジュール構成を次セッションに伝える | low |
| `Packages/SaydoCore/Package.swift` | 作成 | 純 Swift パッケージ（platforms: iOS 26, macOS 26） | low |
| `Packages/SaydoCore/Sources/SaydoCore/Domain/*.swift` | 作成 | `SessionType`, `FlowStep`, `ReasonCategory`, `TaskDomain`, `MicroAction`, `ReasonClassification`, `DialogueContext`, `WeeklyStats` | low |
| `Packages/SaydoCore/Sources/SaydoCore/Flows/{FlowMachine,MorningFlow,NoonFlow,NightFlow}.swift` | 作成 | 状態機械。副作用を持たず、入力イベントから次の状態と命令（発話 / 聞く / 保存 / 通知登録）を返す | medium |
| `Packages/SaydoCore/Sources/SaydoCore/Dialogue/{DialogueEngine,TemplateDialogueEngine,DialogueCopy,Guardrails,ShrinkLadder,JapaneseTimeParser}.swift` | 作成 | 契約、Tier B 実装、全文言、責めないガード、段階表、時刻パース | medium |
| `Packages/SaydoCore/Sources/SaydoCore/Insight/InsightCalculator.swift` | 作成 | 週次集計とテンプレート振り返り | low |
| `Packages/SaydoCore/Sources/SaydoCore/Notifications/{NotificationPlan,NotificationCopy}.swift` | 作成 | トリガー日時と文言の純計算（昼と行動時刻の重複ルールを含む） | low |
| `Packages/SaydoCore/Tests/SaydoCoreTests/*.swift` | 作成 | Flow 3 種、Guardrails、ShrinkLadder、JapaneseTimeParser、InsightCalculator、NotificationPlan のテスト | low |
| `Packages/SaydoAI/Package.swift` | 作成 | FoundationModels に依存するパッケージ（iOS 26 / macOS 26） | low |
| `Packages/SaydoAI/Sources/SaydoAI/{FoundationModelsDialogueEngine,GenerableTypes,PromptBuilder,ModelAvailability}.swift` | 作成 | Tier A 実装。タイムアウト、再試行、Guardrails 適用 | high |
| `Spikes/fm-probe/main.swift` + `Spikes/fm-probe/fixtures.json` | 作成 | 日本語 20 件を流して結果を Markdown に出力 | medium |
| `Spikes/SpeechSpike/*.swift` | 作成 | STT + 録音 + 無音停止 + TTS 半二重 + 起動時間計測 | high |
| `App/SaydoApp.swift`, `App/AppDelegate.swift`, `App/AppRouter.swift` | 作成 | エントリ、通知デリゲート、フロー起動ルーティング | medium |
| `App/Audio/*.swift` | 作成 | 7.3 の実装（SpeechSpike から昇格） | high |
| `App/Data/{Schema,AudioFileStore,Repository}.swift`, `App/Data/Models/*.swift` | 作成 | 10 章の実装 | medium |
| `App/Notifications/{NotificationScheduler,DeepLink}.swift` | 作成 | 7.4 の実装 | medium |
| `App/Features/Session/{SessionViewModel,SessionView,WaveformView,ChoiceChipsView,PlaybackCardView,TextFallbackSheet}.swift` | 作成 | 8 章の会話画面 | high |
| `App/Features/Today/TodayView.swift` | 作成 | 入口画面 | low |
| `App/Features/Timeline/{TimelineView,VoiceEntryRow}.swift` | 作成 | Voice Timeline | low |
| `App/Features/Insight/WeeklyInsightView.swift` | 作成 | 週次分析 | low |
| `App/Features/Onboarding/{OnboardingView,PermissionsViewModel,AssetDownloadView}.swift` | 作成 | 権限・時刻・モデル DL | medium |
| `App/Features/Settings/{SettingsView,AppSettings,DataExporter}.swift` | 作成 | 設定と書き出し / 全削除 | low |
| `App/Resources/Info.plist`（XcodeGen の `info` 設定） | 作成 | `NSMicrophoneUsageDescription` 必須。`NSSpeechRecognitionUsageDescription` は SFSpeechRecognizer フォールバックを同梱する場合のみ | low |
| `docs/spikes/{fm-probe,speech-spike}.md` | 作成 | Go / No-Go 記録 | low |
| `docs/dogfood/week1.md` | 作成 | 7 日間の観察記録と修正リスト | low |

## 12. Implementation Order

1. **Phase 0**: task_001（環境）→ task_002（SaydoCore 骨格）→ task_003（S-A / S-D: fm-probe）と task_004（S-B / S-C: SpeechSpike）は並行可。
2. **Phase 1**: task_005（Flow + テンプレート + Guardrails）→ task_006（SwiftData）→ task_007（音声スタック）→ task_008（朝の SessionView）→ task_009（通知）→ task_010（昼）→ task_011（夜 + 引き継ぎ）→ task_012（Timeline）→ task_013（Onboarding / Settings / Today）→ TestFlight 内部配布。
3. **Phase 1.5**: 7 日間ドッグフーディング（`docs/dogfood/week1.md`）。並行して Phase 2 に着手。
4. **Phase 2**: task_014（SaydoAI）→ task_015（Tier 切替と各ステップへの組み込み）→ task_016（週次分析）→ task_017（AI 品質回帰ハーネス）。
5. **Phase 3**: task_018（アクセシビリティと視覚仕上げ）→ task_019（データ管理と復元確認）→ task_020（審査準備・提出）。task_021（本人の声を通知音にする）は任意。

## 13. Verification Commands

現時点でリポジトリに存在する検証コマンドは **ない**（コードもビルド設定もない）。task_001 が以下を作成し、以降のタスクはこれらを使う。

- `scripts/test-core.sh`（中身は `swift test --package-path Packages/SaydoCore`）
- `scripts/build-ios.sh`（iOS 26.x シミュレータで `xcodebuild build`）
- `scripts/test-ios.sh`（同シミュレータで `xcodebuild test`）

task_001 完了前にこれらを実行しないこと。

## 14. Acceptance Criteria

1. オンボーディング完了後、通知をタップしてからユーザーが一切タップせずに TTS の質問が始まり、話し始めると自動で録音・認識され、無音で自動終了する。
2. 朝フローで宣言音声が保存され、行動時刻に「朝のあなたからです。」通知が届き、タップすると本人の宣言音声がそのまま再生される。
3. 昼フローで「まだ」を選ぶと行動がさらに小さくなり、`Commitment` が更新される。
4. 夜フローの「明日はどうする？」の回答が翌朝の M0 に引き継がれる。
5. Voice Timeline に当日の全 `VoiceEntry` が時刻順に並び、各エントリを再生できる。
6. 7 日分のデータで週次分析が表示され、分野上位と理由の割合が実データと一致する。
7. Apple Intelligence 非対応（またはオフ）端末で、Tier B のまま朝・昼・夜が完走する。
8. すべての TTS 文言・通知文言・LLM 出力が禁止語リストを通過する（テストで保証、LLM 出力は置換で保証）。
9. アプリの外部通信がゼロ（ネットワークアクセスのコードが存在しない。App Store のプライバシー表示は「データを収集しない」）。
10. `scripts/test-core.sh` と `scripts/test-ios.sh` が緑。
11. 朝フローが 3 分、昼・夜が 1 分を超えない（`SessionLog` の計測で 7 日間の中央値）。

## 15. Repair Loop

1. 検証コマンド（`scripts/test-core.sh` → `scripts/build-ios.sh` → `scripts/test-ios.sh`）を実行する。
2. エラー出力を全文取得する（要約しない）。
3. エラーの発生ファイルを 11 章の表と `docs/task-list.json` の `files_to_create / files_to_modify` に照合して `task_id` を特定する。
4. その `task_id` に属するファイルだけを修正する。無関係なリファクタは行わない。
5. 1 に戻って再実行する。
6. 実装が本計画から外れた場合は、本書の該当章と `docs/task-list.json` を先に更新してからコードを直す。
