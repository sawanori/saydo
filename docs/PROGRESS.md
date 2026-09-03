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

## task_005b — テンプレート対話エンジン（Tier B）・一般形 ShrinkLadder・日本語時刻パース

- 日時: 2026-09-04
- 状態: done
- ブランチ: `task/005-flows`

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/test-core.sh` | **0** | `docs/logs/task_005b-1.txt` |

テスト件数: 143（task_005 の 101 + JapaneseTimeParserTests 16 / ShrinkLadderTests 9 / TemplateDialogueEngineTests 17）。

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
| `scripts/test-core.sh` が緑 | 満たす | exit 0 / 143 tests |
| TemplateDialogueEngine が DialogueEngine の全メソッドを LLM なしで実装 | 満たす | `TemplateDialogueEngineTests.testEngineConformsToDialogueEngineWithoutAnyModel`（6 メソッドすべてを `any DialogueEngine` 越しに呼ぶ） |
| ShrinkLadder が一般形で分野に依存しない | 満たす | `ShrinkLadderTests.testLadderIsTheGeneralFourStepForm` / `testLadderDoesNotDependOnAnyDomain` / `testShrinkingWorksTheSameForAnyStartingAction` |
| 行動文が本人の言葉から作られ、名詞切り出しをしていない | 満たす | `testNounUtterancesBecomeVerbEndingActionsWithoutNounExtraction`（『クライアントへの返信』『確定申告』『見積書』が丸ごと残り、40 字以内・動詞終わり）/ `testProposedActionsAreTheGeneralExamplesNotDerivedFromTheAvoidance` |
| JapaneseTimeParser の 10 パターン | 満たす | `JapaneseTimeParserTests.test01`〜`test10`（14時 / 2時 / 午前・午後 / 14時30分 / 2時半 / 1時間後 / 30分後・2時間半後 / 昼過ぎ / 夕方・午前中・午後・夜 / 全角数字） |

テストが実際に効くことは変異テストで確認した（ShrinkLadder の 1 段をメール専用に置換 / `microAction(fromUtterance:)` を末尾 3 文字の切り出しに置換 → 該当テストが 7 件失敗。復元して 143 件緑）。

### 未解決

- 理由のキーワード辞書は「原因がはっきりしている分類を先に、感情だけの分類を後に」の順で照合する（「期限が近くて怖い」は `anxious` ではなく `deadlineFear`）。この優先順位はテストで固定しているが、実発話での妥当性はドッグフーディング（task_013b）で確かめる。
- 分類できない答えは値を作らずに `TemplateDialogueEngine.Failure.reasonNotRecognized` を投げる。呼び出し側はこれを受けても会話を止めない（`FlowMachine` は理由が nil のまま次へ進む）。
- `JapaneseTimeParser` は漢数字（「二時」）を読まない。ASCII と全角の数字のみ。
- 「2時」のように午前・午後が分からない場合は今日これから来る方を選び、今日に来ないなら翌日の同じ時刻にする。22 時に「2時」と言うと翌日 2 時になる（14 時ではない）。この解釈はテストで固定した。
- 振り返り文のテンプレートは `TemplateDialogueEngine.swift` に置いた（task_005b の `files_to_modify` が空で、`DialogueCopy.swift` を触れないため）。`lint-principles.sh` はこれを日本語リテラルとして警告するが exit code には影響しない。task_016 で Insight 側に文言を集めるときに整理する余地がある。

### 人間の確認待ち

- なし。

---

## task_006 — SwiftData スキーマ V1・AudioFileStore・Repository・AppSettings

- 日時: 2026-09-04
- 状態: wip（iOS ビルド・テストが環境要因で走らないため done にしない）
- ブランチ: `task/006-data`（`task/001-bootstrap` から分岐）

### 作ったもの

| ファイル | 中身 |
|---|---|
| `App/Data/Schema.swift` | `SaydoSchemaV1: VersionedSchema`（1.0.0）、`SaydoMigrationPlan`、`SaydoModelContainer.make(inMemory:)`、`DayKey`（`yyyy-MM-dd` / 通知識別子用 `yyyyMMdd`） |
| `App/Data/Models/AvoidanceItem.swift` | id, title, domain, status(open/carriedOver/dropped/done), createdAt, lastTouchedAt, → 多 `Commitment` |
| `App/Data/Models/Commitment.swift` | `#Index([\.dayKey])`。§10 の列 + `reason`（optional）+ `isVoiceless` |
| `App/Data/Models/VoiceEntry.swift` | `#Index([\.recordedAt])`。kind 7 種（fix-decisions P2.1 の reason / status を含む） |
| `App/Data/Models/SessionLog.swift` | sessionType, startedAt, endedAt, completed, tier(A/B), lastStep, guardrailReplacedCount |
| `App/Data/Models/Carryover.swift` | forDayKey, text, sourceEntryID, createdAt |
| `App/Data/AudioFileStore.swift` | `Application Support/Saydo/Audio/yyyy/MM/<uuid>.m4a`、`completeUntilFirstUserAuthentication`、削除、孤児掃除、置き場所の外を指すパスの拒否 |
| `App/Data/Repository.swift` | `@ModelActor`。todayCommitment / createCommitment / updateOutcome / shrink / entries(for:) / carryover(for:) / saveCarryover / appendVoiceEntry / deleteVoiceEntry / sweepOrphanAudioFiles / weeklyStats / lastEntryDate |
| `App/Data/AppSettings.swift` | `UserDefaults`。8:00 / 13:00 / 21:00、無音 1.5 秒、TTS 音声 ID、通知モード（既定 2 回）、週末通知、一人で話せる時間、オンボーディング完了 |
| `Tests/SaydoTests/{RepositoryTests,AudioFileStoreTests,AppSettingsTests}.swift` | インメモリ `ModelContainer` と一時ディレクトリの `AudioFileStore` で 32 件 |

### 設計上の判断（レビュー対象）

1. **`@Model` を外へ出さない**。`@Model` のクラスは Sendable ではないので、`Repository` の返り値は
   `CommitmentSnapshot` / `VoiceEntrySnapshot` / `CarryoverSnapshot`（すべて `Sendable` の値型）にした。
   これで Swift 6 の strict concurrency を、検査を外す属性なしで通している。
2. **`AppSettings` は `@MainActor`**。`UserDefaults` は iOS 26.2 SDK で明示的に非 Sendable
   （`@_nonSendable(_assumed)`）。検査を外す属性で黙らせず隔離で解決した。設定を読むのは UI と通知登録で、どちらも main。
3. **列挙は rawValue（String）で保存**する。`#Predicate` と `SortDescriptor` が String なら確実に動くため。
   未知の rawValue は既定値に寄せて読めるようにしてある。
4. **`audioPath` は相対パス**（`yyyy/MM/<uuid>.m4a`）。絶対パスを保存すると、再インストールや復元で
   アプリコンテナの UUID が変わったときに必ず外れる。解決は `AudioFileStore.url(forRelativePath:)`。
5. **V1 のモデルは名前空間に入れずトップレベル**。V2 を足すときに `extension SaydoSchemaV1` へ移して
   `typealias` で現行版を指す。V1 だけの今、名前空間を先に入れる利得が無いと判断した。
6. **`AvoidanceItem` の削除規則は `.nullify`**（`.cascade` ではない）。声の記録は対象を消しても残す（企画原則 §22-9）。
   「捨てた」は `status = .dropped` であって削除ではない。
7. **`updateOutcome` は `AvoidanceItem.status` を変えない**。5 分の行動が 1 回できたことと、
   逃げている対象が終わったことは別。状態遷移は夜フロー（task_011）の担当。
8. **`AppSettingsTests.swift` は task-list.json の files_to_create に無いが追加した**。
   fix-decisions P1.4 が AppSettings を task_006 の成果物にしており、既定値の表を検証なしで残すのは危ないと判断した。
9. **`weekendNotificationsEnabled` の既定は `true`**。retention-strategy.md R2 の「週末は既定でオフにできる」は
   設定の存在を指すと読み、黙って通知を止める側には倒さなかった。**この既定値は要レビュー**。
10. **`aloneTime`（一人で話せる時間）の既定は nil**。R1 に既定値の指定が無いので数字を作らず、
    未設定の間は夜の時刻を使う（`effectiveAloneTime`）。

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/lint-principles.sh` | 0 | `docs/logs/task_006-lint.txt` |
| `scripts/test-core.sh` | 0 | `docs/logs/task_006-testcore.txt` |
| `scripts/build-ios.sh` | **70** | `docs/logs/task_006-buildios.txt` |
| `scripts/test-ios.sh` | **2** | `docs/logs/task_006-testios.txt` |
| swiftc typecheck（iOS 26 シミュレータ SDK・Swift 6・strict concurrency complete） | 0 | `docs/logs/task_006-typecheck.txt` |
| macOS で Tests/SaydoTests を実行（代替検証） | 0 | `docs/logs/task_006-macos-tests.txt` |

`scripts/build-ios.sh`（末尾）:

```
xcodebuild: error: Unable to find a destination matching the provided destination specifier:
		{ generic:1, platform:iOS Simulator }

	Ineligible destinations for the "Saydo" scheme:
		{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device, error:iOS 26.2 is not installed. Please download and install the platform from Xcode > Settings > Components. }
EXIT=70
```

この 70 は **task_006 の変更前から出る**（`git stash` 相当の素の `task/001-bootstrap` でも同じ）。
`-sdk iphoneos` の実機ビルドも同じ理由で 70。原因は iOS 26.2 プラットフォームが未導入であること 1 点。

`scripts/test-ios.sh`（全文）:

```
test-ios: iOS 26.x の利用可能なシミュレータが見つからない。
  導入コマンド: xcodebuild -downloadPlatform iOS（約 8.4 GB の空きが必要）
  現在のランタイム一覧:
== Runtimes ==
iOS 18.5 (18.5 - 22F77) - com.apple.CoreSimulator.SimRuntime.iOS-18-5
EXIT=2
```

`swiftc typecheck`（全文。iOS 26 シミュレータ SDK に対する型検査。マクロ展開込み）:

```
=== 1) SaydoCore module (iOS 26 simulator, Swift 6, strict concurrency) ===
CORE_EXIT=0
=== 2) App sources -> Saydo module (testability on) ===
APP_EXIT=0
=== 3) Tests/SaydoTests typecheck (iOS 26 simulator) ===
TESTS_EXIT=0
```

警告 0 件（`grep -c "warning:"` = 0）。`@Model` / `#Index` / `@ModelActor` のマクロは展開されている。

macOS でのテスト実行（末尾）:

```
Test Suite 'RepositoryTests' passed at 2026-09-04 06:04:44.668.
	 Executed 17 tests, with 0 failures (0 unexpected) in 0.088 (0.089) seconds
Test Suite 'SaydoHarnessPackageTests.xctest' passed at 2026-09-04 06:04:44.668.
	 Executed 32 tests, with 0 failures (0 unexpected) in 0.104 (0.107) seconds
Test Suite 'All tests' passed at 2026-09-04 06:04:44.668.
	 Executed 32 tests, with 0 failures (0 unexpected) in 0.104 (0.108) seconds
HARNESS_TEST_EXIT=0
```

代替検証の作り方（**リポジトリには入れない**。`docs/logs/task_006-macos-harness-Package.swift.txt` に控え）:
scratchpad に SwiftPM パッケージを 1 つ作り、`Sources/Saydo` → `App/Data`、
`Sources/SaydoCore` → `Packages/SaydoCore/Sources/SaydoCore`、
`Tests/SaydoTests/*.swift` → 本タスクの 3 ファイルを **symlink** して `swift test` を macOS 26 で走らせた。
モジュール名を `Saydo` にしてあるので、テストの `@testable import Saydo` は Xcode の SaydoTests ターゲットと同じまま動く。
`AudioFileStore` のファイル保護属性だけは `#if os(iOS)` で囲ってあるため、この経路では**実行されていない**（下記「未検証」）。

### done_definition との対応

| done_definition | 判定 | 証拠 |
|---|---|---|
| `scripts/test-ios.sh` が緑 | **未達（環境要因）** | exit 2。iOS 26.x シミュレータ未導入。代わりに macOS で同じテストが 32/32 通ることと、iOS SDK に対する型検査 0 警告を示した |
| 同じ dayKey で 2 件目の Commitment を作ると拒否されるテストがある | 済 | `RepositoryTests.testSecondCommitmentOnTheSameDayIsRejected`（macOS で pass） |
| VoiceEntry 削除で音声ファイルが消えるテストがある | 済 | `RepositoryTests.testDeletingAVoiceEntryDeletesItsAudioFile`（macOS で pass） |

### 未検証

- **iOS 実機・シミュレータでの実行は 1 行も行っていない**。`xcodebuild` が iOS プラットフォーム未導入で起動しない。
  型検査（マクロ展開込み）と macOS 実行までが本タスクで取れた証拠のすべて。
- **ファイル保護属性 `completeUntilFirstUserAuthentication` が実際に付くかは未検証**。
  コードは iOS 用に型検査が通っているが、`#if os(iOS)` のため macOS 実行では通っていない。
  iOS が入ったら `AudioFileStore` の書き込み後に `URLResourceValues` か `getattrlist` で属性を確認すること。
- **SwiftData の実ストア（ディスク）での挙動は未検証**。テストは `isStoredInMemoryOnly: true`。
  `#Index` が実際に張られるか、V1 スキーマがディスクに書けるかは iOS 導入後に確認が要る。

### 未解決

- **`Saydo.xcodeproj` を更新していない**（fix-decisions H1.4「worktree では再生成しない」に従った）。
  本タスクが足した `App/Data/` の 8 ファイルと `Tests/SaydoTests/` の 3 ファイルは、
  **main で `xcodegen generate` を実行するまで Xcode プロジェクトに入らない**。
  worktree では `xcodegen generate` が exit 0 で通り、11 ファイルが取り込まれることは確認済み（生成物は破棄した）。
- `project.yml` は変更していない。`packages` への `SaydoCore` 登録は task_002 が済ませている。
- `AppSettings` を読むのは main のみ。task_009 の通知登録が main 以外から設定を読みたくなった場合は、
  値を `TimeOfDay` などの `Sendable` な値にして渡すこと（`AppSettings` 自体を渡さない）。
- 孤児掃除は `SaydoApp.init` から起動時に 1 回だけ走らせている。会話中に呼ぶと録音途中のファイルを消す。
- `DayKey` は端末のカレンダーの「日」で区切る。深夜 1 時の夜フローが前日ではなく当日に付く点は
  夜フロー（task_011）で扱い方を決めること。

### 人間の確認待ち

- task_001 と同じ。**iOS 26.x プラットフォーム（シミュレータランタイム）の導入**が、この 3 タスクで唯一
  ふさがっていない穴。空き容量 6.0 GB / 必要 8.39 GB。`xcodebuild -downloadPlatform iOS` を実行できる状態にする。
  導入後に `scripts/build-ios.sh` と `scripts/test-ios.sh` を実行し、この節と上の「未検証」を更新すること。

---

## task_004 — スパイク S-B / S-C: SpeechSpike（SpeechAnalyzer + 録音 + 無音停止 + TTS 半二重）

- 日時: 2026-09-04
- 状態: needs-device（コンパイルは通った。**実機での計測は 1 件も行っていない**）
- ブランチ: `task/004-speech-spike`

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/build-ios.sh SpeechSpike` | **0** | `docs/logs/task_004-1.txt` |
| `scripts/lint-principles.sh` | **0** | `docs/logs/task_004-2.txt` |
| `scripts/build-ios.sh`（Saydo。参考） | **65** | `docs/logs/task_004-3.txt` |

`scripts/build-ios.sh SpeechSpike`（先頭 4 行 = 今回のフォールバックの表示）:

```
build-ios: scheme=SpeechSpike
build-ios: 注意 — iOS シミュレータのランタイムが未導入で generic/platform=iOS Simulator を解決できない。
build-ios: destination を使わず -target SpeechSpike でビルドする（コンパイルとリンクだけの検証。実行はできない）。
build-ios: 解消するには空き容量を 9 GB 以上確保して xcodebuild -downloadPlatform iOS を実行する。
```

`scripts/build-ios.sh SpeechSpike`（末尾 30 行を要約せず引用。長いコマンド行は 200 桁で切った）:

```
Copy .../SpeechSpike.swiftmodule/arm64-apple-ios-simulator.swiftmodule ...
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-004
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -resolve-src-symlinks -rename ...

Ld .../Objects-normal/arm64/Binary/SpeechSpike normal arm64 (in target 'SpeechSpike' from project 'Saydo')
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-004
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -Xlinker -reproducible -target arm64-apple-ios26.0-simulator -isysroot ...

Ld .../Objects-normal/x86_64/Binary/SpeechSpike normal x86_64 (in target 'SpeechSpike' from project 'Saydo')
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-004
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -Xlinker -reproducible -target x86_64-apple-ios26.0-simulator -isysroot ...

CreateUniversalBinary .../SpeechSpike.app/SpeechSpike normal arm64\ x86_64 (in target 'SpeechSpike' from project 'Saydo')
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-004
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/lipo -create ...

ExtractAppIntentsMetadata (in target 'SpeechSpike' from project 'Saydo')
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-004
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor --toolchain-dir ...
2026-09-04 06:00:51.853 appintentsmetadataprocessor[96276:14083909] Starting appintentsmetadataprocessor export
2026-09-04 06:00:51.855 appintentsmetadataprocessor[96276:14083909] warning: Metadata extraction skipped. No AppIntents.framework dependency found.

CopySwiftLibs .../SpeechSpike.app (in target 'SpeechSpike' from project 'Saydo')
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-004
    builtin-swiftStdLibTool --copy --verbose --scan-executable .../SpeechSpike.app/SpeechSpike --scan-folder ...
Ignoring --strip-bitcode because --sign was not passed

** BUILD SUCCEEDED **

EXIT=0
```

`grep -c "warning:" docs/logs/task_004-1.txt` = **2**。内訳は
`ONLY_ACTIVE_ARCH=YES requested with multiple ARCHS ...`（ランタイム未導入で active arch が決まらないため）と
`appintentsmetadataprocessor ... No AppIntents.framework dependency found`。
**concurrency 警告は 0 件**（`-swift-version 6` / `SWIFT_STRICT_CONCURRENCY: complete` でビルドしている。
`grep -E "error:" docs/logs/task_004-1.txt` は 0 件）。

`grep -nE "@unchecked Sendable|nonisolated\(unsafe\)|URLSession|import Network" Spikes/SpeechSpike/*.swift`:

```
Spikes/SpeechSpike/SpikeAudio.swift:101:/// （`@unchecked Sendable` も `nonisolated(unsafe)` も使わないと決めている）。
```

コメント 1 行のみ。実コードでの使用は 0 件（`scripts/lint-principles.sh` は Spikes を対象外にしているため手で確認した）。

### done_definition との対応

| done_definition | 判定 | 証拠 |
|---|---|---|
| `docs/spikes/speech-spike.md` に ja-JP 対応可否・権限の種類・10 文の正答数・無音の推奨秒数・通知 5 回・AVAudioSession 設定 | **記入欄のみ**（実機計測が未実施） | `docs/spikes/speech-spike.md` §4 に手順と空欄、§3 に AVAudioSession の設定と `.allowBluetoothHFP` の根拠 |
| S-B の数値基準に対する判定 | **未達**（未計測） | 同 §5 の表は空欄。3 基準は明記済み |
| `AnalyzerInputConverter` を使わず `AVAudioConverter` + `AnalyzerInput(buffer:)` で供給できた | **済**（ビルドで確認。動作は未検証） | 同 §2。SDK 内に `AnalyzerInputConverter` は 0 件 |
| Go / No-Go の明記と No-Go 時の `SFSpeechRecognizer` フォールバック | **Go/No-Go は空欄**。フォールバックの記述は済 | 同 §5 |

### このタスクで変えた既存ファイル

- `scripts/build-ios.sh`: `-showdestinations` に iOS Simulator が出ない環境では
  `-destination` を使わず `-target <scheme>` でビルドするフォールバックを追加した（警告 3 行を出す）。
  ランタイム導入後は従来どおり scheme + generic destination で動く。
  この変更で `scripts/build-ios.sh`（Saydo）の失敗は exit 70（destination が無い）から
  exit 65（アセットカタログの actool 失敗）に変わった。**原因は task_001 と同じで未解消**だが、
  Swift のコンパイルまでは進むようになった。

### 未解決

- **iOS 26.x シミュレータランタイムが未導入**（task_001 と同じ。空き容量 6.3 GB / 必要 8.39 GB）。
  そのためスパイクを一度も実行できていない。`scripts/build-ios.sh SpeechSpike` の exit 0 は
  **コンパイルとリンクが通ったこと**しか意味しない。
- `Saydo.xcodeproj` はこのブランチに**含めていない**（fix-decisions H1.4: worktree では再生成しない）。
  新しく `Spikes/SpeechSpike/SpikeView.swift` と `SpikeAudio.swift` を足したので、
  **main へ取り込んだ後に `xcodegen generate` を実行しないとこの 2 ファイルがビルドに入らない**。
  検証時は worktree 内で `xcodegen generate` を実行し、コミット前に `git checkout -- Saydo.xcodeproj` で戻した。
- `AVAudioFile.write(from:)` を入力タップ内（オーディオスレッド）で呼んでいる。実機でグリッチが出る場合は
  書き込みを別スレッドへ逃がす必要がある（task_007 で再検討）。

### 人間の確認待ち

1. **実機での S-B / S-C 計測**（`docs/spikes/speech-spike.md` §4 の 4-1〜4-6）。
   Xcode で `SpeechSpike` スキームを実機に Run し、10 文の正答数・無音停止の誤作動・
   通知タップ → TTS 開始の 5 回・回り込みの有無を記入して、§5 の Go / No-Go を確定する。
2. **ディスク容量の確保**（task_001 から継続）。9 GB 以上空けて `xcodebuild -downloadPlatform iOS`。
   導入後は `scripts/build-ios.sh` が自動的に scheme + generic destination の経路に戻る。
3. main へのマージ後に `xcodegen generate` を実行して `Saydo.xcodeproj` を更新する。

---

## task_007 — 音声スタック（録音 + SpeechAnalyzer + 無音停止 + TTS + 再生 + 波形）

- 日時: 2026-09-04
- 状態: needs-device（型検査は緑。リンク・実行・実機動作は未検証）
- ブランチ: `task/007-audio`
- 分岐元: `task/004-speech-spike`（d2f6495）

`Spikes/SpeechSpike/SpikeAudio.swift` の 1 画面スパイクを、`App/Audio/` の再利用可能な
サービス 7 本へ昇格させた。すべて `@MainActor`、すべて protocol で抽象化してあり、
task_008 の `SessionViewModel` がモックを注入できる。

| ファイル | 型 | protocol |
|---|---|---|
| `App/Audio/AudioSessionController.swift` | `AudioSessionController` | `AudioSessionControlling` |
| `App/Audio/VoiceCapture.swift` | `VoiceCapture` | `VoiceCapturing` |
| `App/Audio/SilenceDetector.swift` | `SilenceDetector`（純ロジック・struct） | なし（値型） |
| `App/Audio/TranscriptionService.swift` | `TranscriptionService` | `Transcribing` |
| `App/Audio/SpeechSynthesisService.swift` | `SpeechSynthesisService` | `Synthesizing` |
| `App/Audio/VoicePlayer.swift` | `VoicePlayer` | `Playing` |
| `App/Audio/WaveformSampler.swift` | `WaveformSampler` | なし（`@Observable` の表示状態） |

### 証拠

全文ログ: `docs/logs/task_007-1.txt`

| コマンド | exit code |
|---|---|
| `swiftc -typecheck -swift-version 6 -strict-concurrency=complete -sdk "$SDK" -target arm64-apple-ios26.0-simulator App/Audio/*.swift` | **0** |
| 同上 + `-enable-upcoming-feature ExistentialAny -enforce-exclusivity=checked`（Saydo ターゲットと同じフラグ） | **0** |
| `swiftc -emit-module -module-name Saydo -enable-testing ... App/SaydoApp.swift App/Audio/*.swift` | **0** |
| `swiftc -typecheck ... -I <mod> -I "$PLAT/Developer/usr/lib" -F "$PLAT/Developer/Library/Frameworks" Tests/SaydoTests/SilenceDetectorTests.swift` | **0** |
| `scripts/lint-principles.sh` | **0** |
| `scripts/test-ios.sh` | **2**（環境要因） |
| `scripts/build-ios.sh` | **65**（環境要因。Swift のコンパイルに到達しない） |

`grep -c "warning:"`（上の swiftc 4 本の出力）: **0**

末尾 30 行（`docs/logs/task_007-1.txt` の 6)〜8) 節）:

```
==================================================================
6) 警告件数
$ grep -c "warning:" <2)〜5) の出力>
0

==================================================================
7) scripts/lint-principles.sh
lint-principles: 対象 8 ファイル（App/ と Packages/*/Sources。Tests と Spikes は除外）
lint-principles: OK
EXIT=0

==================================================================
8) scripts/test-ios.sh（環境要因で未達）
test-ios: iOS 26.x の利用可能なシミュレータが見つからない。
  導入コマンド: xcodebuild -downloadPlatform iOS（約 8.4 GB の空きが必要）
  現在のランタイム一覧:
== Runtimes ==
iOS 18.5 (18.5 - 22F77) - com.apple.CoreSimulator.SimRuntime.iOS-18-5
EXIT=2
```

#### whole-module でしか出ない診断を 1 件踏んで直した

`swiftc -typecheck` はファイル単位なので通ってしまうが、`-emit-module`（whole-module）だと

```
App/Audio/VoiceCapture.swift:125:16: error: sending 'buffer.some' risks causing data races
note: task-isolated 'buffer.some' is passed as a 'sending' parameter
```

が出た。原因と回避は `docs/spikes/speech-spike.md` §1「詰まった 1 点と回避」と同じで、
入力バッファを `[[Float]]`（Sendable）経由で複製してから `Mutex<AVAudioPCMBuffer?>` に入れる。
スパイクの `InputBufferSource(copying:)` をそのまま `VoiceCapture.swift` へ移した。
**次タスクで新しく `AVAudioPCMBuffer` を跨がせる場合も同じ罠を踏むので、
検証は `-typecheck` だけでなく `-emit-module` も掛けること。**

#### xcodebuild は本タスクのコードを一切検証していない

`scripts/build-ios.sh` の exit 65 は actool（アセットカタログ）の失敗で、
**Swift のコンパイルには到達していない**。一時的に `xcodegen generate` して
App/Audio の 7 ファイルをターゲットへ入れた状態で測っても
`SwiftCompile` 0 件 / `EmitSwiftModule` 0 件 / `.o` 0 個だった。
確認後 `git checkout -- Saydo.xcodeproj` で戻し、`build/` は削除した。

### done_definition との対応

| done_definition | 判定 | 証拠 |
|---|---|---|
| `scripts/test-ios.sh` が緑（SilenceDetectorTests を含む） | **未達（環境要因）** | exit 2。iOS 26.x ランタイム未導入。テストは書いたが**一度も実行していない** |
| 実機で「話す → 無音で停止 → 文字起こし → 再生」が動く手動確認記録 | **未達** | 実機作業。手順は task_004 の `docs/spikes/speech-spike.md` §4 と同じ |
| 音声認識権限のダイアログが出ない（マイクのみ） | **未検証** | `SFSpeechRecognizer` の呼び出しは無い（`grep -rn SFSpeechRecognizer App/` は `TranscriptionService.swift` のコメント 1 行だけ）。ダイアログの実挙動は実機でしか見られない |
| `installTap` のクロージャ内に状態変更が無く、concurrency 警告が 0 件 | **済** | クロージャが触るのは `AVAudioFile.write(from:)` と continuation 2 本の `yield` だけ。`grep -c "warning:"` = 0 |

### 採用した設定（docs/spikes/speech-spike.md と実装計画 §7.3 から）

- `AVAudioSession`: カテゴリ `.playAndRecord` / モード `.default`（`.voiceChat` に切替可） /
  オプション `[.allowBluetoothHFP, .allowBluetoothA2DP]`。
  **スパイクと違い `.defaultToSpeaker` は付けていない**（実装計画 §7.3 と task_007 scope に従う。
  付けるとイヤホンが無視され R8 が成立しない）。出力先は再生・発話の直前に
  `applyOutputRoute(preferReceiver:)` が `currentRoute.outputs` を見て
  accessory / speaker / receiver を決める。
- 消音スイッチ: `.playAndRecord` はスイッチの影響を受けないので OS 任せにしない。
  `requiresAudiblePlaybackConfirmation`（イヤホン未接続 かつ `outputVolume > 0.3`）を
  確認 UI（「イヤホンで聞く / 文字で読む」）のゲートにした（fix-decisions P3.1 / P5.4）。
- 無音判定: RMS 閾値 0.015、既定 1.5 秒（`SilenceDuration` = 1.2 / 1.5 / 2.0）。
- 録音: AAC 32 kbps、標本化周波数とチャンネル数は入力ノードに合わせる。タップは 4096 フレーム。
- 上限: `VoiceCaptureLimit.utterance` = 20 秒 / `.declaration` = 30 秒。
  到達したら `.reachedLimit` を流して自分で停止する。
- TTS: ja-JP の enhanced / premium を優先し、無ければ既定音声で開始する（fix-decisions P5.8）。
  `hasHighQualityJapaneseVoice` をオンボーディングの案内条件に使う。
- `AnalyzerInputConverter` は使わない（iOS 26.2 SDK に不在）。`AVAudioConverter` +
  `AnalyzerInput(buffer:)` で供給する（fix-decisions P4.1）。

### 未解決

- **`Saydo.xcodeproj` はこのブランチに含めていない**（task_004 と同じ運用）。
  `App/Audio/` の 7 ファイルと `Tests/SaydoTests/SilenceDetectorTests.swift` を足したので、
  **main へ取り込んだ後に `xcodegen generate` を実行しないとビルドとテストに入らない**。
- `project.yml` は変更していない。`Saydo` ターゲットの sources が `path: App`（ディレクトリ単位）、
  `SaydoTests` が `path: Tests/SaydoTests` なので、ターゲット定義の追加は不要。
- `SilenceDetectorTests` は **一度も実行していない**（iOS 26.x ランタイム未導入）。型検査だけが根拠。
- `AVAudioFile.write(from:)` を入力タップ内（オーディオスレッド）で呼んでいる（task_004 から継続）。
  実機でグリッチが出る場合は書き込みを別スレッドへ逃がす。
- `AudioSessionController` は `deinit` で通知の解除をしない（`@MainActor` の格納プロパティに
  nonisolated な deinit から触れないため）。`deactivate()` を明示的に呼ぶ設計にした。
  task_008 の `SessionViewModel` が画面の終了時に呼ぶこと。
- `AudioSessionController.events` は購読者 1 つを想定した `AsyncStream`。
  複数の画面から同時に購読する必要が出たら分配層が要る。
- RMS 閾値 0.015 と `WaveformSampler` の正規化基準（これまでの最大値・下限 0.05）は
  実機で調整する前提の初期値。

### 人間の確認待ち

1. **ディスク容量の確保**（task_001 から継続・これが全ての iOS ビルドとテストを止めている）。
   9 GB 以上空けて `xcodebuild -downloadPlatform iOS`。導入後に `scripts/test-ios.sh` を実行して
   `SilenceDetectorTests` の緑を確認し、このエントリの done_definition 表を更新する。
2. **実機での結合確認**（task_007 scope「UI なしの結合テストは実機で手動確認」）。
   録音ファイルが生成されて再生できること、話す → 無音で停止 → 文字起こし → 再生が通ること、
   マイク以外の権限ダイアログが出ないこと。
3. main へのマージ後に `xcodegen generate` を実行して `Saydo.xcodeproj` を更新する。
