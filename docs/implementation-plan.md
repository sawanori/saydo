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
4. **AI 実行はオンデバイス（Foundation Models）。** 利用不可の端末では同じフローがテンプレート＋選択肢で動く（Tier B）。UI は Tier に依らず同一。Apple Intelligence 対応機は iPhone 15 Pro 以降に限られ、iOS 26 対応機の過半が Tier B になる前提で、**Tier B を主戦場として設計する**（Tier A は上積み）。
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
| 対話 AI（LLM） | Foundation Models `SystemLanguageModel.default` | Apple Intelligence 対応機のみ。`availability` で `deviceNotEligible` / `appleIntelligenceNotEnabled` / `modelNotReady` を判定。**Tier A と見なすのは `availability == .available` かつ `SystemLanguageModel.default.supportsLocale(Locale(identifier: "ja_JP"))` が真の場合の両方が揃ったときだけ。** `supportsLocale` の実在は task_003 で確認し、無ければ日本語プロンプトを 1 回試行した結果で代替する。 |
| 音声合成（TTS） | `AVSpeechSynthesizer` | ja-JP 音声。高品質音声は端末の設定でダウンロード可能なため設定画面から案内。 |
| 永続化 | SwiftData + アプリ領域の音声ファイル（AAC） | 自前サーバーなし。 |
| バックアップ | iCloud バックアップ（アプリデータは既定で対象） | 複数端末同期（CloudKit）は非スコープ。 |
| 通知 | `UserNotifications`（ローカル通知） | 既定は朝 1 回 + 行動時刻 1 回。昼・夜は設定の「3 回モード」で追加する。繰り返しトリガーは使わず 7 日分を都度再計画する（§7.4）。 |
| 将来の高性能モデル | `PrivateCloudComputeLanguageModel`（iOS 27 beta で文書化） | v1 の依存にしない。Phase 4 以降の選択肢。 |

### 0.3 段階と出口条件

| Phase | 内容 | 出口条件 | 目安（1 人・Claude Code 主導） |
|---|---|---|---|
| 0 | 環境構築 + 技術スパイク（LLM 日本語品質 / 音声パイプライン） | Go / No-Go を `docs/spikes/` に記録 | 3〜4 日 |
| 1 | コアループ（Tier B、AI なし）: 朝 → 昼 → 夜 → 翌日引き継ぎ、通知、Voice Timeline、オンボーディング | 実機で 1 日分が通り、TestFlight 内部配布 #2 まで到達（#1 は task_010 完了時点で本人のみに配る） | 約 10 日 |
| 1.5 | ドッグフーディング | 7 日連続使用。文言・無音閾値・通知時刻の修正リスト | 7 日（Phase 2 と並行） |
| 2 | AI 層（Foundation Models）+ 週次分析 | Tier A/B 自動切替。ガードレール通過率 100%（違反は置換される） | 約 5 日 |
| 3 | 仕上げ・審査 | App Store 提出 | 約 5 日 + 待ち時間 |

- Phase 3 には自分では短縮できない待ち時間が含まれる: 外部 TestFlight のベータ審査待ち（1〜2 日）と App Review（1〜3 日。リジェクト 1 回分の再提出を見込む）。
- Phase 0 の前提として実機の確保が要る。Apple Intelligence 対応機（iPhone 15 Pro 以降）が手元に無い場合は、Tier A の実機検証を見送るか端末を購入するかを task_003 の結果を見て判断する。Tier B の実機検証は iOS 26 が動く任意の iPhone で行える。
- 目安は実測で更新する。待ち時間と実機確保を含めた合計はおよそ 7〜8 週間。

### 0.4 最初の 1 週間で潰すリスク（スパイク）

| ID | リスク | 検証方法 | No-Go 時の代替 |
|---|---|---|---|
| S-A | Foundation Models の日本語品質（理由分類・5 分以下への細分化・短い追加質問） | macOS CLI `fm-probe` に 20 件のフィクスチャを流し、人手採点（採用可 / 要修正 / 不可）。**合格基準: 20 件中 16 件以上が採用可、生成文の禁止句 0 件、1 呼び出しの所要時間が p50 で 4 秒以内** | Tier B 固定で出荷。Phase 4 で iOS 27 の PrivateCloudComputeLanguageModel、または Claude API + 薄いプロキシ（Cloudflare Workers）を検討 |
| S-B | SpeechAnalyzer ja-JP のライブ認識精度と遅延、録音との同時実行、無音自動停止、TTS との半二重切替 | iOS スパイクアプリを実機で計測。**合格基準: 10 文中 8 文が意味の通る文字起こし、無音自動停止の誤作動が 10 回中 1 回以下、通知タップから TTS 開始までが 1.5 秒以内（5 回中 4 回）** | `SFSpeechRecognizer`（オンデバイス指定）へフォールバック。その場合のみ音声認識権限が必要 |
| S-C | 通知タップから TTS 発話開始までの時間（目標 1.5 秒以内） | 実機でストップウォッチ計測 5 回。**合格基準は S-B と同一（5 回中 4 回が 1.5 秒以内）で、同じ計測を共有する** | 起動時にオーディオセッションと音声アセットをプリウォーム |
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
- Git: SAYDO は独立リポジトリとして GitHub の `sawanori/saydo` に接続済みで、初回コミットも完了している。したがって **task_001 に `git init` は含めない**（親のホームディレクトリ `/Users/noritakasawada` がコミット 0 件の git リポジトリである点は変わらないが、SAYDO はその影響を受けない）。task_001 は既存リポジトリの上で `.gitignore` と `project.yml` 以下を追加する。
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
| 4 | AI による追加質問 | task_005, task_005b（テンプレート）, task_014, task_015（AI） |
| 5 | 逃げたい理由の整理 | task_005, task_005b, task_015 |
| 6 | 行動を 5 分以下に分解 | task_005b（`ShrinkLadder`）, task_015 |
| 7 | 今日の行動時間を設定 | task_005b（`JapaneseTimeParser`）, task_008 |
| 8 | 本人による音声宣言 | task_008 |
| 9 | 昼の通知 | task_009 |
| 10 | 朝の本人音声の再生 | task_010 |
| 11 | 状態確認 | task_010 |
| 12 | 行動できていない場合の再分解 | task_005b, task_010, task_015 |
| 13 | 夜の振り返り | task_011 |
| 14 | 翌日への引き継ぎ | task_011 |
| 15 | Voice Timeline | task_012 |
| 16 | 1 週間単位の簡易分析 | task_016 |

加えて: オンボーディング（権限・通知回数と時刻設定）（task_013）、設定（task_013）、データの書き出しと全削除（task_019）、TestFlight 内部配布 #1 / #2（task_010 / task_013b）、App Store 提出準備（task_020）。retention-strategy.md の R1〜R11 も Phase 1〜2 の必須スコープに含める（反映先は §7.2 / §7.3 / §7.4 / §7.6 / §8）。

## 5. Non-Scope

- 企画書 §18 の全項目（高機能 TODO、カレンダー、プロジェクト管理、ガントチャート、複雑な習慣管理、SNS、ランキング、競争、過剰なゲーミフィケーション）
- §16 の逃避検知（DeviceActivity / Screen Time API 連携）
- Android 版、Apple Watch、ウィジェット、Live Activity
- アカウント、サーバー、クラウド LLM、複数端末同期（CloudKit）
- 課金・サブスクリプション
- 日本語以外のローカライズ
- テキストチャット UI（テキスト入力は騒音時の補助のみ）

## 6. Assumptions

1. 最小 OS は iOS 26.0。Apple Intelligence 非対応機は Tier B（テンプレート）で全機能が動く。Apple Intelligence 対応機は iPhone 15 Pro 以降に限られるため、**iOS 26 対応機の過半は Tier B になる**。Tier B を主戦場として設計し、Tier A はその上積みとして扱う（品質・文言・所要時間の目標はすべて Tier B で満たす）。
2. 言語は日本語のみ（UI・音声認識・音声合成すべて ja-JP）。
3. 利用者は端末につき 1 人。
4. 音声ファイルは端末内に保存し、iCloud バックアップの対象から除外しない。AAC 32 kbps モノラル × 15 秒でおよそ 60 KB/件、1 日 5 件で約 300 KB、年間およそ 110 MB。復元は iOS の端末バックアップに委ねる。**iCloud バックアップが無効な端末では音声が端末内にしか残らない**ため、その旨をオンボーディングと設定画面に明示する（task_013・task_019）。
5. 通知の既定は朝 1 回（8:00）+ 行動時刻 1 回。昼 13:00 と夜 21:00 は設定の「3 回モード」で追加する（時刻はいずれも変更可、週末オフも可）。すべて非繰り返しトリガーで 7 日分ずつ登録する。
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
  scripts/        build-ios.sh, test-ios.sh, build-mac.sh, test-core.sh, lint-principles.sh
  docs/           本計画、PROGRESS.md、spikes/、dogfood/、logs/、app-store/
```

- フロントエンド: SwiftUI。画面は Today（セッション）、Timeline、Insight、Onboarding、Settings の 5 つ。
- バックエンド: なし。
- データベース: SwiftData（端末内）。
- 認証: なし。
- ストレージ: SwiftData ストア + `Application Support/Saydo/Audio/yyyy/MM/<uuid>.m4a`。ファイル保護は `completeUntilFirstUserAuthentication`（通知タップ直後の再生をロック解除後に保証するため）。
- インフラ: なし。TestFlight / App Store Connect のみ。

### 7.2 会話の制御方式（状態機械 + 穴埋め LLM）

- `FlowMachine` は `SessionType`（morning / noon / night / adhoc）ごとの `FlowStep` 列を持ち、各ステップは「発話（TTS）→ 入力（音声 / 選択肢 / テキスト）→ 処理（DialogueEngine 呼び出し or 決定的処理）→ 保存」の 4 段で構成する。
- `FlowMachine` の入力イベントに `interrupted`（着信・Siri 起動・オーディオ経路変更）を持たせる。`interrupted` を受けたら途中状態（`lastStep` と入力済みの値）を保存してセッションを閉じ、次回起動時にそのステップから再開する。
- `DialogueEngine` プロトコルに `TemplateDialogueEngine`（Tier B）と `FoundationModelsDialogueEngine`（Tier A）の 2 実装。Tier は起動時に `SystemLanguageModel.default.availability == .available` かつ `SystemLanguageModel.default.supportsLocale(Locale(identifier: "ja_JP"))` が真であることの両方で決める（§0.2 の対応表を参照。`supportsLocale` の実在は task_003 で確認する）。
- LLM 呼び出しは 1 ステップ 1 回、タイムアウト 6 秒。失敗・タイムアウト・ガードレール違反はすべてテンプレート出力に置換し、会話は止めない。
- 発話の保存: M0（逃げたいこと）・M1（理由）・M4（宣言）・N1（状態）・N2（止めているもの）・E0（前進）・E1（明日）はいずれも `VoiceEntry` として音声と文字起こしを残す。kind は §10 の一覧（avoidance / reason / declaration / status / blocker / progress / tomorrow）をそのまま使う。選択肢で答えた場合は音声なしで文字起こし相当のテキストだけを残す。
- タイムボックス: 朝 3 分、昼 1 分、夜 1 分。各「聞く」区間は最長 20 秒。**沈黙は最大 5 秒で「長く考えなくていい。10 秒で答えて。」を 1 回だけ挟み、さらに 10 秒沈黙が続いたらその質問をスキップして次のステップへ進む。** タイムボックスを超えた場合は「続きは昼に聞くね。」と言い、そこまでの入力を保存して終了する。
- TTS 音声: enhanced / premium の ja-JP 音声が端末にインストール済みならそれを使い、無ければ既定音声で開始する。オンボーディングと設定画面で高品質音声のダウンロード手順を案内する（アプリからは強制できない）。
- チップ（選択肢）の出しどころ: **答えを選ばせるチップは M1（理由）・N1（状態）・E0 の前進なし分岐の 3 か所だけ。** M0・M3・M4 にはチップを出さず、音声（または「話せない時」モード）で答える。M2 と N3 の一般形 4 つは「答えに詰まったときの例示」であって選択肢ではなく、本人が自分の言葉で言うのが既定。キーボードは常時、画面右下の小さなボタンとして置くだけにして自動表示しない。
- 「話せない時」モード（R1）: オンボーディングと会話画面から切り替えられる第一級のモード。M0〜M3 を選択肢と短文入力だけで完走でき、M4（声の宣言）だけを「後で声で」に回せる。後回しにした場合、オンボーディングで聞いた「一人になれる時刻」に「30 秒だけ、声で約束して。」を **1 回だけ** 通知する（再通知はしない）。
- マイク権限が拒否された場合: テキスト入力で朝・昼・夜すべてを完走できる。ただしその日の `Commitment` には「声なし」フラグを立て、昼 N0 では宣言音声の代わりに **本人の宣言テキストを画面に大きく表示**して「朝のあなたからです。」とだけ読む（本人の言葉を TTS で読み上げ直さない。本人の言葉は本人に見せる）。同時に設定アプリでマイクを許可する導線を出す。
- 文言バリエーション（R5）: `DialogueCopy` は主要 8 文言について 5 種類以上の言い換えを配列で持ち、3 日以内に同じ文言を繰り返さない。可能な箇所では本人の名詞（「見積書」「クライアント」）をそのまま埋め込む。
- 空白後の再入場（R4）: 前回の記録から 2 日以上空いた次の起動では、M0 を「おかえり。今日から、また一つだけ。」に差し替える。空白日数・連続日数には一切言及しない。

#### 朝（MorningFlow）

| Step | 発話（テンプレート） | 入力 | 処理 |
|---|---|---|---|
| M0 | 「おはよう。今日、いちばん逃げたいことは何？」（前夜の引き継ぎがあれば「昨日の夜『◯◯』って言ってたね。今日はそれでいく？」+ 選択肢。2 日以上空いた後は「おかえり。今日から、また一つだけ。」） | 音声 | `AvoidanceItem` 作成、`VoiceEntry(kind: avoidance)` 保存。**「特にない」と答えた場合は「それは良い日。10 秒で終わるね。」で終了し、良い日として Timeline に残す**（R6。逃げたいことを無理に作らせない） |
| M1 | Tier A: LLM が生成した 1 文の追加質問。Tier B: 「一番近いのはどれ？」+ 選択肢 7 種（気まずい / 完璧にやりたい / 面倒 / 不安・怖い / 量が多い / 何から始めるかわからない / 期限が怖い） | 音声 or 選択肢 | `ReasonCategory` 確定（音声はキーワード照合、Tier A は LLM 分類）。理由を声で答えた場合は `VoiceEntry(kind: reason)` として保存する |
| M2 | Tier A: LLM が 5 分以下の行動を 3 案生成し、1 案目を読み上げ。Tier B: **「最初の 5 分でできる、いちばん小さいことは？」と本人に言わせ、本人の言葉をそのまま行動文にする**（自由発話から名詞を機械的に切り出さない）。例示チップは分野に依らない一般形の 4 つ（開くだけ / 1 行だけ書く / 必要なものを机に置く / 相手の名前を検索する）。常に「もっと小さく」を選べる | 音声 or 選択肢 | `MicroAction` 確定。「もっと小さく」は `ShrinkLadder`（一般形の段階表: 開く → 一部だけ → 1 行だけ → 置くだけ）を 1 段下る。段階表はメール専用にしない |
| M3 | 「今日は何時に、どこでやる？」+ 選択肢（1 時間後 / 午後 / 夕方 / 時刻を選ぶ）。時間と場所を **同じ一問** で聞き、会話時間は増やさない（R11） | 音声 or 選択肢 | 日本語時刻パース（「14 時」「2 時」「午後 2 時」「昼過ぎ」）。場所は本人の言葉のまま `MicroAction` に添える |
| M4 | 「じゃあ最後に、自分に約束してください。今日やることを声に出して。」 | 音声（30 秒以内） | 宣言音声を保存、`Commitment` 作成、行動時刻の通知を登録。「受け取りました。◯時に、朝のあなたから届きます。」。**「話せない時」モードでは「後で声で」を選べ、その場合は宣言テキストだけで `Commitment` を作り、一人になれる時刻に 1 回だけ再通知する** |

#### 昼（NoonFlow。行動時刻通知・昼通知・手動起動で共通）

**入口の条件（NoonFlow を開く前に必ず判定する）**

| 状況 | 挙動 |
|---|---|
| 当日の `Commitment` が無い（朝を飛ばした） | 昼・夜の通知タップは NoonFlow ではなく **短縮版の朝フロー（M0 → M2 → M4）** を開く。理由（M1）は聞かない |
| `Commitment.outcome == done` | 固定の昼通知と行動時刻通知を取り消す。手動起動時は「今日はもう動けてる。」で終了する |
| 現在時刻 < `Commitment.plannedAt` | 「どうだった？」は出さない。固定の昼通知は送らず、行動時刻通知だけを送る。手動起動時は「◯時の約束、まだ生きてる？」+ 選択肢（はい / 時間を変える）で終了 |
| 上記以外 | 下表の N0 から通常どおり進む |

| Step | 発話 | 入力 | 処理 |
|---|---|---|---|
| N0 | 「朝のあなたからです。」→ 宣言音声を再生 | なし | 再生完了を待つ。**イヤホン未接続かつ消音スイッチが ON の場合は、再生と TTS を始める前に「イヤホンで聞く / 文字で読む」を出す**（R8。文字で読んだ場合も体験は成立させる）。「声なし」フラグが立っている日は宣言テキストを画面に大きく表示し、「朝のあなたからです。」だけを読む |
| N1 | 「どうだった？」+ 選択肢（やった / 少しやった / まだ） | 音声 or 選択肢 | `Commitment.outcome` 更新。声で答えた場合は `VoiceEntry(kind: status)` として保存。「やった」なら「それを残しておくね。」で終了。**「少しやった」も前進として扱い、`outcome = partial` にして「それを今日の前進として残すね。」で終了する（N2 に進まない）** |
| N2 | 「何が止めてる？」 | 音声 | `VoiceEntry(kind: blocker)` 保存 |
| N3 | Tier A: LLM が blocker を踏まえて行動を縮小。Tier B: **「じゃあ今は◯◯しなくていい。最初の 5 分でできる、いちばん小さいことは？」と本人に言わせ、本人の言葉をそのまま新しい行動文にする**（例示チップは M2 と同じ一般形 4 つ）。`ShrinkLadder` を 1 段下るのは本人が「決められない」を選んだときだけ。+ 選択肢（1 時間後にもう一度 / 今日は捨てる / 明日に回す）。**企画書 §9 の 6 選択肢は、夜 E0 ではなくこの N3 と翌朝 M0 の引き継ぎ確認で使う** | 音声 or 選択肢 | `MicroAction` 更新（`shrinkCount` +1）、必要なら通知を再登録 |

#### 夜（NightFlow）

| Step | 発話 | 入力 | 処理 |
|---|---|---|---|
| E0 | 「今日、少しでも前に進めたことは？」 | 音声 | `VoiceEntry(kind: progress)` 保存。「それを今日の前進として残します。」。**前進がない場合は「今日はそういう日。明日、もっと小さくしよう。」とだけ言い、チップは「もっと小さくする / 明日に回す」の 2 つに絞る**（その日を否定的にラベル付けしない） |
| E1 | 「明日はどうする？」 | 音声 | `VoiceEntry(kind: tomorrow)` 保存、翌朝の M0 用に引き継ぎを作成。「明日の朝、聞くね。」で終了 |

### 7.3 音声パイプライン（1 入力 2 消費）

- `AVAudioEngine` の入力ノードにタップを 1 つ設置し、同じバッファを (a) `AVAudioFile`（AAC 32 kbps モノラル、`.m4a`）への書き込みと (b) SpeechAnalyzer へ流す。(c) RMS を `WaveformSampler` に渡して波形描画に使う。
- SpeechAnalyzer への受け渡し: **`AnalyzerInputConverter` は iOS 26.2 SDK に存在しない前提で書く。** `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` が返す形式へ `AVAudioConverter` で変換し、`AnalyzerInput(buffer:)` を生成して `AsyncStream` に流す。iOS 27 以降で `AnalyzerInputConverter` が使えるようになった場合はそこだけ差し替える（実在は task_004 で確認する）。
- 並行性: **`installTap` のクロージャは nonisolated である。** クロージャ内では `AsyncStream` の continuation に yield する（と `AVAudioFile` へ書く）だけにし、状態変更は `@MainActor` 側で行う。クロージャから actor 隔離された状態に触らない（`actor` でまとめて包む方法は採らない）。
- 無音判定 `SilenceDetector`: RMS が閾値未満の状態が 1.5 秒（設定で 1.2 / 1.5 / 2.0 秒）続いたら発話終了。`SpeechTranscriber` の確定結果（finalized）を待って処理に進む。
- 半二重: TTS 発話中は STT へ流さない。`AVSpeechSynthesizerDelegate.didFinish` の後に聞き取りを開始する。
- `AVAudioSession`: カテゴリ `.playAndRecord`、モード `.default`、スピーカー既定出力。Bluetooth オプションは iOS 26.2 SDK の最新名を S-B で確認して使う。TTS の回り込みが認識に混入する場合は `.voiceChat` モードを S-B で比較する。**消音スイッチを尊重する**: 消音を無視して鳴らす（`.ambient` 相当の切り替えで押し通す）ことはしない。イヤホン未接続かつ消音スイッチ ON の状態で通知から起動した場合は、TTS と宣言音声の再生を始める前に「イヤホンで聞く / 文字で読む」を出す。
- 「話せない時」モードとマイク拒否時は、この音声パイプライン自体を起動しない（選択肢と短文入力だけでフローを進める）。
- 音声認識モデル: 初回に `AssetInventory.assetInstallationRequest(supporting:)` で ja-JP をダウンロード。オンボーディングで進捗表示。
- 通知タップからの起動時に、オーディオセッション有効化 → TTS 開始までを 1.5 秒以内に収める（S-C）。

### 7.4 通知

- **既定は 2 回 + 1 回**（R2）: 朝と行動時刻だけを既定で送る。昼の固定通知と夜の通知は、設定画面で「3 回モード」を選んだときにだけ追加する。週末をまとめてオフにする設定も置く。時刻の既定値は朝 8:00 / 昼 13:00 / 夜 21:00 のまま（後 2 つは既定では鳴らない）。
- **繰り返しトリガーは使わない**（当日分だけをスキップできないため）: 固定通知は毎回の起動時と宣言時に、**今日から 7 日分を非繰り返しの `UNCalendarNotificationTrigger` として再計画する**。識別子は `morning-yyyyMMdd`・`noon-yyyyMMdd`・`night-yyyyMMdd` の形にし、再計画のたびに古い pending を消してから登録し直す。文言は §15 のもの。昼は「朝、自分で言ったこと覚えてる？」「例のやつ、まだ避けてる？」を日替わりで交互に使う。
- 行動時刻 1 回: 朝の M4 完了時に登録（識別子 `action-yyyyMMdd`）。文言「朝のあなたからです。」。固定の昼通知と 30 分以内に重なる場合は、その日の `noon-yyyyMMdd` だけを取り消す（非繰り返しなので翌日以降には影響しない）。
- 通知アクション「今日は休む」（R3）: すべての通知に付ける。長押しから 1 タップで当日を休みにでき、その日の残りの pending 通知を取り消す。休みは記録上「失敗」にせず（`Commitment` を作らない）、Timeline にも表示しない。`SessionLog` にだけ休みとして残す。
- `userInfo` に `sessionType` と `commitmentID` を入れ、`UNUserNotificationCenterDelegate.didReceive` から `AppRouter` が該当フローを自動開始する。当日の `Commitment` が無い場合と、既に `outcome == done` の場合の分岐は §7.2 の「入口の条件」に従う。
- 起動ごとに通知許可状態と pending 一覧を確認する。許可が拒否・失効していたり pending が空だったりする場合は、`TodayView` に再許可（設定アプリ）への導線を出す。通知が唯一の入口なので、黙って壊れたままにしない。
- 行動時刻通知は **Time Sensitive エンタイトルメントを追加して `.timeSensitive`** にする（集中モード中でも届かせる）。固定通知は通常の割り込みレベルのままにする。
- 通知本文に「未達成」「連続」などの責める語彙は使わない（`NotificationCopy` に固定し、Guardrails のテストを通す）。

### 7.5 ガードレール（責めない保証）

- **単語の部分一致ではなく句パターンで判定する**（「連続」だけで弾くと「連続して 5 分」のような無害な文まで落ちるため）。禁止句リスト（初期値）: 「未達成」「N 日連続」（数字 + 日連続）「サボ」「怠け」「言い訳」「甘え」「なぜやらない」「また逃げ」。「失敗」「ダメ」は **断定形のみ**（「失敗です」「失敗した」「ダメです」「ダメだ」）を対象にする。
- **適用範囲は生成文（LLM 出力・テンプレート文言・通知文言）だけ。** ユーザーの文字起こしには一切適用しない（本人が「またサボった」と言うのは自由で、それを弾いてはいけない）。
- 形式規則: 質問は 60 文字以内で「？」で終わる。行動文は 40 文字以内で動詞で終わる。URL・英語のみの出力を拒否。
- 違反時: 該当ステップのテンプレート文に置換し、`SessionLog` に `guardrailReplaced` を記録する（後で品質改善に使う）。

### 7.6 週次分析（Insight）

- `InsightCalculator` は SwiftData の集計だけで動く純関数: 逃げ対象の分野（`TaskDomain`: 人への返信 / お金 / 大きなタスク / 営業 / 書類 / 健康 / その他）別件数と、理由（`ReasonCategory`）別割合。
- **`WeeklyStats`（= LLM に渡す構造体）に入れるのは分野別件数と理由別割合だけ。** 宣言の結果内訳（やった / 少し / まだ）と平均縮小回数は入れない。達成率の提示は「責めない」原則と衝突するため、結果内訳は設定画面の開発者向け節にだけ表示する（retention-strategy.md §4 の計測項目と同じ扱い）。
- 振り返り文の目的は **「何から、なぜ逃げるか」を本人が理解すること** に限定する。達成度の評価・激励・次週の目標設定は書かない。
- 振り返り 1 文: Tier A は集計値だけを LLM に渡して生成（原文は渡さない → トークン節約）。Tier B は上位の理由 × 分野の組み合わせ表から選ぶテンプレート。
- 分野の判定: Tier A は `@Generable enum TaskDomain` で分類。Tier B はキーワード辞書。
- **初回インサイトは 3 件目で出す**（R9）: 週次を待たず、`AvoidanceItem` が 3 件たまった時点で「3 回のうち 2 回が『人への返信』」のような 1 行を Timeline 上部に出す。同じ計算を `InsightCalculator` の件数版として実装する。

## 8. UI Plan

| 画面 | 役割 | 状態 |
|---|---|---|
| `SessionView`（Today タブの本体） | 朝・昼・夜・手動の会話画面。中央に大きな波形、1 行の質問、状態行（「聞いています…」「考えています…」）。答えを選ばせるチップは M1・N1・E0 の前進なし分岐だけに表示（M2・N3 の一般形 4 つは例示として控えめに置く）。右下に小さなキーボードボタンを常時置く（自動でせり上げない）。「話せない時」モードへの切り替えも同じ場所から。マイク拒否時は画面上部に設定アプリへの導線を出し、昼 N0 では宣言テキストを大きく表示する | `idle` / `speaking`（TTS） / `listening` / `thinking`（LLM） / `choosing`（チップ） / `recordingDeclaration` / `playback` / `done` / `error(micDenied / assetDownloading)` |
| `TodayView` | 通知以外から開いたときの入口。今日の宣言カード（再生ボタン + 行動時刻）と「今話す」ボタン。宣言前は朝フロー、宣言後は手動チェックイン（NoonFlow）を開始 | 宣言前 / 宣言後 / 夜完了 |
| `TimelineView`（記録タブ） | 日ごとのセクションに 🎙️ + 時刻 + 文字起こし + 再生ボタン。**記録がある日だけを並べ、空白日のプレースホルダは置かない**（R4）。上部に Insight カード（3 件目以降は 1 行インサイト、7 日分そろえば週次） | 空 / 通常 / 再生中 |
| `WeeklyInsightView` | 「あなたが逃げやすいこと」上位 5、理由の割合、振り返り 1 文。達成率と平均縮小回数は出さない | データ不足（3 件未満） / 1 行インサイト（3 件以上・7 日未満） / 通常 |
| `OnboardingView` | 1 画面ずつ: コンセプト 1 文 → マイク権限 → 通知権限 → 通知の回数（既定 2 回 + 行動時刻 / 3 回モード）と時刻 → 「一人になれる時刻」（宣言を後回しにしたときの再通知先） → ja-JP 音声モデルのダウンロード進捗 → 音声が端末内にのみ残ること（iCloud バックアップが無効な場合）の説明 | 各ステップの許可 / 拒否 |
| `SettingsView` | 時刻と通知回数、週末オフ、TTS 音声の選択（高品質音声のダウンロード案内を含む）、無音判定秒数、「話せない時」モードの既定、データ書き出し、全削除、バックアップに関する注意。最下部に「開発者向け」節（結果内訳・完走率・休んだ回数など retention-strategy.md §4 の計測値） | 通常 |

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

- `@Generable` 型（SaydoAI）: `ReasonClassification { category: ReasonCategory; followUp: String }`、`MicroAction { text: String; estimatedMinutes: Int(@Guide(.range(1...5))) }`、`TaskDomain`（enum）。
- **`@Guide` に文字数制約は書けない。** `@Guide` で表現できるのは自然文の description と `.anyOf` / `.range` / `.count` などの構造的制約だけなので、**文字数（質問 60 文字以内 / 行動文 40 文字以内）・動詞終わり・疑問形は Guardrails の後段検査で強制する**。`@Guide` 側には「短い疑問文」「5 分以内でできる行動」といった description を置くにとどめる。
- 入力の検証: 文字起こしが空、または 2 文字未満なら「もう一度、ゆっくりで大丈夫。」と再入力（最大 2 回、その後は選択肢）。
- エラー処理: `LanguageModelSession.GenerationError` のうち以下を扱う。`exceededContextWindowSize` → 新しい `LanguageModelSession` を作って 1 回だけ再試行。`guardrailViolation` / `refusal` → その場でテンプレート文に置換して会話を続ける（再試行しない）。`unsupportedLanguageOrLocale` → セッション内で Tier B に固定する。タイムアウト 6 秒 → テンプレート置換。ここに挙げていない case 名は、実在を task_003 で確認するまで書かない（`default:` で受けてテンプレート置換に倒す）。
- プロンプト予算: 指示 600 文字以内、入力 400 文字以内、出力 200 文字以内。合計で 4,096 トークンを大きく下回る。

## 10. Database Plan（SwiftData、`VersionedSchema` V1）

| モデル | 主なプロパティ | 関係 |
|---|---|---|
| `AvoidanceItem` | id, title(本人の言葉), domain(TaskDomain), status(open / carriedOver / dropped / done), createdAt, lastTouchedAt | 1 → 多 `Commitment` |
| `Commitment` | id, dayKey(yyyy-MM-dd), microActionText, plannedPlace, plannedAt, declarationAudioPath, declarationTranscript, isVoiceless(声なし: マイク拒否 or 宣言を後回し), outcome(pending / done / partial / notYet), shrinkCount, progressNote, createdAt | 多 → 1 `AvoidanceItem`、1 → 多 `VoiceEntry` |
| `VoiceEntry` | id, recordedAt, sessionType, kind(avoidance / reason / declaration / status / blocker / progress / tomorrow), audioPath, transcript, durationSec | 多 → 1 `Commitment`（任意） |
| `SessionLog` | id, sessionType, startedAt, endedAt, completed, tier(A / B), lastStep, guardrailReplacedCount | なし |
| `Carryover` | id, forDayKey, text, sourceEntryID | なし |

- インデックス: `VoiceEntry.recordedAt`、`Commitment.dayKey`（`#Index` を V1 から付ける）。
- 制約: 「1 日 1 件のアクティブな Commitment」はスキーマではなく `Repository` で保証する。
- 削除: `Commitment` / `VoiceEntry` の削除時に `AudioFileStore` が音声ファイルを削除する（孤児ファイルの掃除を起動時に 1 回走らせる）。
- 設定値（通知時刻、通知回数モード、週末オフ、一人になれる時刻、TTS 音声 ID、無音秒数、オンボーディング完了フラグ）は `UserDefaults`。既定値は `AppSettings` に集約し、task_006 で作成する（task_013 はその UI だけを作る）。
- 音声ファイル: AAC 32 kbps モノラル。15 秒でおよそ **60 KB/件**、1 日 5 件で **約 300 KB**、年間 **約 110 MB**。iCloud バックアップの対象に含める。バックアップが無効な端末では端末内にしか残らないため、その旨をオンボーディングと設定画面に表示する。

## 11. File-by-File Plan

担当タスクは `docs/task-list.json` の `files_to_create` と一対一で対応させる。片方だけを変えないこと。

| ファイル | 種別 | 目的 | 担当タスク | リスク |
|---|---|---|---|---|
| `.gitignore` | 作成 | Xcode / SwiftPM / DerivedData / xcuserdata を除外 | task_001 | low |
| `project.yml` | 作成 | XcodeGen 定義。**task_001 は Saydo(iOS 26.0) / SaydoTests / SpeechSpike(iOS) / fm-probe(macOS CLI) の 4 ターゲットを、それぞれプレースホルダのソース付きで作る。`packages` は書かない。** SaydoCore の登録は task_002、SaydoAI の登録は task_014 | task_001（登録は task_002 / task_014） | medium |
| `App/Resources/Info.plist`（XcodeGen の `info` 設定） | 作成 | `NSMicrophoneUsageDescription`、`UILaunchScreen`、`ITSAppUsesNonExemptEncryption=false`。`NSSpeechRecognitionUsageDescription` は SFSpeechRecognizer フォールバックを同梱する場合のみ | task_001 | low |
| `App/Resources/Assets.xcassets` | 作成 | 仮 AppIcon（1024px）と AccentColor。視覚の仕上げは task_018 | task_001 | low |
| `App/SaydoApp.swift` | 作成 | 空の SwiftUI アプリとして作り、以後 task_006 / 009 / 012 / 013 / 015 が更新する | task_001 | low |
| `Tests/SaydoTests/SmokeTests.swift` | 作成 | 常に通る最小テスト（`test-ios.sh` の疎通確認用） | task_001 | low |
| `scripts/test-core.sh` | 作成 | `swift test --package-path Packages/SaydoCore`。末尾で `lint-principles.sh` を実行 | task_001 | low |
| `scripts/build-ios.sh` | 作成 | スキーム名を第 1 引数（既定 `Saydo`）で受け、利用可能な iOS 26.x シミュレータを自動選択して `xcodebuild build` | task_001 | medium |
| `scripts/test-ios.sh` | 作成 | 同上で `xcodebuild test`。末尾で `lint-principles.sh` を実行 | task_001 | medium |
| `scripts/build-mac.sh` | 作成 | macOS ターゲット（`fm-probe`）のビルド。スキーム名を引数で受ける | task_001 | low |
| `scripts/lint-principles.sh` | 作成 | `URLSession` / `import Network` / `@unchecked Sendable` / `nonisolated(unsafe)` / Copy ファイル外の日本語リテラルを検出する | task_001 | low |
| `docs/PROGRESS.md` | 作成 | 各タスクの記録欄。exit code と末尾 30 行だけを貼り、全文は `docs/logs/<task_id>-<n>.txt` に残す | task_001 | low |
| `.claude/settings.json` | 作成 | 既存の `.claude/workflows/*.js`（plan-review / task-review / copy-audit / phase-gate）を呼ぶ任意のフック | task_001 | low |
| `CLAUDE.md`（SAYDO 直下） | 作成 | 検証コマンドとモジュール構成を次セッションに伝える | task_001 | low |
| `Packages/SaydoCore/Package.swift` | 作成 | 純 Swift パッケージ（platforms: iOS 26, macOS 26） | task_002 | low |
| `Packages/SaydoCore/Sources/SaydoCore/Domain/*.swift` | 作成 | `SessionType`, `FlowStep`, `ReasonCategory`, `TaskDomain`, `MicroAction`, `ReasonClassification`, `DialogueContext`, `WeeklyStats` | task_002 | low |
| `Packages/SaydoCore/Sources/SaydoCore/Flows/{FlowMachine,MorningFlow,NoonFlow,NightFlow}.swift` | 作成 | 状態機械。副作用を持たず、入力イベント（`interrupted` を含む）から次の状態と命令（発話 / 聞く / 保存 / 通知登録）を返す | task_005 | medium |
| `Packages/SaydoCore/Sources/SaydoCore/Dialogue/{DialogueEngine,DialogueCopy,Guardrails}.swift` | 作成 | 契約、全文言（主要 8 文言は 5 種以上の言い換えを配列で持つ）、句パターンによる責めないガード | task_005 | medium |
| `Packages/SaydoCore/Sources/SaydoCore/Dialogue/{TemplateDialogueEngine,ShrinkLadder,JapaneseTimeParser}.swift` | 作成 | Tier B 実装、一般形の段階表（開く → 一部だけ → 1 行だけ → 置くだけ）、日本語時刻パース | task_005b | medium |
| `Packages/SaydoCore/Sources/SaydoCore/Notifications/{NotificationPlan,NotificationCopy}.swift` | 作成 | 7 日分の非繰り返しトリガー日時と文言の純計算（昼と行動時刻の重複ルール、「今日は休む」を含む） | task_009 | low |
| `Packages/SaydoCore/Sources/SaydoCore/Insight/InsightCalculator.swift` | 作成 | 週次集計（分野別件数・理由別割合）、3 件目の 1 行インサイト、テンプレート振り返り | task_016 | low |
| `Packages/SaydoCore/Tests/SaydoCoreTests/*.swift` | 作成 | Domain（task_002）、Flow 3 種 / DialogueCopy / Guardrails（task_005）、TemplateDialogueEngine / ShrinkLadder / JapaneseTimeParser（task_005b）、NotificationPlan（task_009）、InsightCalculator（task_016） | task_002 / 005 / 005b / 009 / 016 | low |
| `Packages/SaydoAI/Package.swift` | 作成 | FoundationModels に依存するパッケージ（iOS 26 / macOS 26）。`project.yml` への登録もここで行う | task_014 | low |
| `Packages/SaydoAI/Sources/SaydoAI/{FoundationModelsDialogueEngine,GenerableTypes,PromptBuilder,ModelAvailability}.swift` と `Tests/SaydoAITests/*` | 作成 | Tier A 実装。タイムアウト、再試行、`GenerationError` の処理、Guardrails 適用 | task_014 | high |
| `Spikes/fm-probe/main.swift` + `Spikes/fm-probe/fixtures.json` | 作成 | 日本語 20 件を流して結果を Markdown に出力（task_017 が回帰用フィクスチャを追加する） | task_003 | medium |
| `docs/spikes/fm-probe.md` | 作成 | S-A / S-D の Go / No-Go 記録 | task_003 | low |
| `Spikes/SpeechSpike/*.swift` | 作成 | STT + 録音 + 無音停止 + TTS 半二重 + 起動時間計測 | task_004 | high |
| `docs/spikes/speech-spike.md` | 作成 | S-B / S-C の Go / No-Go 記録 | task_004 | low |
| `App/Data/{Schema,AudioFileStore,Repository}.swift`, `App/Data/Models/*.swift` | 作成 | 10 章の実装 | task_006 | medium |
| `App/Features/Settings/AppSettings.swift` | 作成 | `UserDefaults` の既定値（時刻 8:00 / 13:00 / 21:00、通知回数モード、無音 1.5 秒、TTS 音声 ID、一人になれる時刻）。**UI は task_013 が作る** | task_006 | low |
| `App/Audio/*.swift` | 作成 | 7.3 の実装（SpeechSpike から昇格） | task_007 | high |
| `App/Features/Session/{SessionViewModel,SessionView,WaveformView,ChoiceChipsView,TextFallbackSheet}.swift` | 作成 | 8 章の会話画面 | task_008 | high |
| `App/AppDelegate.swift`, `App/AppRouter.swift`, `App/Notifications/{NotificationScheduler,DeepLink}.swift` | 作成 | 7.4 の実装。通知デリゲートとフロー起動ルーティング | task_009 | medium |
| `App/Features/Session/{PlaybackCardView,ListenModeSheet}.swift` | 作成 | 宣言音声の再生カードと「イヤホンで聞く / 文字で読む」の確認シート | task_010 | medium |
| `App/Features/Today/TodayView.swift` | 作成 | 入口画面 | task_010 | low |
| `App/Features/Timeline/{TimelineView,VoiceEntryRow}.swift` | 作成 | Voice Timeline（記録がある日だけを並べる） | task_012 | low |
| `App/Features/Onboarding/{OnboardingView,PermissionsViewModel,AssetDownloadView}.swift` | 作成 | 権限・通知回数と時刻・一人になれる時刻・モデル DL・バックアップの注意 | task_013 | medium |
| `App/Features/Settings/SettingsView.swift` | 作成 | 設定画面（開発者向け節を含む）。既定値は task_006 の `AppSettings` を読む | task_013 | low |
| `docs/dogfood/week1.md` | 作成 | 7 日間の観察記録と修正リスト（TestFlight 内部配布 #2 と同じタスク） | task_013b | low |
| `App/Features/Insight/WeeklyInsightView.swift` | 作成 | 週次分析と 3 件目の 1 行インサイト | task_016 | low |
| `App/Features/Settings/DataExporter.swift` | 作成 | データの書き出しと全削除 | task_019 | low |
| `docs/backup-restore-check.md` | 作成 | バックアップ復元の確認記録（ドッグフーディング 7 日間の後に実施する） | task_019 | low |
| `docs/app-store/{metadata.md,review-notes.md}` | 作成 | プライバシーポリシー URL（non-turn.com 配下の静的ページ。録音は端末内のみと明記）、非対応機での機能差（Tier B）の説明、マイク自動開始の仕様 | task_020 | medium |
| `App/Notifications/VoiceNotificationSound.swift` | 作成 | （任意）宣言音声を IMA4 の `.caf` に変換して通知音にする | task_021 | medium |

## 12. Implementation Order

1. **Phase 0**: task_001（環境。4 ターゲットを先に作る）→ task_002（SaydoCore 骨格と `project.yml` への SaydoCore 登録）→ task_003（S-A / S-D: fm-probe）と task_004（S-B / S-C: SpeechSpike）は並行可（task_004 は task_001 の完了だけを待つ）。
2. **Phase 1**: task_005（Flow + 文言 + Guardrails）→ task_005b（TemplateDialogueEngine + ShrinkLadder + JapaneseTimeParser）→ task_006（SwiftData + AppSettings）→ task_007（音声スタック）→ task_008（朝の SessionView）→ task_009（通知）→ **task_010（昼。完了時点で TestFlight 内部配布 #1 を本人のみに出す。オンボーディングは権限要求だけの状態でよい）** → task_011（夜 + 引き継ぎ）→ task_012（Timeline）→ task_013（Onboarding / Settings / Today 導線）→ task_013b（TestFlight 内部配布 #2 と `docs/dogfood/week1.md` の作成。人間の作業を含む）。
3. **Phase 1.5**: 7 日間ドッグフーディング（`docs/dogfood/week1.md`）。並行して Phase 2 に着手。
4. **Phase 2**: task_014（SaydoAI。`project.yml` への SaydoAI 登録を含む）→ task_015（Tier 切替と各ステップへの組み込み）→ task_016（週次分析。**Tier B 経路で成立するため task_013b を待てば着手でき、task_015 は「あれば使う」**）→ task_017（AI 品質回帰ハーネス。**S-A が No-Go の場合はスキップ可**）。
5. **Phase 3**: task_018（アクセシビリティと視覚仕上げ）→ task_019（データ管理と復元確認。**復元テストはドッグフーディング 7 日間の後に行う**）→ task_020（審査準備・提出）。task_021（本人の声を通知音にする）は任意。
6. `project.yml` を変更するタスク（task_001 / 002 / 003 / 004 / 006 / 007 / 014 / 020）は main で `xcodegen generate` を実行する。worktree では `.xcodeproj` を再生成しない。

## 13. Verification Commands

現時点でリポジトリに存在する検証コマンドは **ない**（コードもビルド設定もない）。task_001 が以下を作成し、以降のタスクはこれらを使う。

- `scripts/test-core.sh`（中身は `swift test --package-path Packages/SaydoCore`）
- `scripts/build-ios.sh [スキーム]`（既定 `Saydo`。iOS 26.x シミュレータで `xcodebuild build`。スパイクは `scripts/build-ios.sh SpeechSpike`）
- `scripts/test-ios.sh [スキーム]`（既定 `Saydo`。同シミュレータで `xcodebuild test`）
- `scripts/build-mac.sh [スキーム]`（macOS ターゲット用。`scripts/build-mac.sh fm-probe`）
- `scripts/lint-principles.sh`（`URLSession` / `import Network` / `@unchecked Sendable` / `nonisolated(unsafe)` / Copy ファイル外の日本語リテラルを検出。`test-core.sh` と `test-ios.sh` の末尾から自動で呼ばれる）

task_001 完了前にこれらを実行しないこと。

## 14. Acceptance Criteria

1. オンボーディング完了後、通知をタップしてから **M1 と N1 のチップ以外のタップがゼロ** のまま TTS の質問が始まり、話し始めると自動で録音・認識され、無音で自動終了する（M0・M3・M4 にチップは出ず、M2・N3 の例示は任意）。
2. 朝フローで宣言音声が保存され、行動時刻に「朝のあなたからです。」通知が届き、タップすると本人の宣言音声がそのまま再生される。
3. 昼フローで「まだ」を選ぶと行動がさらに小さくなり、`Commitment` が更新される。
4. 夜フローの「明日はどうする？」の回答が翌朝の M0 に引き継がれる。
5. Voice Timeline に当日の全 `VoiceEntry` が時刻順に並び、各エントリを再生できる。
6. 7 日分のデータで週次分析が表示され、分野上位と理由の割合が実データと一致する。
7. Apple Intelligence 非対応（またはオフ）端末で、Tier B のまま朝・昼・夜が完走する。
8. すべての TTS 文言・通知文言・LLM 出力が禁止句パターンを通過する（テストで保証、LLM 出力は置換で保証）。ユーザーの文字起こしには禁止句を適用しない。
9. 会話の途中で着信・Siri 起動・オーディオ経路変更が起きても、`interrupted` として途中状態が保存され、次回起動時に同じステップから再開できる。
10. マイク権限を拒否した状態でも、朝・昼・夜がテキスト入力だけで完走する。その日の昼 N0 では宣言テキストが画面に大きく表示される。
11. アプリの外部通信がゼロ（ネットワークアクセスのコードが存在しない。App Store のプライバシー表示は「データを収集しない」）。
12. `scripts/test-core.sh` と `scripts/test-ios.sh` が緑（末尾の `scripts/lint-principles.sh` を含めて exit 0）。
13. 朝フローが 3 分、昼・夜が 1 分を超えない（`SessionLog` の計測で 7 日間の中央値）。

## 15. Repair Loop

1. 検証コマンド（`scripts/test-core.sh` → `scripts/build-ios.sh` → `scripts/test-ios.sh`）を実行する。
2. エラー出力を全文取得する（要約しない）。
3. エラーの発生ファイルを 11 章の表と `docs/task-list.json` の `files_to_create / files_to_modify` に照合して `task_id` を特定する。
4. その `task_id` に属するファイルだけを修正する。無関係なリファクタは行わない。
5. 1 に戻って再実行する。
6. 実装が本計画から外れた場合は、本書の該当章と `docs/task-list.json` を先に更新してからコードを直す。
