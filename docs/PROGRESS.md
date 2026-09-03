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

## task_005 — 会話状態機械（Morning / Noon / Night）と文言・ガードレール

- 日時: 2026-09-04
- 状態: done
- ブランチ: `task/005-flows`

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/test-core.sh` | **0** | `docs/logs/task_005-1.txt` |

テスト件数: 101（DomainTests 15 / DialogueCopyTests 15 / GuardrailsTests 13 / MorningFlowTests 23 / NightFlowTests 12 / NoonFlowTests 23）。

`scripts/test-core.sh`（末尾 30 行）:

```
    Packages/SaydoCore/Sources/SaydoCore/Domain/FlowStep.swift:64: "もっと小さく"
    Packages/SaydoCore/Sources/SaydoCore/Domain/FlowStep.swift:65: "今日の前進"
    Packages/SaydoCore/Sources/SaydoCore/Domain/FlowStep.swift:66: "明日のこと"
    Packages/SaydoCore/Sources/SaydoCore/Domain/FlowStep.swift:67: "終わり"
    Packages/SaydoCore/Sources/SaydoCore/Domain/ReasonCategory.swift:22: "気まずい"
    Packages/SaydoCore/Sources/SaydoCore/Domain/ReasonCategory.swift:23: "完璧にやりたい"
    Packages/SaydoCore/Sources/SaydoCore/Domain/ReasonCategory.swift:24: "面倒"
    Packages/SaydoCore/Sources/SaydoCore/Domain/ReasonCategory.swift:25: "不安・怖い"
    Packages/SaydoCore/Sources/SaydoCore/Domain/ReasonCategory.swift:26: "量が多い"
    Packages/SaydoCore/Sources/SaydoCore/Domain/ReasonCategory.swift:27: "何から始めるかわからない"
    Packages/SaydoCore/Sources/SaydoCore/Domain/ReasonCategory.swift:28: "期限が怖い"
    Packages/SaydoCore/Sources/SaydoCore/Domain/SessionType.swift:15: "朝"
    Packages/SaydoCore/Sources/SaydoCore/Domain/SessionType.swift:16: "昼"
    Packages/SaydoCore/Sources/SaydoCore/Domain/SessionType.swift:17: "夜"
    Packages/SaydoCore/Sources/SaydoCore/Domain/SessionType.swift:18: "手動"
    Packages/SaydoCore/Sources/SaydoCore/Domain/TaskDomain.swift:20: "人への返信"
    Packages/SaydoCore/Sources/SaydoCore/Domain/TaskDomain.swift:21: "お金"
    Packages/SaydoCore/Sources/SaydoCore/Domain/TaskDomain.swift:22: "大きなタスク"
    Packages/SaydoCore/Sources/SaydoCore/Domain/TaskDomain.swift:23: "営業"
    Packages/SaydoCore/Sources/SaydoCore/Domain/TaskDomain.swift:24: "書類"
    Packages/SaydoCore/Sources/SaydoCore/Domain/TaskDomain.swift:25: "健康"
    Packages/SaydoCore/Sources/SaydoCore/Domain/TaskDomain.swift:26: "その他"
    Packages/SaydoCore/Sources/SaydoCore/Flows/MorningFlow.swift:131: "特にない"
    Packages/SaydoCore/Sources/SaydoCore/Flows/NightFlow.swift:56: "ない"
    Packages/SaydoCore/Sources/SaydoCore/Flows/NightFlow.swift:57: "何もできなかった"
    Packages/SaydoCore/Sources/SaydoCore/Flows/NoonFlow.swift:183: "少し"
    Packages/SaydoCore/Sources/SaydoCore/Flows/NoonFlow.swift:184: "まだ"
    Packages/SaydoCore/Sources/SaydoCore/Flows/NoonFlow.swift:186: "やった"
    Packages/SaydoCore/Sources/SaydoCore/Flows/NoonFlow.swift:187: "終わった"
lint-principles: OK
```

### done_definition の自己監査

| 項目 | 結果 | 証拠 |
|---|---|---|
| `scripts/test-core.sh` が緑で、3 フローの全分岐にテストがある | 満たす | 上表。MorningFlowTests 23 / NoonFlowTests 23 / NightFlowTests 12 |
| DialogueCopy の全文言が Guardrails を通過するテストがある | 満たす | `GuardrailsTests.testEveryDialogueCopyLinePassesGuardrails` / `testEveryChoiceLabelPassesGuardrails` |
| 主要 8 文言に 5 種以上のバリエーションがあり、3 日以内に同じ文言が繰り返されない | 満たす | `DialogueCopyTests.testEightPrimaryLinesHaveFiveOrMoreVariants` / `testSameLineIsNotRepeatedWithinThreeDays` |
| interrupted で中断した後、同じ FlowStep から再開できる | 満たす | `MorningFlowTests.testInterruptedKeepsTheStepAndResumesFromIt` ほか昼・夜に各 1 件 |
| copy-audit.js の実行結果が指摘 0 件 | **未実施（実行不能）** | 下記「人間の確認待ち」 |

テストが実際に効くことは変異テストで確認した（`Guardrails.bannedPhrases` から「サボ」を外す / N1 の partial を N2 に進める → 該当テストが 4 件失敗。その後復元して 101 件緑）。

### 未解決

- `NotificationCopy` は task_009 の担当。task_005 では `NotificationRequest`（kind と時刻表現）までを定義し、通知文言は持たない。done_definition の「NotificationCopy 相当の全文言」は task_009 で改めて検査する。
- `FlowMachine` は時計を持たない。M3 の答えは `plannedAnswer` に本人の言葉のまま入り、`Date` への解決は `JapaneseTimeParser`（task_005b）と `NotificationPlan`（task_009）が行う。
- M1 を声で答えた場合、`FlowState.reason` は nil のまま次へ進む（分類に失敗しても会話を止めない）。`DialogueEngine` の分類結果はアプリ側が `FlowEvent.choice(.reason(_))` として戻す設計。
- `lint-principles.sh` は Flows 配下の**認識用キーワード辞書**（「特にない」「まだ」など）を日本語リテラルとして警告する。画面に出す文言ではないため `DialogueCopy` に移していない。exit code には影響しない。

### 人間の確認待ち

- `node .claude/workflows/copy-audit.js` は実行できない。`.claude/workflows/*.js` は Claude Code の Workflow スクリプト（`agent()` / `parallel()` / `phase()` とトップレベル `return` を使う）で、素の node では `SyntaxError: Illegal return statement` になる。代替として copy-audit の RULES のうち機械検査できる項目（禁止語・質問は 60 字以内で「？」終わり・行動文は 40 字以内・TODO アプリ語彙）を全 79 文言 + 27 チップに対して実行し、指摘 1 件（「受け取りました。あとで、…」の "あと"）を「時間になったら」に直して 0 件にした。トーン（上司口調など）の主観判定は未実施。

---

## task_014 — SaydoAI: Foundation Models による DialogueEngine 実装

- 日時: 2026-09-04
- 状態: done（`scripts/build-ios.sh` のみ環境要因で未達。task_001 と同じ）
- ブランチ: `task/014-saydo-ai`（`task/005-flows` から分岐）

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `swift build --package-path Packages/SaydoAI` | **0** | `docs/logs/task_014-1.txt` |
| `swift test --package-path Packages/SaydoAI` | **0**（33 tests / 0 failures） | `docs/logs/task_014-2.txt` |
| `scripts/test-core.sh` | **0**（SaydoCore 101 + SaydoAI 33 + lint OK） | `docs/logs/task_014-3.txt` |
| `scripts/build-ios.sh` | **70**（iOS 26.2 シミュレータ未導入。task_001 から未解消） | `docs/logs/task_014-4.txt` |
| `xcodegen generate --spec project.yml --project <一時ディレクトリ>` | **0**（`SaydoAI` が pbxproj に 10 箇所） | — |

`swift test --package-path Packages/SaydoAI`（末尾 20 行）:

```
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsBlamingSentence]' started.
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsBlamingSentence]' passed (0.000 seconds).
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsEmpty]' started.
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsEmpty]' passed (0.000 seconds).
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsLinkAndEnglishOnly]' started.
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsLinkAndEnglishOnly]' passed (0.000 seconds).
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsNumbers]' started.
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsNumbers]' passed (0.000 seconds).
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsTooLongSentence]' started.
Test Case '-[SaydoAITests.ReflectionRuleTests testRejectsTooLongSentence]' passed (0.001 seconds).
Test Suite 'ReflectionRuleTests' passed at 2026-09-04 06:29:06.480.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'SaydoAIPackageTests.xctest' passed at 2026-09-04 06:29:06.480.
	 Executed 33 tests, with 0 failures (0 unexpected) in 18.712 (18.715) seconds
Test Suite 'All tests' passed at 2026-09-04 06:29:06.480.
	 Executed 33 tests, with 0 failures (0 unexpected) in 18.712 (18.716) seconds
```

`scripts/build-ios.sh`（末尾。**失敗は project.yml の変更とは無関係**。destination 解決の時点で落ちており、コンパイルまで到達していない）:

```
xcodebuild: error: Unable to find a destination matching the provided destination specifier:
		{ generic:1, platform:iOS Simulator }

	Ineligible destinations for the "Saydo" scheme:
		{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device,
		  error:iOS 26.2 is not installed. Please download and install the platform from Xcode > Settings > Components. }
```

### 本機（macOS 26.5 / Apple M4 / Xcode 26.2）での実測

- `SystemLanguageModel.default.availability` = `available`、`supportsLocale(Locale(identifier: "ja_JP"))` = `true`。
  結合テストは **スキップされず実際に走った**。
- **`GenerationOptions(maximumResponseTokens: 200)` が無いと 6 秒予算が成立しない。**
  上限なしで 24 呼び出しを流したところ、`followUpQuestion` / `classifyReason` / `weeklyReflection` で
  生成が暴走し `exceededContextWindowSize`（"Content contains 4089 tokens ... maximum 4096"）まで
  **53〜56 秒**走る呼び出しが 6 件出た。上限 200 では 30 呼び出し中 **6 秒超過 0 件**（最長 3.95 秒）で、
  暴走は `decodingFailure` として 3 秒前後で返り `default` 経路でテンプレートに落ちる。
- **`withThrowingTaskGroup` でタイムアウトを組むと上限が効かない。**
  時間切れで抜けるときグループが子タスクの終了を待つため、キャンセルに応じない生成では意味を失う。
  最初の実装で `classifyDomain` が 6 秒指定にもかかわらず **44 秒** 返らずテストが落ちた。
  現在は「先に届いた結果だけを通し、放棄した生成の完了を待たない」実装に差し替えている。
- 出力品質: `weeklyReflection` が `... 逃げちゃうんだ。」}``` ```js -import` のように JSON/コードの断片を漏らす例、
  `followUpQuestion` が YouTube の URL を含む例を観測した。いずれも Guardrails / ReflectionRule で弾かれる。

### done_definition の自己監査

| 項目 | 結果 | 証拠 |
|---|---|---|
| `project.yml` に `packages.SaydoAI` がある | 満たす | `project.yml`。`Saydo` ターゲットの dependencies にも登録済み |
| `scripts/build-ios.sh` が exit 0 | **満たさない（環境要因）** | 上表。iOS 26.2 シミュレータランタイム未導入。人間の作業待ち |
| Apple Intelligence 有効な Mac で結合テストが緑、無効環境ではスキップ | 満たす | 本機は available。`FoundationModelsDialogueEngineIntegrationTests` 2 件が実走して緑。無効時は `XCTSkipUnless` |
| 全メソッドにタイムアウトと Guardrails 置換がある | 満たす | 6 メソッドすべてが `generate`（6 秒上限）を通り、`classifyDomain` 以外は Guardrails / ReflectionRule を通す。`classifyDomain` は列挙のみで検査対象の文が無い |
| `guardrailViolation` / `refusal` / `exceededContextWindowSize` / `unsupportedLanguageOrLocale` の扱いが実装とテストで固定 | 満たす | `FoundationModelsDialogueEngine.policy(for:)` と `testGenerationErrorPolicy` / `testGuardrailViolationFallsBackWithoutRetry` / `testRefusalFallsBackWithoutRetry` / `testExceededContextWindowSizeRetriesOnce` / `testUnsupportedLanguageOrLocaleLocksToTemplate`。実際の `GenerationError` 値を作って踏んでいる |
| `@Guide` に文字数制約を使っていない | 満たす | `GenerableTypes.swift` の `@Guide` は description と `.range(1...5)` / `.count(3)` のみ |
| 指示文が 600 文字以内であることをテストで固定 | 満たす | `testInstructionLengthsAreFixed`（234 / 353 / 305 / 285 / 186 / 241 文字を等値で固定）と `testEveryInstructionIsWithinBudget` |

### 未解決

- **`exceededContextWindowSize` の再試行は 6 秒運用では実質踏まれない。** 4,096 トークンに達するまで 50 秒以上かかるため、
  必ずタイムアウトが先に成立する。分岐は仕様どおり実装し、`handle` を直接呼ぶテストで固定してあるが、
  実運用の経路としては死に枝であることを task_015 の計測時に踏まえること。
- **放棄した生成がモデルを占有する。** 6 秒で打ち切っても生成自体は走り続けるため、
  直後の呼び出しがその裏で待たされてタイムアウトし、連鎖してテンプレートに落ちることがある。
  結合テスト 10 呼び出しで所要 15〜47 秒とばらついたのはこれが原因。
  会話を止めないことを優先した設計上の割り切りで、緩和策（`prewarm` / 呼び出し間隔）は task_015 の判断に委ねる。
- **プロセス内の初回呼び出しが遅い。** 上限なしの計測では初回だけ 30 秒級だった。
  `LanguageModelSession.prewarm(promptPrefix:)` が SDK に実在することは確認済み。使うかどうかは task_015 で決める。
- `TemplateDialogueEngine`（task_005b）がまだ無い。エンジンは `fallback: any DialogueEngine` を注入で受け、
  テストでは `TemplateStub` を使っている。task_005b 完了後に実体を差し込むのは task_015 の配線作業。
- `Guardrails.Form.statement` は「80 文字以内」「数字を含まない」を課さない（§7.5 の振り返り固有の規則）。
  SaydoCore は本タスクで変更しない方針のため、`SaydoAI.ReflectionRule` として上乗せしている。
  SaydoCore 側に寄せるかどうかは task_016（週次分析）で再検討する。
- `SaydoAI.PromptBuilder` は `FoundationModels.PromptBuilder`（result builder）と名前が衝突する。
  両方を import するファイルでは `SaydoAI.PromptBuilder` と修飾する必要がある（テストで実際に踏んだ）。
- `lint-principles.sh` が SaydoAI の日本語リテラルを 14 件警告する。プロンプトと `@Guide` の description で、
  利用者に見せる文言ではないため `DialogueCopy` に移していない。exit code には影響しない。
- `Saydo.xcodeproj` は再生成していない（worktree では再生成しない方針。実装計画 §12-6）。
  `project.yml` の妥当性は一時ディレクトリへの `xcodegen generate` で確認した。**main での再生成が必要**。

### 人間の確認待ち

- iOS 26.2 シミュレータランタイムの導入（空き容量 9 GB 以上を確保して `xcodebuild -downloadPlatform iOS`）。
  これが済むまで `scripts/build-ios.sh` は SaydoAI と無関係に落ち続ける。
- main で `xcodegen generate` を実行して `Saydo.xcodeproj` に SaydoAI を反映すること。
- 実機（Apple Intelligence 対応 iPhone）での Tier A 検証は未実施。本タスクの検証はすべて macOS 上。
