# 統合後の設計判断と第 2 波の実行計画（2026-09-04 / 判定: Fable 5.1）

対象: `integration` ブランチ（12 ブランチ統合済み、5 検証コマンド exit 0）以降の残作業。
`docs/PROGRESS.md` の integration エントリ「未解決」に列挙した引き継ぎ事項へ、ここで判断を付ける。
task-list.json と食い違う場合は **この文書と `fix-decisions-2026-09-04.md` を優先** する。

## A. 設計判断（未決 8 件）

| ID | 論点 | 判断 | 根拠 |
|---|---|---|---|
| D1 | `Commitment.plannedPlace` が無い（計画 §10 との不一致） | **モデルに `plannedPlace: String?` を追加する**（V1 のまま。配布済みビルドが無いのでマイグレーション不要）。`CommitmentSnapshot` / `CommitmentDraft` にも同名で追加し、`SessionViewModel` が M3 の場所を保存する。TodayView の宣言カードに「14:00・机で」の形で出す | R11「何時に、どこで？」を一問で聞く以上、答えを捨てるのは本人の言葉を軽んじる（§22-6） |
| D2 | 文言バリエーション履歴（R5）が永続化されていない | **`App/Data/CopyHistoryStore.swift`（UserDefaults、JSON 配列、3 日より古い記録は読み込み時に捨てる）を新設**し、`SessionViewModel` が `CopyPicker` へ渡す。`AppSettings` には入れない（task_013 が同ファイルを触るため） | 3 日以内の重複回避はセッションをまたいで初めて意味を持つ |
| D3 | `weekendNotificationsEnabled` の既定 true | **true のまま** | R2 は「週末は既定で **オフにできる**」であり、既定オフではない。土日に沈黙すると 2 日空白が生まれ R4 の再入場文言が毎週出る |
| D4 | `aloneTime` の既定 nil → 夜の時刻にフォールバック | **現状維持**。オンボーディングで必ず尋ね、未回答なら夜の時刻を使う | 既定値を捏造するより、本人の生活時間を聞く方が R1 の意図に合う |
| D5 | Time Sensitive エンタイトルメント | **`project.yml` の Saydo ターゲットに `entitlements` を追加**（`com.apple.developer.usernotifications.time-sensitive: true`）。生成物 `App/Saydo.entitlements` は XcodeGen に作らせる（`entitlements.path` + `properties`）。シミュレータビルド（CODE_SIGNING_ALLOWED=NO）には影響しない | 行動時刻通知は `.timeSensitive` 指定済みだがエンタイトルメント無しでは `.active` に降格される |
| D6 | 通知アクション「今は話せない」 | **実装する**。`NotificationCopy.busyNowActionIdentifier` / `busyNowActionTitle`（「今は話せない」）、`DeepLink.Action.snooze`、`NotificationScheduler.snooze(_ link:)` が同じ内容を 60 分後に 1 件だけ再登録（識別子 `<slot>-yyyyMMdd-snooze<n>`、n は 1..2、同日 3 回目は登録しない）。`AppDelegate` は `.snooze` でフローを開かない。`Commitment` に未達を記録しない。識別子と上限の純ロジックは SaydoCore（`NotificationPlan` の拡張）に置きテストする | task-list task_009 scope 末尾の要件。R3 と同じく「休む」を失敗にしない |
| D7 | lint WARN（列挙型 `displayName` / Flow のチップ文言 / 週次テンプレート） | **今回は移さない**。exit code に影響しない。Copy への移動は task_018（仕上げ）で判断する | 第 2 波の並列作業で Flow ファイルを触ると衝突源になる |
| D8 | `SessionLog` の読み書きが `SessionViewModel.swift` にある | **`App/Data/Repository.swift` へ移す**（task_008-core の申し送り） | 置き場所の是正のみ。挙動は変えない |
| D9 | 昼フローで `MicroAction` を `Commitment` から復元していない | **復元する**。`NoonFlow.start` 前に `todayCommitment` の `microAction` / `plannedAt` / `plannedPlace` を `FlowState` に載せる | N3 で「今の行動文」を読み上げるのに必要 |
| D10 | M1 の 2 分割（理由分類と追加質問を別呼び出しに） | **task_015 で SaydoAI 側を直す**。第 2 波では触らない | task_003 の発見。UI 波と独立 |
| D11 | 画面の配色・文字階層 | **`App/Features/Shared/SaydoTheme.swift` を唯一の出所にする**（integration に先行コミット）。画面ファイルに HEX やサイズを直書きしない。値は `docs/design/design-notes.md` | 6 画面を並列で作るため、統合時に見た目がばらけるのを防ぐ |
| D12 | 記録タブの View 名 `TimelineView` が SwiftUI の `TimelineView` と衝突 | **`VoiceTimelineView` に改名**（ファイルも `VoiceTimelineView.swift`）。以後、SwiftUI / Foundation の型と同名の View・型をアプリ側に作らない | 第 2 波の統合で F の `PlaybackCardView` の `TimelineView(.animation)` が B の型に解決されコンパイルエラーになった。`SwiftUI.` で毎回修飾するより、名前を避ける方が再発しない |

## B. 第 2 波の並列計画（実装は Opus、worktree は `integration` から切る）

harness-design §4 の「直列必須: 008 → 009 → 010 → 011 → 012 → 013」は `SessionViewModel` の共有が理由。
第 2 波では **`SessionViewModel.swift` を触るのは 1 エージェント（F）だけ** にし、他は新規ファイル中心で並列化する。
各エージェントは下表の「所有ファイル」以外を変更しない（読むのは自由）。所有が無いファイルに変更が要る時は、
実装せず「統合時の継ぎ目」として PROGRESS に書く。

| ID | ブランチ | 内容 | 所有ファイル（作成・変更） |
|---|---|---|---|
| A | `task/008-session-ui` | task_008 の UI 部分 + task_009 残件のうち `AppRouter`。`SessionView`（波形・1 行の質問・状態行・チップ・右下キーボード・「話せない時」トグル・M0 文字起こし 1 行と再録音・マイク拒否の掲示）、`WaveformView`（design-notes の式）、`ChoiceChipsView`（7 個が SE × xxxLarge に収まる）、`TextFallbackSheet`、`AppRouter`（`SessionLauncher` 準拠、`DeepLink` → セッション表示）、`RootView`（TabView 2 タブ。Today / Timeline は **RootView.swift 内のプレースホルダ**）、`SaydoApp`（RootView 表示、`appDelegate.setLauncher(router)`、起動即 SessionView） | `App/Features/Session/{SessionView,WaveformView,ChoiceChipsView,TextFallbackSheet}.swift`、`App/AppRouter.swift`、`App/RootView.swift`、`App/SaydoApp.swift`。**`SessionViewModel.swift` は変更禁止**（足りない表示用プロパティは既存 API から導出するか継ぎ目として報告） |
| F | `task/010-noon-night` | task_010 + task_011 の ViewModel 側と専用画面。D1 / D2 / D8 / D9 の実装、R8 の「イヤホンで聞く / 文字で読む」判定（`AudioSessionControlling.requiresAudiblePlaybackConfirmation`）を `SessionViewModel` に配線、`PlaybackCardView`（再生リボン・声なしの日は宣言テキスト大表示）、`ListenModeSheet`、`TodayView`（宣言カード + 「今話す」+ 通知再許可の導線。セッション開始はクロージャで受ける）、`SessionViewModelTests` に昼 3 分岐 / 入口 3 状態 / 夜→翌朝の引き継ぎ / R8 のテスト | `App/Features/Session/{SessionViewModel,PlaybackCardView,ListenModeSheet}.swift`、`App/Features/Today/TodayView.swift`、`App/Data/{Repository,CopyHistoryStore}.swift`、`App/Data/Models/Commitment.swift`、`Tests/SaydoTests/{SessionViewModelTests,RepositoryTests}.swift` |
| B | `task/012-timeline` | task_012。`TimelineView`（記録がある日だけ、休みの日は出さない、`audioPath == nil` は再生無し）、`VoiceEntryRow`（ストローク SVG 風マイク + 時刻 + 文字起こし + 再生）、単一再生の制御。上部に Insight カード用の差し込み口（`topAccessory: () -> some View`）。TabView 導入は A の RootView が担うため **SaydoApp / AppRouter は触らない** | `App/Features/Timeline/{TimelineView,VoiceEntryRow,TimelinePlayback}.swift`、`Tests/SaydoTests/TimelineGroupingTests.swift` |
| C | `task/013-onboarding-settings` | task_013 + task_019 の UI 部分。`OnboardingView`（コンセプト → マイク → 通知 → 時刻 → 一人で話せる時間 → 音声モデル案内 → バックアップ注意）、`PermissionsViewModel`、`AssetDownloadView`、`SettingsView`（時刻・3 回モード・週末オフ・一人で話せる時間・TTS 音声・無音秒数・「話せない時を自動で使う時間帯」・開発者向け節・書き出し（`DataExporter` + ShareLink）・全削除（`Repository.deleteAll` + `removeAllManagedPending` + `AppSettings.reset`）・バックアップ注意）。設定変更で `NotificationScheduler.reschedule` を呼ぶ | `App/Features/Onboarding/{OnboardingView,PermissionsViewModel,AssetDownloadView}.swift`、`App/Features/Settings/SettingsView.swift`、`App/Data/AppSettings.swift`（追加のみ）、`Tests/SaydoTests/AppSettingsTests.swift` |
| D | `task/009-residual` | D5 + D6。エンタイトルメント、「今は話せない」アクション（Copy・DeepLink・Scheduler・AppDelegate）、SaydoCore 側の識別子・上限ロジックとテスト、Guardrails 通過テスト | `project.yml`、`Packages/SaydoCore/Sources/SaydoCore/Notifications/{NotificationCopy,NotificationPlan}.swift`、同 Tests、`App/Notifications/{NotificationScheduler,DeepLink}.swift`、`App/AppDelegate.swift`、`Tests/SaydoTests/DeepLinkTests.swift` |
| E | `task/016-insight-view` | task_016 のアプリ側。`WeeklyInsightView`（上位 5・理由の帯・振り返り 1 文・データ不足表示）、`InsightCardView`（3 件目の 1 行インサイト。Timeline 上部に差し込む部品）、`Repository+Insight.swift`（3 件目判定と週次の取得。**Repository.swift 本体は触らない**） | `App/Features/Insight/{WeeklyInsightView,InsightCardView,InsightViewModel}.swift`、`App/Data/Repository+Insight.swift`、`Tests/SaydoTests/InsightViewModelTests.swift` |

第 2 波に **含めない**: task_015（AI 組み込み。F の後、`SessionViewModel` を触る）、task_023 本実装（実機スパイクの Go / No-Go 待ち）、task_018、task_020、task_013b（人間）。

### 継ぎ目（統合セッションが配線する箇所）

1. `RootView` のプレースホルダを `TodayView`（F）と `TimelineView`（B）に置き換える。`TimelineView` の `topAccessory` に `InsightCardView`（E）。
2. `SessionView` の `.playback` 表示に `PlaybackCardView`（F）、R8 の確認に `ListenModeSheet`（F）を差し込む。
3. `RootView` のオンボーディング分岐に `OnboardingView`（C）、「今日」右上に `SettingsView`（C）。
4. `AppRouter` から `.snooze`（D）を無視する分岐。
5. `SessionViewModel` の新 API（D1 `plannedPlace` 保存、`listenModePrompt` 等）を `SessionView` が読む部分。

### 検証と報告（全エージェント共通）

- `scripts/test-ios.sh` は同時実行を lock で直列化する（integration で追加）。待ちが出るのは正常。`scripts/build-ios.sh` と `scripts/test-core.sh` は並列に実行してよい。
- verify_commands の全文は `docs/logs/<task_id>-<n>.txt`、PROGRESS には exit code と末尾 30 行。
- `scripts/lint-principles.sh` の WARN は既存分（D7）を除き増やさない。新しいユーザー向け文言は `DialogueCopy` / `NotificationCopy` / `InsightCopy` か、画面専用なら `App/Features/<画面>/<画面>Copy.swift`（`*Copy.swift` は lint 対象外）に置く。
- 実機でしか確認できない項目は「人間の確認待ち」に手順を書き、ブロックしない。
