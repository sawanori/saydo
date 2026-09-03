# PROGRESS

セッション間の状態引き継ぎ。1 タスク 1 エントリ。新しいエントリを一番下に追記する。

## 記入規則

- **task_id**: `task_0NN`（`docs/task-list.json` の ID）
- **状態**: `done` / `blocked` / `needs-device` / `wip`
- **証拠**: 実行した検証コマンドと **exit code + 出力の末尾 30 行**だけを貼る。**全文ログは `docs/logs/<task_id>-<n>.txt`** に置き、パスを書く。
- **未解決**: このタスクで残した問題（次タスクが踏む地雷）
- **人間の確認待ち**: 実機・Apple Intelligence・TestFlight・課金・容量確保など、エージェントにできない作業と手順

`docs/task-list.json` は仕様であり、進捗を書き込まない。

### 雛形

```
## task_0NN — <タイトル>

- 日時: YYYY-MM-DD
- 状態: done / blocked / needs-device / wip
- ブランチ / コミット: task/0NN-xxx / <hash>

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/xxx.sh` | 0 | `docs/logs/task_0NN-1.txt` |

（各コマンドの末尾 30 行をここに貼る）

### 未解決

### 人間の確認待ち
```

---

## task_001 — リポジトリ・ツールチェーン・XcodeGen プロジェクトの初期化

- 日時: 2026-09-04
- 状態: blocked（iOS ターゲットのビルドのみ環境要因で失敗。ほかは完了）
- ブランチ: `task/001-bootstrap`

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `brew install xcodegen` → `xcodegen --version` | 0（`Version: 2.46.0`） | — |
| `xcodebuild -downloadPlatform iOS`（バックグラウンド） | 0（**中身は失敗**: 容量不足） | `docs/logs/task_001-downloadPlatform.txt` |
| `xcodegen generate` | 0 | — |
| `scripts/build-ios.sh`（Saydo） | **70** | `docs/logs/task_001-1.txt` |
| `xcodebuild -target Saydo -sdk iphonesimulator`（destination 回避の切り分け） | **65** | `docs/logs/task_001-2.txt` |
| `scripts/build-mac.sh fm-probe` | **0** | `docs/logs/task_001-3.txt` |
| `scripts/build-ios.sh SpeechSpike` | **70** | `docs/logs/task_001-4.txt` |
| `scripts/test-ios.sh` | **2**（設計どおり。iOS 26.x シミュレータ無し） | `docs/logs/task_001-5.txt` |
| `scripts/lint-principles.sh` | **0** | `docs/logs/task_001-6.txt` |

`xcodebuild -downloadPlatform iOS`（末尾）:

```
Downloading iOS 26.3.1 Simulator (23D8133) (arm64): Error: Error Domain=DVTDownloadsUtilitiesErrorDomain Code=1 "Insufficient space available. Requires 8.39 GB" UserInfo={NSLocalizedDescription=Insufficient space available. Requires 8.39 GB}
```

`scripts/build-ios.sh`（末尾）:

```
build-ios: scheme=Saydo
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build -project Saydo.xcodeproj -scheme Saydo -configuration Debug -sdk iphonesimulator -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO

Build settings from command line:
    CODE_SIGNING_ALLOWED = NO
    SDKROOT = iphonesimulator26.2

xcodebuild: error: Unable to find a destination matching the provided destination specifier:
		{ generic:1, platform:iOS Simulator }

	Ineligible destinations for the "Saydo" scheme:
		{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device, error:iOS 26.2 is not installed. Please download and install the platform from Xcode > Settings > Components. }
EXIT=70
```

destination を回避して `-target` で直接ビルドすると Swift のコンパイル（`-swift-version 6` / `-target arm64-apple-ios26.0-simulator`）までは通り、アセットカタログで落ちる:

```
/Users/noritakasawada/AI_P/SAYDO/.worktrees/task-001/App/Resources/Assets.xcassets: error: No simulator runtime version from ["22F77"] available to use with iphonesimulator SDK version 23C53
** BUILD FAILED **
EXIT=65
```

この actool のエラーは**プロジェクト側の問題ではない**。色 1 個だけの空のアセットカタログを `xcrun actool` に直接渡しても同じエラーが出る（`--platform iphoneos` でも `--platform iphonesimulator` でも、`--minimum-deployment-target` を 18.5 に下げても同じ）。Xcode 26.2 の SDK（23C53）に対して、インストール済みのシミュレータランタイムが iOS 18.5（22F77）しか無いことが原因。

`scripts/build-mac.sh fm-probe`（末尾）:

```
RegisterExecutionPolicyException /Users/noritakasawada/Library/Developer/Xcode/DerivedData/Saydo-hezvjracsfbrulejmvpjdsyfdzkj/Build/Products/Debug/fm-probe (in target 'fm-probe' from project 'Saydo')
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-001
    builtin-RegisterExecutionPolicyException /Users/noritakasawada/Library/Developer/Xcode/DerivedData/Saydo-hezvjracsfbrulejmvpjdsyfdzkj/Build/Products/Debug/fm-probe

** BUILD SUCCEEDED **

EXIT=0
```

`scripts/test-ios.sh`（全文）:

```
test-ios: iOS 26.x の利用可能なシミュレータが見つからない。
  導入コマンド: xcodebuild -downloadPlatform iOS（約 8.4 GB の空きが必要）
  現在のランタイム一覧:
== Runtimes ==
iOS 18.5 (18.5 - 22F77) - com.apple.CoreSimulator.SimRuntime.iOS-18-5
EXIT=2
```

`scripts/lint-principles.sh`（全文）:

```
lint-principles: 対象 1 ファイル（App/ と Packages/*/Sources。Tests と Spikes は除外）
lint-principles: OK
EXIT=0
```

lint 自体が機能することは、禁止パターンを全部含む一時ファイル `App/_LintProbe.swift` を置いて確認した（URLSession / import Network / @unchecked Sendable / nonisolated(unsafe) の 4 件を検出して exit 1、日本語リテラルを WARN で列挙）。確認後に削除済み。

### done_definition との対応

| done_definition | 判定 | 証拠 |
|---|---|---|
| git のトップレベルが SAYDO（task_001 から git init は除外・fix-decisions C P1.1） | 済 | worktree `task/001-bootstrap`。リポジトリは既存 |
| `xcrun simctl list runtimes` に iOS 26.x | **未達** | 容量不足でダウンロード失敗 |
| `scripts/build-ios.sh` が exit 0 | **未達（環境要因）** | 上記 exit 70 / 65 |
| CLAUDE.md に検証コマンド | 済 | `CLAUDE.md` §2（5 本） |
| 4 ターゲットがプレースホルダ付きで存在 | 済 | `project.yml`（Saydo / SaydoTests / SpeechSpike / fm-probe）+ `xcodegen generate` 成功 |
| Assets.xcassets（AppIcon 1024 + AccentColor） | 済（ビルドは上記で未検証） | `App/Resources/Assets.xcassets` |
| Info.plist に NSMicrophoneUsageDescription / UILaunchScreen / ITSAppUsesNonExemptEncryption / CFBundleDisplayName | 済 | `App/Resources/Info.plist`（生成物） |

### 未解決

- `scripts/build-ios.sh` と `scripts/test-ios.sh` は iOS 26.x シミュレータランタイムが入るまで通らない。iOS 側の検証は**この 1 点で止まる**（task_004 / 007 以降の実機作業も同じ）。
- SaydoCore / SaydoAI は `project.yml` の `packages` に未登録（task_002 / task_014 で追加する）。
- `scripts/test-core.sh` は `Packages/SaydoCore` が無い間は実行できない（task_002 で解消）。

### 人間の確認待ち

1. **ディスク容量の確保（最優先・これが全ての iOS ビルドを止めている）**: 現在の空きは 7.6 GB、必要は 8.39 GB。9 GB 以上空けてから `xcodebuild -downloadPlatform iOS` を実行する。
   - 空ける候補: 古い iOS 18.5 シミュレータランタイム（約 7 GB。`xcrun simctl runtime list -v` で確認 → 不要なら `xcrun simctl runtime delete <build>`）、`~/Library/Developer/Xcode/DerivedData`、`~/Library/Developer/Xcode/iOS DeviceSupport`。
   - **エージェントは削除を実行しない**（不可逆・他プロジェクトへの影響があるため）。
2. 導入後に `scripts/build-ios.sh` / `scripts/build-ios.sh SpeechSpike` / `scripts/test-ios.sh` を実行し、この節を更新する。

---

## task_002 — SaydoCore パッケージ骨格とドメイン型

- 日時: 2026-09-04
- 状態: done（`scripts/test-core.sh` 緑。`scripts/build-ios.sh` は task_001 と同じ環境要因で未達）
- ブランチ: `task/001-bootstrap`

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `swift build --package-path Packages/SaydoCore` | 0（`Build complete! (2.75s)`） | — |
| `xcodegen generate`（packages 追加後） | 0 | — |
| `scripts/test-core.sh` | **0**（15 tests, 0 failures） | `docs/logs/task_002-1.txt` |
| `scripts/build-ios.sh` | **70**（task_001 と同じ destination の問題。task_002 の差分とは無関係） | `docs/logs/task_002-2.txt` |

`scripts/test-core.sh`（テスト部分の末尾と lint の結論。日本語リテラルの WARN 一覧は全文ログ参照）:

```
Test Suite 'DomainTests' passed at 2026-09-04 05:48:16.543.
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.003 (0.004) seconds
Test Suite 'SaydoCorePackageTests.xctest' passed at 2026-09-04 05:48:16.543.
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.003 (0.004) seconds
Test Suite 'All tests' passed at 2026-09-04 05:48:16.543.
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.003 (0.006) seconds
lint-principles: OK
EXIT=0
```

`Saydo.xcodeproj` へのパッケージ登録（生成結果の確認）:

```
243:				40C819ECC38AF9744BB87EFD /* XCLocalSwiftPackageReference "Packages/SaydoCore" */,
643:		40C819ECC38AF9744BB87EFD /* XCLocalSwiftPackageReference "Packages/SaydoCore" */ = {
645:			relativePath = Packages/SaydoCore;
651:			isa = XCSwiftPackageProductDependency;
```

### 確定したドメイン型（後続タスクはこの名前とプロパティを変えない）

| 型 | 種別 | 内容 |
|---|---|---|
| `SessionType` | enum(String) | morning / noon / night / adhoc。displayName = 朝 / 昼 / 夜 / 手動 |
| `FlowStep` | enum(String) | morningAvoidance(M0) … morningDeclaration(M4) / noonPlayback(N0) … noonShrink(N3) / nightProgress(E0) / nightTomorrow(E1) / finished(END)。`code`・`displayName`・`sessionType`・`steps(for:)` を持つ。adhoc は空配列（入口判定は FlowMachine の担当） |
| `ReasonCategory` | enum(String) | awkward / perfectionism / tedious / anxious / tooMuch / unclearStart / deadlineFear（7 種） |
| `TaskDomain` | enum(String) | reply / money / bigTask / sales / paperwork / health / other（7 種） |
| `CommitmentOutcome` | enum(String) | pending / done / partial / notYet。`isProgress` は done と partial が true（§22-7） |
| `MicroAction` | struct | `text` / `estimatedMinutes`(既定 5) / `shrinkCount`(既定 0)、`isFiveMinutesOrLess`、`shrunk(to:estimatedMinutes:)` |
| `ReasonClassification` | struct | `category` / `followUp`（文字数と疑問形の強制は Guardrails 側） |
| `DialogueContext` | struct | `sessionType` / `step` / `avoidance` / `reason?` / `domain?` / `microAction?` / `blocker?` / `carryover?` / `outcome`。会話履歴は持たない |
| `WeeklyStats` | struct | `weekStart` / `domainCounts` / `reasonRatios` のみ（fix-decisions P2.2）。`totalCount`・`topDomains(limit:)`・`topReasons(limit:)` |

すべて `Sendable, Codable, Hashable`。enum は `CaseIterable`。

### 未解決

- `scripts/lint-principles.sh` は Domain の `displayName` を「Copy 以外の日本語リテラル」として WARN で列挙する（29 件）。これは設計どおり（task_002 の仕様が enum に日本語表示名を持たせている）で、exit code には影響しない。**この WARN を消すために displayName を移動しないこと。**
- `Packages/SaydoAI` は未作成（task_014）。
- iOS 側のビルド・テストは task_001 の「人間の確認待ち」が解消するまで通らない。

### 人間の確認待ち

- task_001 と同じ（iOS 26.x シミュレータランタイムの導入）。追加はなし。

---

## task_009-core — 通知の純ロジック（NotificationPlan / NotificationCopy）

- 日時: 2026-09-04
- 状態: done（SaydoCore の純ロジック部分のみ。task_009 の App 側は未着手）
- ブランチ / コミット: `task/009-notification-core` / （このコミット）

### スコープ

task_009 のうち **SaydoCore に置く純計算だけ**。`NotificationScheduler` / `AppDelegate` / `AppRouter` /
`UNUserNotificationCenter` / SwiftData には触れていない。

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/test-core.sh` | **0**（47 tests, 0 failures） | `docs/logs/task_009-core-1.txt` |

```
Test Suite 'NotificationCopyTests' passed at 2026-09-04 05:59.
	 Executed 9 tests, with 0 failures (0 unexpected)
Test Suite 'NotificationPlanTests' passed at 2026-09-04 05:59.
	 Executed 23 tests, with 0 failures (0 unexpected)
Test Suite 'All tests' passed
	 Executed 47 tests, with 0 failures (0 unexpected) in 0.010 (0.012) seconds
lint-principles: OK
EXIT=0
```

`scripts/build-ios.sh` は未実行（この差分に iOS ターゲットのファイルが無く、task_001 の環境要因で
どのみち exit 70 になるため）。

### 確定した通知の契約（App 側の task_009 はこの名前を使う）

| 型 | 内容 |
|---|---|
| `TimeOfDay` | `hour` / `minute`。`minutesFromMidnight`、`Comparable` |
| `NotificationSlot` | morning / noon / night / action。識別子の接頭辞。`sessionType` は action → `.noon`（行動時刻通知も NoonFlow に入る） |
| `NotificationMode` | twice（既定・朝のみ固定）/ thrice（朝昼夜）。`fixedSlots`・`fixedNotificationsPerDay` |
| `NotificationSettings` | `morning` / `noon` / `night` / `mode` / `weekendEnabled`（false = 週末オフ） |
| `DayCommitment` | `plannedAt?` / `outcome`。`.noCommitment` が宣言前 |
| `NotificationRegistration` | `identifier`（`<slot>-yyyyMMdd`）/ `fireDate` / `slot` / `copyKey` / `sessionType` |
| `NotificationPlan` | `registrations`（発火日時の昇順）/ `cancelledIdentifiers`。`make(now:settings:today:calendar:)` |
| `NotificationCopyKey` | morning / noonRemember / noonAvoiding / night / action / declarationReminder |
| `NotificationCopy` | `body(for:)`、`noonKey(for:calendar:)`（日替わり交互）、`restTodayActionTitle` = 「今日は休む」、`categoryIdentifier` |

先読み日数は `min(maxHorizonDays 30, pendingBudget 50 / 1 日あたりの固定本数)`。
2 回モード = 30 日（30 本）、3 回モード = 16 日（48 本）。行動時刻通知を足しても保留 50 本を超えない。

昼をスキップする規則（当日のみ・`cancelledIdentifiers` にも入る）:
(a) 固定の昼通知が `plannedAt` と 30 分以内、(b) 計画時点で `now < plannedAt`、
(c) `outcome` が `done` / `partial`（このとき `action-yyyyMMdd` も取り消す）。

### 未解決

- `Guardrails`（task_005）が別ブランチのため、禁止句リストを `NotificationCopyTests` に直接持っている。
  task_005 が入ったら `Guardrails` 側のリストへ寄せる（テストのコメントに明記済み）。
- App 側（`NotificationScheduler` / `AppDelegate` / `AppRouter` / 通知カテゴリ登録 / ディープリンク）は未実装。
  `NotificationCopy.restTodayActionIdentifier` と `categoryIdentifier` は App 側が使う前提の定数。
- `declarationReminder`（retention R1 の「30 秒だけ、声で約束して」）は文言だけ用意した。
  発火時刻は「一人になれる時刻」の設定（task_013）に依存するため、`NotificationPlan` は生成しない。

### 人間の確認待ち

- task_001 と同じ（iOS 26.x シミュレータランタイムの導入）。追加はなし。

---

## task_009-app — 通知のアプリ側（NotificationScheduler / DeepLink / AppDelegate）

- 日時: 2026-09-04
- 状態: wip（型検査は緑。実機での配信・タップ・pending 上限は未検証。`AppRouter` は未実装）
- ブランチ / コミット: `task/009-notification-app`（`task/009-notification-core` から分岐） / （このコミット）

### スコープ

task_009 のうち **App 側で UI を持たない部分だけ**。`SaydoCore` と `project.yml` は編集していない。

作ったもの:

| ファイル | 内容 |
|---|---|
| `App/Notifications/NotificationScheduler.swift` | `UNUserNotificationCenter` のラッパ。`NotificationPlan` の出力を非繰り返し `UNCalendarNotificationTrigger` で登録。`NotificationIdentifier`（管理接頭辞の判定）、`PendingDiagnostics`（保留通知の実測値）、`NotificationHealth`（許可状態 + 保留本数） |
| `App/Notifications/DeepLink.swift` | `userInfo` の組み立てと解析。`NotificationUserInfoKey`、`DeepLink`（`sessionType` / `slot` / `commitmentID` / `copyKey` / `action`）、`DeepLink.Action`（open / rest） |
| `App/AppDelegate.swift` | `UNUserNotificationCenterDelegate`。`SessionLauncher` プロトコルの定義と注入 |
| `App/SaydoApp.swift` | `@UIApplicationDelegateAdaptor(AppDelegate.self)` の 1 行追加のみ |
| `Tests/SaydoTests/DeepLinkTests.swift` | `DeepLink` の解析と識別子判定のテスト 18 件 |

やっていないもの（このタスクの範囲外）: `AppRouter`、設定 UI（task_013）、Today 画面の再許可導線の表示（task_012）、
休みの記録（`SessionLog`。task_006）、`Commitment` との接続（task_005 / task_008）。

### 実装の決定

- **再計画の手順**: `apply(_:commitmentID:)` は毎回 `morning-*` / `noon-*` / `night-*` / `action-*` の
  保留通知を **全部消してから** 登録し直す。`NotificationPlan.cancelledIdentifiers` は念のため明示的にも消す。
- **非同期 API はすべて完了ハンドラ版を `withCheckedContinuation` で包む**。`UNNotificationSettings` と
  `UNNotificationRequest` をアクター境界に渡さず、`String` / `Int` / `Date` だけを取り出すため
  （`async` 版を直接 await すると Swift 6 strict concurrency で Sendable の問題を踏む可能性がある）。
- **`didReceive` は `nonisolated`** にし、その場で `UNNotificationResponse` → `DeepLink`（Sendable な値型）へ
  落としてから `Task { @MainActor }` で渡す。`@unchecked Sendable` も `nonisolated(unsafe)` も使っていない。
- **フォアグラウンドは `[.banner]` だけ**。`.sound` は TTS と重なるため、`.list` は後からタップされて
  会話が二重に始まるため付けない（check_022）。
- **コールドスタート対策**: `SessionLauncher` が注入される前に `didReceive` が来た場合は
  `pendingLink` に 1 件だけ持ち、`setLauncher(_:)` で流す。
- **バッジは要求しない**（`requestAuthorization(options: [.alert, .sound])`）。未処理の数を見せるのは
  企画原則 §22-8「タスク管理アプリにしない」に反するため。
- **文言は 1 つも App 側に置いていない**。すべて `SaydoCore.NotificationCopy` から引く（`lint-principles.sh` の
  日本語リテラル WARN に `App/` の行が 1 件も出ないことで確認済み）。

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `swiftc -typecheck`（App 4 ファイル。iOS シミュレータ SDK 26.2 / `arm64-apple-ios26.0-simulator`） | **0** | `docs/logs/task_009-app-1.txt` |
| `swiftc -typecheck`（`Tests/SaydoTests` 2 ファイル） | **0** | `docs/logs/task_009-app-1.txt` |
| `scripts/test-core.sh` | **0**（47 tests, 0 failures / `lint-principles: OK`） | `docs/logs/task_009-app-2.txt` |
| `scripts/build-ios.sh` | **70**（task_001 と同じ destination の問題。この差分とは無関係） | `docs/logs/task_009-app-3.txt` |
| `xcodebuild -target Saydo -sdk iphonesimulator`（`xcodegen generate` を一時実行。後で revert） | **65** | `docs/logs/task_009-app-4.txt` |

`scripts/build-ios.sh` が通らないため、代替として **iOS シミュレータ SDK に対する型検査**で確認した。
`project.yml` の `SWIFT_VERSION: 6.0` / `SWIFT_STRICT_CONCURRENCY: complete` /
`SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY: YES` に対応するフラグを付けている。

```
--- [2] App 側の型検査（本タスクの成果物） ---
+ swiftc -typecheck -swift-version 6 -strict-concurrency=complete -enable-upcoming-feature ExistentialAny -sdk .../iPhoneSimulator26.2.sdk -target arm64-apple-ios26.0-simulator -I .typecheck App/SaydoApp.swift App/AppDelegate.swift App/Notifications/DeepLink.swift App/Notifications/NotificationScheduler.swift
+ echo EXIT=0
EXIT=0
+ set +x

--- [3] Saydo モジュール（-enable-testing）→ Tests/SaydoTests の型検査 ---
+ swiftc -emit-module -enable-testing -module-name Saydo -emit-module-path .typecheck/Saydo.swiftmodule -swift-version 6 -strict-concurrency=complete -enable-upcoming-feature ExistentialAny -sdk .../iPhoneSimulator26.2.sdk -target arm64-apple-ios26.0-simulator -I .typecheck App/SaydoApp.swift App/AppDelegate.swift App/Notifications/DeepLink.swift App/Notifications/NotificationScheduler.swift
+ echo EXIT=0
EXIT=0
+ swiftc -typecheck -swift-version 6 -strict-concurrency=complete -enable-upcoming-feature ExistentialAny -sdk .../iPhoneSimulator26.2.sdk -target arm64-apple-ios26.0-simulator -I .typecheck -F .../Developer/Library/Frameworks -I .../Developer/usr/lib Tests/SaydoTests/DeepLinkTests.swift Tests/SaydoTests/SmokeTests.swift
+ echo EXIT=0
EXIT=0
+ set +x
```

警告は 1 件も出ていない（`-strict-concurrency=complete` と `ExistentialAny` を有効にした状態で出力なし）。

### 未検証（実機・シミュレータが必要）

- **リンクと実行**。型検査だけで、`Saydo.app` を作って動かしてはいない。
- 通知が実際に届くこと、タップで `didReceive` が呼ばれること、通知タップから TTS までの 1.5 秒（check_016）。
- 通知の長押しから「今日は休む」が出ること（check_035）と、当日の残りが消えること。
- **保留通知の上限**。`NotificationScheduler.logPendingDiagnostics()` を用意したが実機で回していない。
  実機で `subsystem:com.nonturn.saydo category:notifications` を Console.app で絞ると
  `pending managed=N total=N repeating=0 morning=N noon=N night=N action=N first=... last=...` が 1 行出る。
  この N を次のセッションで PROGRESS に記録する（task_009 の done_definition）。
- `Tests/SaydoTests` は iOS 26.x シミュレータランタイムが無いため実行できていない（型検査のみ）。

### 未解決

- **`Time Sensitive` エンタイトルメントは未追加**。指示どおり `project.yml` を編集していないため、
  `com.apple.developer.usernotifications.time-sensitive` は入っていない。コード側は
  `content.interruptionLevel = .timeSensitive`（`slot == .action` のときだけ）を指定しているだけ。
  **エンタイトルメント未設定の状態では、この指定による集中モードの突破は得られず、通常の通知として届く**
  という理解で実装している（Apple のドキュメントに基づく理解であり、実機では未確認）。
  エンタイトルメントの追加は `project.yml` を触るタスク（task_013 か専用の小タスク）で行う。
- **`Saydo.xcodeproj` を再生成していない**。指示どおり `.xcodeproj` はコミットしていないので、
  `App/AppDelegate.swift` と `App/Notifications/*.swift` と `Tests/SaydoTests/DeepLinkTests.swift` は
  まだプロジェクトのファイル一覧に入っていない。**main に取り込んだあと `xcodegen generate` が必要**。
  これをやるまで `scripts/build-ios.sh` / `scripts/test-ios.sh` は新規ファイルを見ない。
- **通知アクション「今は話せない」は未実装**。実装計画 §7.4 と task-list.json の scope にはあるが、
  `SaydoCore.NotificationCopy` に文言・識別子が無く、SaydoCore を編集しない制約のため入れられなかった。
  60 分後の 1 件再登録（同日 2 回まで）も未実装。SaydoCore 側に
  `cannotTalkNowActionIdentifier` / `cannotTalkNowActionTitle` を足す後続タスクが要る。
- **`AppRouter` が無い**。`AppDelegate.setLauncher(_:)` を呼ぶ側がまだ存在しないため、
  現状は通知をタップしても `pendingLink` に溜まるだけで何も起きない。
  `AppRouter` は `SessionLauncher` に準拠して `setLauncher` に渡す。
- **休みの記録が繋がっていない**。`DeepLink.Action.rest` を受けると当日の残りの保留通知は消えるが、
  `SessionLog` への「休み」の記録は `SessionLauncher` の実装側（task_006 / task_012）の担当。
- `NotificationHealth.needsAttention` を Today 画面に出す配線は未実装（task_012）。

### 人間の確認待ち

- task_001 と同じ（iOS 26.x シミュレータランタイムの導入）。これが入るまで
  `scripts/build-ios.sh` / `scripts/test-ios.sh` は通らず、リンク・実行・テストの実行は行えない。
- 実機での通知配信・「今日は休む」・保留通知の上限の確認。
