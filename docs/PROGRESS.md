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

---

## task_008-core — SessionViewModel と結合テスト（UI を除く）

- 日時: 2026-09-04
- 状態: wip（UI 4 ファイルは後続。iOS シミュレータでの実行は環境要因で未検証）
- ブランチ / コミット: `task/008-session-vm`（`task/005-flows` から分岐し、`task/006-data` と `task/007-audio` をマージ）

### 作ったもの

| ファイル | 中身 |
|---|---|
| `App/Features/Session/SessionViewModel.swift` | `@MainActor @Observable`。`FlowMachine` の 9 命令（speak / listen / showChoices / record / play / save / scheduleNotification / cancelNotification / finish）を音声スタック・`Repository`・通知に配線する。状態は `SessionPhase`（idle / speaking / listening / thinking / choosing / recordingDeclaration / playback / done / error(micDenied / assetDownloading)）。あわせて `protocol NotificationScheduling`（task_009-app が実装）、`protocol SessionStore` と `RepositorySessionStore`、`Repository` の `SessionLog` 読み書き拡張を同ファイルに置いた |
| `Tests/SaydoTests/SessionViewModelTests.swift` | インメモリの `SessionStore`、`Synthesizing` / `VoiceCapturing` / `Transcribing` / `Playing` のモック、通知のスパイを注入した結合テスト 14 件 |

`SessionView` / `WaveformView` / `ChoiceChipsView` / `TextFallbackSheet` と `App/SaydoApp.swift` の更新は
**このコミットに含まない**（UI は後続）。

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| iOS 26 シミュレータ SDK に対する型検査（SaydoCore / App / Tests の 3 段） | **0 / 0 / 0**（warning 0 件） | `docs/logs/task_008-typecheck.txt` |
| macOS ハーネスで `Tests/SaydoTests` を実行（代替検証） | **1**（60 件中 59 件成功。失敗 1 件は後述の既知の理由） | `docs/logs/task_008-macos-tests.txt` |
| `scripts/test-core.sh` | **0**（143 tests） | `docs/logs/task_008-testcore.txt` |
| `scripts/lint-principles.sh` | **0** | `docs/logs/task_008-lint.txt` |
| `scripts/build-ios.sh` | **65**（環境要因。**このコミットの Swift は 1 行もコンパイルされていない**。後述） | `docs/logs/task_008-buildios.txt` |

型検査（`docs/logs/task_008-typecheck.txt` 全文）:

```
# SDK: .../iPhoneSimulator26.2.sdk
# target: arm64-apple-ios26.0-simulator
$ xcrun swiftc -emit-module -module-name SaydoCore ... <SaydoCore の全 .swift>
CORE_EXIT=0
$ xcrun swiftc -emit-module -module-name Saydo -enable-testing -I <mod> ... <App の全 .swift>
APP_EXIT=0
$ xcrun swiftc -typecheck -module-name SaydoTests -I <mod> -I <XCTest lib> -F <XCTest fw> ... <Tests/SaydoTests の全 .swift>
TESTS_EXIT=0
warnings: 0
```

型検査が本当にモジュールを解決していることは、`SessionPhase` に存在しない case を書いた
使い捨てファイルが `error: type 'SessionPhase' has no member 'nope'` で落ちることで確かめた。

macOS ハーネスでのテスト実行（末尾）:

```
Test Case '-[SaydoTests.SessionViewModelTests testSilenceNudgesOnceThenSkipsTheQuestion]' passed (0.001 seconds).
Test Case '-[SaydoTests.SessionViewModelTests testTimeboxExceededEndsSessionAndRecordsLastStep]' started.
Test Case '-[SaydoTests.SessionViewModelTests testTimeboxExceededEndsSessionAndRecordsLastStep]' passed (0.000 seconds).
Test Suite 'SessionViewModelTests' passed at 2026-09-04 06:37:28.
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.013 (0.013) seconds
...
Test Case '-[SaydoTests.SmokeTests testBundleIdentifierIsSaydo]' started.
SmokeTests.swift:5: error: XCTAssertEqual failed: ("Optional("com.apple.dt.xctest.tool")") is not equal to ("Optional("com.nonturn.saydo"))
Test Case '-[SaydoTests.SmokeTests testBundleIdentifierIsSaydo]' failed (0.045 seconds).
	 Executed 60 tests, with 1 failure (0 unexpected) in 0.127 (0.130) seconds
```

**`SessionViewModelTests` は 14 件すべて成功。** 唯一の失敗 `SmokeTests.testBundleIdentifierIsSaydo` は
アプリのバンドル ID を見るテストで、macOS の `xctest` ツール上では成立しない**ハーネス由来の失敗**。
iOS ターゲットでは task_001 で成功している。

`scripts/build-ios.sh`（末尾）:

```
** BUILD FAILED **
The following build commands failed:
	CompileAssetCatalogVariant thinned .../Saydo.app .../App/Resources/Assets.xcassets (in target 'Saydo' from project 'Saydo')
(1 failure)
```

**この exit 65 は本タスクのコードの証拠にならない。** 理由は 2 つあり、どちらも環境と手順によるもの:
(a) task_001 から続く `actool` の失敗（iOS 26.x シミュレータランタイム未導入）でアセットカタログが通らない。
(b) worktree では `xcodegen generate` を実行しない規約のため、`Saydo.xcodeproj` に本タスクの
新規 2 ファイルが**入っていない**（`grep -c SessionViewModel Saydo.xcodeproj/project.pbxproj` = 0）。
つまり xcodebuild は本コミットの Swift を 1 行もコンパイルしていない。
コードの検証は上の型検査と macOS 実行で取っている。

### 代替検証の作り方（リポジトリには入れない）

控えは `docs/logs/task_008-macos-harness-Package.swift.txt`。SwiftPM の macOS パッケージに
`Packages/SaydoCore/Sources/SaydoCore`・`App/**`・`Tests/SaydoTests/**` を symlink し、
macOS 非対応 API を持つ 4 ファイル（`AudioSessionController` / `SpeechSynthesisService` /
`VoicePlayer` / `SaydoApp`）だけを除いて、そのプロトコル面を実ファイルから切り出したものに差し替える。
`SessionViewModel` はこれらの具象クラスに依存していないので、検証したい経路はそのまま走る。

### done_definition の自己監査

| 条件 | 状況 | 根拠 |
|---|---|---|
| M4 完了時に m4a と Commitment が保存されている | 済（テストで） | `testMorningFlowCompletesAndSavesCommitmentWithThreeVoiceEntries`（`declarationAudioPath` が非 nil、宣言 `VoiceEntry.audioPath` と同一） |
| SessionLog に開始・終了・完走・tier・lastStep が記録されている | 済 | 同テストで 5 項目すべてを検証。`guardrailReplacedCount` は Tier B では常に 0 |
| M0 の文字起こしが 1 行表示され、1 タップで再録音できる | ViewModel 側は済 | `testAvoidanceTranscriptCanBeRetakenOnce`（誤認識の `VoiceEntry` を消して録り直し、2 回目は不可）。表示は UI（後続） |
| SessionViewModelTests が緑 | 済（macOS 代替実行） | 14 件成功。iOS シミュレータでの実行は**未検証** |
| 朝フロー完走後、当日の VoiceEntry が 3 件（入力方式に依らず） | 済 | 声の経路と、マイク拒否のテキスト経路の両方で 3 件を検証 |
| 通知タップまたは起動から 1.5 秒以内に TTS 開始／タップ 0 回で M4 到達 | **未検証** | 実機の画面録画が要る |
| M1 の理由チップ 7 個が iPhone SE × Dynamic Type xxxLarge に収まる | **未着手** | UI（後続） |
| 実機で朝フロー 3 回の SessionLog 中央値が 3 分以内 | **未検証** | 実機が要る |

### 設計上の判断（レビュー対象）

1. **`SessionStore` プロトコルを挟んだ**。`Repository` は `@ModelActor` の具象アクターで、
   既定引数のあるメソッドはプロトコル要件の witness にならない。`RepositorySessionStore` で
   引数を明示して転送し、テストにはインメモリ実装を注入する。
2. **`SessionLog` の読み書きを `Repository` の拡張として足した**（fix-decisions P1.3）。
   task_006 の `Repository` に無かったため。scope を守って `SessionViewModel.swift` に置いたが、
   **本来は `App/Data/Repository.swift` に移すべき**。task_010 / 011 が同ファイルを触るときに移す。
3. **宣言（M4）だけ `appendVoiceEntry` を呼ばない**。`Repository.createCommitment` が
   宣言音声の `VoiceEntry` を作るので二重書き込みになる。声なしの日は `createCommitment` が
   作らないため、その場合だけ音声なしの 1 件を後から足して 3 件をそろえる。
4. **行動時刻の通知を `Commitment` 作成まで遅らせる**。`FlowMachine` は M4 の `save` の直後に
   `scheduleNotification` を出すが、その時点では `commitmentID` が無い（通知の `userInfo` に
   載せられない）。朝フローでは命令を溜め、`createCommitment` の直後にまとめて登録する。
5. **タイムアウトはテスト専用の入口を作らず、実 API（`silenceElapsed()` / `timeboxElapsed()`）に
   した**。見張りタイマーもテストも同じ経路を通る。待ち時間は `SessionTimer` として注入し、
   テストは実時間を待たずに要求された待ち秒数（180 / 5 / 10）だけを検証する。
6. **`error(micDenied)` は行き止まりにしない**。マイクが使えない・録音が始められない場合は
   掲示（`notice`）を出したうえでテキスト経路に落とし、会話は完走させる（計画 §7.2）。
7. **タイムボックスの秒数（朝 180 / 昼 60 / 夜 60）は ViewModel に置いた**。SaydoCore の
   `FlowMachine` は時計に触らない設計なので、時間の値は外に置くのが筋と判断した。

### 未解決

1. **`Commitment` に場所（`plannedPlace`）の保存先が無い**。計画 §10 の表には載っているが
   task_006 のモデルには無い。M3 で本人が言った場所は `JapaneseTimeParser` で切り出して
   `SessionViewModel.plannedPlace` に持つだけで、**永続化されていない**。
   モデルに足すか、計画 §10 から落とすかの判断が要る。
2. **`CopyPicker` の使用履歴（`copyHistory`）を保存していない**。毎回空で渡しているため、
   retention R5「3 日以内に同じ文言を繰り返さない」が**セッションをまたいで効かない**。
   `CopyPicker.Use` の保存先（`UserDefaults` か SwiftData）を決める必要がある。
3. `guardrailReplacedCount` は Tier B では常に 0。置換が起きるのは Tier A の生成文
   （task_014 / 015）なので、そこで積む。
4. `AudioSessionControlling` は ViewModel に配線していない。再生前の
   「イヤホンで聞く / 文字で読む」（R8）は task_010 の担当。
5. 昼フローの `MicroAction` は `Commitment` から復元していない（`FlowState.microAction` は
   `NoonFlow.start` で nil のまま）。N3 で本人が言い直した行動は `Repository.shrink` で
   書けているが、「今の行動文を読み上げる」には復元が要る。task_010 で入れる。

### 人間の確認待ち

1. **ディスク容量の確保**（task_001 から継続）。9 GB 以上空けて `xcodebuild -downloadPlatform iOS`。
   導入後に `scripts/test-ios.sh` を実行し、`SessionViewModelTests` 14 件が iOS シミュレータでも
   緑になることを確認して、この表の「未検証」を更新する。
2. **実機での確認**: 通知タップから TTS 開始までの時間（1.5 秒以内）、タップ 0 回での M4 到達、
   朝フロー 3 回の所要時間の中央値（3 分以内）。いずれも画面録画が要る。
3. main へのマージ後に `xcodegen generate` を実行し、`App/Features/Session/SessionViewModel.swift` と
   `Tests/SaydoTests/SessionViewModelTests.swift` を `Saydo.xcodeproj` に取り込む。

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

## task_016-core — 週次分析の純ロジック（InsightCalculator）

- 日時: 2026-09-04
- 状態: done（SaydoCore の純ロジック部分のみ。`WeeklyInsightView` と `Repository.weeklyStats` は未着手）
- ブランチ / コミット: `task/009-notification-core` / （このコミット）

### スコープ

task_016 のうち **SaydoCore に置く純計算だけ**。SwiftUI / SwiftData には触れていない。

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/test-core.sh` | **0**（62 tests, 0 failures） | `docs/logs/task_016-core-1.txt` |

```
Test Suite 'InsightCalculatorTests' passed at 2026-09-04 06:05.
	 Executed 15 tests, with 0 failures (0 unexpected)
Test Suite 'All tests' passed
	 Executed 62 tests, with 0 failures (0 unexpected) in 0.014 (0.017) seconds
lint-principles: OK
EXIT=0
```

### 確定した週次分析の契約

| 型 | 内容 |
|---|---|
| `InsightInput` | `date` / `domain?` / `reason?` / `outcome`。App 側の `Repository` が `Commitment` + `AvoidanceItem` から詰め替える |
| `InsightCalculator.weeklyStats(from:weekStart:)` | 与えられた入力をそのまま集計。期間の切り出しは呼び出し側 |
| `InsightCalculator.weeklyStats(from:weekContaining:calendar:)` | 暦の週で切り出してから集計 |
| `InsightCalculator.firstInsight(from:)` | 3 件目で出す 1 行（retention R9）。件数不足・最多が 1 件のときは nil |
| `InsightCalculator.weeklyReflection(for:)` | テンプレートの振り返り 1 文。3 件未満は `InsightCopy.notEnoughData` |
| `InsightCopy` | データ不足の文言、初回インサイト、理由 × 分野の組み合わせ表（7 理由 × 7 分野） |

集計の規則:

- 分野別件数は `domain != nil` の件数。理由別割合の母数は `reason != nil` の件数。
- 結果内訳（done / partial / notYet）と平均縮小回数は**持たない**（`WeeklyStats` が持たない。
  達成率の表示に使わせないため。企画原則 §22-8）。

企画メモ §11 の例を再現するフィクスチャ（`InsightCalculatorTests.conceptMemoFixture`）:

- 分野 56 件 = 人への返信 18 / お金 14 / 大きなタスク 11 / 営業 8 / 書類 5（上位 5 の並びが §11 と一致）
- 理由 56 件 = 気まずさ 21 / 完璧主義 15 / 面倒 12 / 不安 8
  → 38% / 27% / 21% / 14%（§11 の数字と一致）

### 未解決

- `scripts/lint-principles.sh` が `Insight/InsightCopy.swift` の日本語リテラルを WARN で列挙する
  （task_002 の Domain `displayName` と同じ扱い。exit code には影響しない）。
  文言を Copy ファイルに集約する規約自体は守っている。許可リストに `InsightCopy.swift` を足すかは
  レビューの判断に委ねる。**WARN を消すために文言を `InsightCalculator` へ戻さないこと。**
- `Repository.weeklyStats`・`WeeklyInsightView`・Tier A の `weeklyReflection`（task_014）は未実装。
- 分野の判定（Tier B のキーワード辞書 / Tier A の `classifyDomain`）は task_005 / task_014 の担当。
  `InsightCalculator` は `domain` が入っている前提で数えるだけ。

### 人間の確認待ち

- task_001 と同じ（iOS 26.x シミュレータランタイムの導入）。追加はなし。
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
## task_019 — データの書き出し・全削除・バックアップ復元の確認（UI を除く中核）

- 日時: 2026-09-04
- 状態: wip（中核は done。**設定画面の UI と実機での復元確認は未実施**）
- ブランチ: `task/019-data-export`（`task/006-data` から分岐）

### やったこと

| 変更 | 内容 |
|---|---|
| `App/Features/Settings/DataExporter.swift`（新規） | 全 5 モデルを JSON にし、音声と一緒に zip にまとめる |
| `App/Data/Repository.swift`（追加のみ） | `deleteAll(cancelPendingNotifications:)` と `DeletionSummary` を追加。既存メソッドは変えていない |
| `Tests/SaydoTests/DataExporterTests.swift`（新規） | 純ロジックのテスト 11 件（JSON の中身・ファイル一覧・zip・ファイル名） |
| `docs/backup-restore-check.md`（新規） | 人間が実機で埋める確認手順と記入欄（容量・復元・ファイル保護） |

**このタスクの範囲外（別担当）**: `App/Features/Settings/SettingsView.swift`（書き出しの ShareLink と「全部消す」のボタン）。
`.xcodeproj` は再生成していない（worktree では生成しない規約）。`project.yml` と `SaydoCore` は触っていない。

### 設計

- **zip の作り方**: `NSFileCoordinator` の `.forUploading` にディレクトリを渡すと zip ができる。
  これが Foundation だけで zip 書庫を作れる唯一の経路（`Compression` はストリーム圧縮で書庫を作らず、
  `AppleArchive` が作るのは `.aar` で Finder が開けない）。
- **純ロジックの分離**: `ExportArchive`（Codable な値型 5 種）と `DataExportBuilder`（ファイルを並べて zip にする）は
  SwiftData に触らない。SwiftData を読むのは `DataExporter`（`@ModelActor`）だけ。テストは前者だけを見る。
- **`Repository` を増やさない**: 書き出しは読み取り専用なので、`Repository` に fetch を足さず
  `DataExporter` を別の `@ModelActor` にした。`Repository` への追加は `deleteAll` だけ。
- **`deleteAll` が消さないもの**: `UserDefaults`（`AppSettings.reset()`）と保留中の通知。
  前者は画面の判断、後者はコールバック（`cancelPendingNotifications`）に委譲した。
  `Repository` が `UserNotifications` を持つと保存データのテストが通知センターを要るようになるため。
- 書き出しの zip は `tmp/SaydoExport/` に置く（バックアップ対象外。共有したら消えてよい）。

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `swiftc -typecheck -swift-version 6 -strict-concurrency=complete`（App のソース） | **0** | `docs/logs/task_019-1.txt` |
| `swiftc -typecheck`（`Tests/SaydoTests/DataExporterTests.swift`、`-enable-testing` の Saydo モジュール付き） | **0** | `docs/logs/task_019-2.txt` |
| macOS 実行確認（SwiftData in-memory で書き出し + 全削除、22 件すべて PASS） | **0** | `docs/logs/task_019-3.txt` |
| `scripts/lint-principles.sh` | **0**（`lint-principles: OK`。DataExporter.swift は日本語リテラルの WARN なし） | `docs/logs/task_019-4.txt` |
| `scripts/build-ios.sh` | **70**（task_001 / 002 と同じ destination の問題。差分とは無関係） | `docs/logs/task_019-5.txt` |
| `scripts/test-ios.sh` | **2**（iOS 26.x のシミュレータランタイムが無い） | `docs/logs/task_019-6.txt` |

`swiftc -typecheck`（iOS シミュレータ SDK・iOS 26.0 ターゲット・Swift 6 strict concurrency）は
`scripts/build-ios.sh` が通らない環境での代替。`@ModelActor` と `#Predicate` を含めて 0 で通る。

macOS 実行確認の末尾（全文は `docs/logs/task_019-3.txt`）:

```
--- deleteAll ---
DeletionSummary(avoidanceItemCount: 1, commitmentCount: 1, voiceEntryCount: 2, sessionLogCount: 0, carryoverCount: 1, audioFileCount: 2)
PASS  通知取り消しのコールバックが呼ばれた
PASS  消したレコード数 = 5
PASS  消した音声 = 2
PASS  音声ディレクトリが消えた
PASS  全削除後は空
EXIT 0
```

同じ実行で確かめた zip の中身:

```
     2015  09-04-2026 06:12   saydo-export/saydo-export.json
    61440  09-04-2026 06:12   saydo-export/Audio/2026/09/aaaaaaaa-0000-0000-0000-000000000001.m4a
    58000  09-04-2026 06:12   saydo-export/Audio/2026/09/bbbbbbbb-0000-0000-0000-000000000002.m4a
```

### done_definition との対応

| done_definition | 状態 |
|---|---|
| zip に音声と JSON が含まれる | **満たした**（macOS 実行確認。iOS 実機は未確認） |
| 全削除で空状態に戻る | **保存データは満たした**。「オンボーディングに戻る」は `AppSettings.reset()` を呼ぶ設定画面（別担当）が要る |
| ドッグフーディング 7 日後のデータで復元確認を行った記録がある | **未達**。`docs/backup-restore-check.md` の記入欄が空。task_013b の後に人間が実施する |
| 実測の 1 件あたり容量と年間見積もりが記録されている | **見積もり（60 KB/件・年間約 110 MB）は記載済み。実測欄は空** |

### 未検証

- **iOS シミュレータ・実機では 1 行も動かしていない。** 型検査と macOS 実行だけ。
  `NSFileCoordinator(.forUploading)` の zip 生成は macOS 26.0 でしか確認できていない。
- `Tests/SaydoTests/DataExporterTests.swift` は**型検査のみ**。`xcodebuild test` は動かせていない（上表の exit 2）。
- ShareLink での共有、ファイル保護属性、iCloud バックアップからの復元は全部未確認。

### 未解決

- **`DayKey.make(from:calendar:)` は端末の暦設定が和暦だと壊れる**（task_006 の `App/Data/Schema.swift`）。
  `Calendar(identifier: .japanese)` では `dateComponents(...).year` が元号の年を返すため、
  2026-09-04 が `0008-09-04` になる（macOS で実測）。`Commitment.dayKey` と `Carryover.forDayKey` が
  日ごとに変わらなくなるわけではないが、`AppSettings` の暦とまたぐと日付の解釈が食い違う。
  本タスクの範囲外なので直していない（task_006 のファイル）。`DayKey` を
  `Calendar(identifier: .gregorian)` に固定するのが直し方。`DataExporter.zipFileName` は
  同じ罠を踏まないよう西暦固定にしてある。
- `App/Features/Settings/SettingsView.swift` は未作成（task_013 / task_019 の UI 担当）。
  そこで `DataExporter.export()` の返す `zipURL` を ShareLink に渡し、
  「全部消す」で `Repository.deleteAll { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }` と
  `AppSettings.shared.reset()` の両方を呼ぶこと。**後者を呼ばないとオンボーディングに戻らない。**
- `Saydo.xcodeproj` に新しいファイルが登録されていない。main へマージしたあとで `xcodegen generate` が要る。

### 人間の確認待ち

- task_001 と同じ **iOS 26.x シミュレータランタイムの導入**（`xcodebuild -downloadPlatform iOS`）。
  導入後に `scripts/test-ios.sh` を実行し、`DataExporterTests` の 11 件が通ることを確かめて上表を更新すること。
- **`docs/backup-restore-check.md` の記入欄**（1〜6 節）。task_013b の 7 日間ドッグフーディングが終わった後に、
  実機で書き出し・全削除・iCloud バックアップ復元・ファイル保護属性・容量実測を行い、結果を書き込む。
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
## task_023 — 行動時刻アラーム（AlarmKit）スパイク S-E

- 日時: 2026-09-04
- 状態: **コンパイルまで完了。実機挙動は全て未検証（人間の確認待ち）**
- ブランチ: `task/023-alarm-spike`
- 記録: `docs/spikes/alarm-spike.md`

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `xcodegen generate` | 0 | — |
| `scripts/build-ios.sh AlarmSpike` | **70**（task_001 / 002 と同じ destination の問題。AlarmSpike の差分とは無関係） | `docs/logs/task_023-1.txt` |
| `xcodebuild -project Saydo.xcodeproj -target AlarmSpike -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` | **0** | `docs/logs/task_023-2.txt` |
| `supportedModes` の実測（4 通りビルド） | 全て 0 | `docs/logs/task_023-3.txt` |

`scripts/build-ios.sh AlarmSpike`（末尾）:

```
xcodebuild: error: Unable to find a destination matching the provided destination specifier:
		{ generic:1, platform:iOS Simulator }

	Ineligible destinations for the "AlarmSpike" scheme:
		{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device, error:iOS 26.2 is not installed. Please download and install the platform from Xcode > Settings > Components. }
EXIT=70
```

`-target` 直指定（destination を要求しないためランタイム不要）の末尾:

```
Validate /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-023/build/Debug-iphonesimulator/AlarmSpike.app (in target 'AlarmSpike' from project 'Saydo')
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-023
    builtin-validationUtility /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-023/build/Debug-iphonesimulator/AlarmSpike.app -shallow-bundle -infoplist-subpath Info.plist

Touch /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-023/build/Debug-iphonesimulator/AlarmSpike.app (in target 'AlarmSpike' from project 'Saydo')
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-023
    /usr/bin/touch -c /Users/noritakasawada/AI_P/SAYDO/.worktrees/task-023/build/Debug-iphonesimulator/AlarmSpike.app

warning: ONLY_ACTIVE_ARCH=YES requested with multiple ARCHS and no active architecture could be computed; building for all applicable architectures (in target 'AlarmSpike' from project 'Saydo')
** BUILD SUCCEEDED **

EXIT=0
```

ソース由来の警告は 0 件（`ONLY_ACTIVE_ARCH` の 1 件のみ。これはランタイム未導入に伴うもの）。
`SWIFT_VERSION=6.0` + `SWIFT_STRICT_CONCURRENCY=complete` のまま、`@unchecked Sendable` も
`nonisolated(unsafe)` も `@preconcurrency import` も使わずに通っている。

### API についての確定事項（詳細は `docs/spikes/alarm-spike.md` §2）

- `AlertConfiguration.AlertSound` は **ActivityKit** の **struct**。公開メンバーは
  `static var default` と `static func named(_ name: String) -> AlertSound` の 2 つだけ。enum の case ではない。
  AlarmKit は ActivityKit を再エクスポートしないので **`import ActivityKit` が必須**（省くとコンパイルエラー）。
- `AlertSound.named` の SDK ドキュメントコメントに「main bundle **または** データコンテナの `Library/Sounds`」と明記されている。
  スパイクの未確認事項「音声ファイルの置き場所」への SDK 側の回答。AlarmKit が同じ探索をするかは実機項目。
- **`AlarmPresentation.Alert.stopButton` は iOS 26.1 で deprecated**（"This property is not used anymore"）。
  26.1 以降の init には stopButton 引数自体が無い。**停止ボタンはアプリの持ち物ではなくなった** =
  要望「アプリを開くまで消せない」は AlarmKit 単体では成立しない。
- `AlarmConfiguration.alarm(...)` に **`appEntityIdentifier:` という引数は存在しない**（26.2 SDK）。
- `cancel` / `stop` / `pause` / `resume` / `countdown` は同期の `throws`。`async` なのは `schedule` と
  `requestAuthorization` だけ。`alarms` は `get throws`。
- `AlarmButton` に `.stopButton` などの static メンバーは無い。`init(text:textColor:systemImageName:)` のみ。
- **`supportedModes` の罠（実測）**: `static let supportedModes: IntentModes = .foreground(.immediate)` と書くと
  AppIntents のメタデータ抽出が定数畳み込みできず、`.background` と同じ **1** を書き出す。
  static var 形式の `.foreground` なら **2**。4 通りとも exit 0・警告 0 件なので**コンパイラは何も言わない**。
  SAYDO 本体で AppIntent を書くときも同じ罠を踏む。

### 未解決

- 実機挙動は 1 つも検証できていない。消音/集中モード、連鎖、Open インテント、バンドル外サウンド、
  強制終了、音量の 6 項目は全て `docs/spikes/alarm-spike.md` §6 の記入欄が空のまま。
- `NSAlarmKitUsageDescription` というキー名は Xcode 同梱ドキュメント由来で、コンパイラでは検証できない。実機項目 (0)。
- アラームの同時登録上限（`AlarmError.maximumLimitReached` が出る件数）は SDK に定数が無く未測定。
- iOS 26.x シミュレータランタイムは依然として未導入（`xcrun simctl runtime list` は `Total Disk Images: 0`）。
  そのため `scripts/build-ios.sh` は AlarmSpike でも通らない。task_001 の「人間の確認待ち」と同じ。

### 人間の確認待ち

1. **実機で `docs/spikes/alarm-spike.md` §6 の 6 項目（+ 補助 4 項目）を実施し、記入欄と Go / No-Go を埋める。**
   iOS 26.x の実機が必要。シミュレータでは意味が無い。
2. §7 の要望 4 点の整理表を実機結果で確定させる。特に①（アプリを開くまで消せない）と④（音量が最大に戻る）は
   **API の事実として不可**なので、連鎖アラームで代替するか、体験設計を変えるかの方針判断が要る。
3. iOS 26.x シミュレータランタイムの導入（task_001 と同じ）。

## integration — 12 ブランチの統合と iOS 初回ビルド・テスト実行

- 日時: 2026-09-04
- 状態: done（統合ツリーの 5 検証コマンドが全て exit 0。実機項目は従来どおり未検証）
- ブランチ / コミット: `integration` / 前セッション 2839e99〜df302ce（統合修正 5 件）+ 本セッション 00cd8b4, d996e45, 9ac4fed
- 統合済みブランチ（`git branch --merged integration`）: task/001-bootstrap, 003-fm-probe, 004-speech-spike, 005-flows, 006-data, 007-audio, 008-session-vm, 009-notification-core, 009-notification-app, 014-saydo-ai, 019-data-export, 023-alarm-spike（12 本。未統合 0）

### 環境の変化

iOS 26.3.1 シミュレータランタイム（23D8133）が導入済み（`xcrun simctl runtime list` = Ready、空き容量 17 GiB）。
task_001 以来のブロッカーが解消し、`build-ios.sh` は本来の `generic/platform=iOS Simulator` 経路、`test-ios.sh` は iPhone 17 / iOS 26.3 で実行できた。**iOS ターゲットのビルド成功とアプリ側テストの実行は本プロジェクトで初**。

### 本セッションの修正

| コミット | 内容 | 出どころ |
|---|---|---|
| 00cd8b4 | fm-probe の `call<Value: Generable & Sendable>` と `@MainActor func line()`（Swift 6）。AppSettingsTests の `TimeOfDay` 曖昧性を `Saydo.` で明示 | 前セッションの未コミット差分。本セッションで検証してコミット |
| d996e45 | lint の日本語リテラル除外を `*Copy.swift` に一般化（InsightCopy の 11 件 WARN 解消）。CLAUDE.md の「環境制約・未解消」を「環境の履歴」に書き換え | task_009-core 引き継ぎ (4) |
| 9ac4fed | `NotificationPlan` 規則 3(b) を `now < plannedAt` から `noonFireDate < plannedAt` に変更。テスト 2 件追加（190 → 192） | task_009-core 引き継ぎ (1)。宣言直後の再計画で当日の昼通知が必ず消え、行動時刻通知を見送った人に「どうだった？」が届かない不具合 |

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/test-core.sh`（修正前） | 0（SaydoCore 190 / SaydoAI 33 / lint OK） | `docs/logs/integration-1-test-core.txt` |
| `scripts/build-mac.sh fm-probe` | 0 | `docs/logs/integration-2-build-mac-fm-probe.txt` |
| `scripts/build-ios.sh`（Saydo） | **0**（本来の destination 経路。フォールバック無し） | `docs/logs/integration-3-build-ios-saydo.txt` |
| `scripts/test-ios.sh`（修正前） | 0（SaydoTests 89 / lint OK） | `docs/logs/integration-4-test-ios.txt` |
| `scripts/build-ios.sh SpeechSpike` | 0 | `docs/logs/integration-5-build-ios-speechspike.txt` |
| `scripts/build-ios.sh AlarmSpike` | 0 | `docs/logs/integration-6-build-ios-alarmspike.txt` |
| `scripts/test-core.sh`（昼通知修正後） | 0（SaydoCore **192** / SaydoAI 33 / lint OK） | `docs/logs/integration-7-test-core-after-noon-fix.txt` |
| `scripts/test-ios.sh`（最終ツリー 9ac4fed） | 0（SaydoTests 89 / lint OK） | `docs/logs/integration-8-test-ios-final.txt` |

スイート別件数（iOS、最終）: AppSettings 7 / AudioFileStore 8 / DataExporter 11 / DeepLink 18 / Repository 17 / SessionViewModel 14 / SilenceDetector 13 / Smoke 1 = 89。
スイート別件数（SaydoCore、最終）: DialogueCopy 15 / Domain 15 / Guardrails 13 / InsightCalculator 15 / JapaneseTimeParser 16 / MorningFlow 23 / NightFlow 12 / NoonFlow 23 / NotificationCopy 9 / NotificationPlan 25 / ShrinkLadder 9 / TemplateDialogueEngine 17 = 192。
SaydoAI 33 件のうち `FoundationModelsDialogueEngineIntegrationTests` 2 件は本機の Apple Intelligence で実走（スキップ 0）。

`scripts/build-ios.sh`（末尾）:

```
build-ios: scheme=Saydo
2026-09-04 10:29:45.479 appintentsmetadataprocessor[36684:14492243] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
** BUILD SUCCEEDED **
```

`scripts/test-ios.sh`（最終、末尾）:

```
test-ios: scheme=Saydo device=iPhone 17 runtime=com.apple.CoreSimulator.SimRuntime.iOS-26-3 udid=9D2D913B-5C7B-4969-B86C-C69CDFE434E2
	 Executed 89 tests, with 0 failures (0 unexpected) in 0.576 (0.890) seconds
	 Executed 89 tests, with 0 failures (0 unexpected) in 0.576 (0.891) seconds
** TEST SUCCEEDED **
lint-principles: 対象 49 ファイル（App/ と Packages/*/Sources。Tests と Spikes は除外）
lint-principles: OK
```

`scripts/test-core.sh`（最終、末尾）:

```
	 Executed 192 tests, with 0 failures (0 unexpected) in 0.036 (0.043) seconds
	 Executed 192 tests, with 0 failures (0 unexpected) in 0.036 (0.044) seconds
	 Executed 33 tests, with 0 failures (0 unexpected) in 12.717 (12.720) seconds
	 Executed 33 tests, with 0 failures (0 unexpected) in 12.717 (12.720) seconds
lint-principles: 対象 49 ファイル（App/ と Packages/*/Sources。Tests と Spikes は除外）
lint-principles: OK
```

### 未解決（統合で確認したが手を付けていない引き継ぎ事項）

- **main へのマージは未実施。** `integration` は main から 34 コミット先行（main 側の追加 0）。マージは人間の判断（下記）。
- task_009-app: Time Sensitive エンタイトルメントが project.yml に無い。通知アクション「今は話せない」（60 分後に再登録）は NotificationCopy に定数が無く未実装。AppRouter の SessionLauncher 配線は task_010/011 で。
- task_008: `Commitment.plannedPlace` が無い（§10 との不一致）。文言バリエーション履歴（R5）が永続化されていない。SessionLog の読み書きを Repository へ移す。
- task_006: `weekendNotificationsEnabled` の既定 true、`aloneTime` 既定 nil の解釈は未判断のまま。
- task_003 / 014: M1 を「理由分類」と「追加質問」の 2 呼び出しに分割する設計変更は task_015 で。
- lint WARN が残る箇所: 列挙型の `displayName`（FlowStep / ReasonCategory / SessionType / TaskDomain）、Flow のチップ文言（MorningFlow / NightFlow / NoonFlow）、TemplateDialogueEngine の週次テンプレート。これらを Copy に移すかは方針判断（exit code には影響しない）。
- task_005 の copy-audit Workflow は未実行。
- iOS 実行で `failed to create instance for plugin for <CFUUID ...>` がテスト起動時に 2 行出る。シミュレータ側の既知ノイズで、テスト結果には影響していない。

### 人間の確認待ち

1. `integration` を main にマージするかの判断（本セッションは `integration` の push まで。main は触っていない）。
2. 実機検証（音声 10 項目、AlarmKit 6 項目、fm-probe 人手採点 20 件）。従来どおり未実施。
3. task_006 / 008 の設計判断 4 点（週末通知の既定、aloneTime、plannedPlace、文言履歴の永続化）。

---

## task_009-residual — Time Sensitive エンタイトルメントと「今は話せない」

- 日時: 2026-09-04
- 状態: done（設計判断 D5 / D6 の実装。3 検証コマンドが exit 0。実機での長押しアクション・60 分後の再通知・Time Sensitive の実効は未検証）
- ブランチ / コミット: `task/009-residual`（`integration` の 1042720 から分岐） / （このコミット）
- 対象: `docs/review/integration-decisions-2026-09-04.md` の D5・D6、task_009 scope 末尾の「今は話せない」、fix-decisions P3.5

### 作ったもの

| ファイル | 内容 |
|---|---|
| `project.yml` | Saydo ターゲットに `entitlements`（`path: App/Saydo.entitlements` + `properties`）を追加。`com.apple.developer.usernotifications.time-sensitive: true`（D5） |
| `App/Saydo.entitlements` | XcodeGen の生成物。`properties` から作られたものをそのままコミットした（`.gitignore` が除外するのは `*.xcodeproj` などで、`*.entitlements` は対象外） |
| `Packages/SaydoCore/.../NotificationCopy.swift` | `busyNowActionIdentifier` = `"saydo.notification.action.busyNow"`、`busyNowActionTitle` = 「今は話せない」、`actionTitles`（通知に並ぶ順。今は話せない → 今日は休む）。`allTexts` を `actionTitles` 経由に変更 |
| `Packages/SaydoCore/.../NotificationPlan.swift` | `snoozeInterval`（60 分）、`maxSnoozesPerDay`（2）、`snoozeIdentifier(base:attempt:)`、`snoozeAttempt(in:)`、`baseIdentifier(of:)`、`nextSnoozeAttempt(base:pending:)`。`copyKey(for:day:calendar:)` を private → public（再登録時に元の `copyKey` が読めなかったときの拠り所） |
| `App/Notifications/DeepLink.swift` | `DeepLink.Action.snooze` を追加。`action(forActionIdentifier:)` が `busyNowActionIdentifier` を `.snooze` に写す |
| `App/Notifications/NotificationScheduler.swift` | `registerCategories()` にアクション 2 つ（`busyNow` → `restToday` の順）。`snooze(_:now:) async -> String?` を追加。`NotificationIdentifier.matches(dayStamp:identifier:)` が `-snooze<n>` を外してから日付印を比べるように変更 |
| `App/AppDelegate.swift` | `handle(_:)` に `.snooze` 分岐。`scheduler.snooze(link)` を呼んで **return**（launcher に渡さない・フローを開かない・`Commitment` に触らない） |
| テスト | `NotificationPlanTests` +12（25 → 37）、`NotificationCopyTests` +4（9 → 13）、`DeepLinkTests` +5（18 → 23） |

### 実装の決定

- **識別子は `<枠>-yyyyMMdd-snooze<n>`**。接頭辞が元のままなので `NotificationIdentifier.isManaged` にそのまま掛かり、再計画（`removeAllManagedPending`）と全削除（task_013 の `removeAllManagedPending`）で一緒に消える。日付印の判定だけは接尾辞を外す必要があったので `matches(dayStamp:identifier:)` を `NotificationPlan.baseIdentifier(of:)` 経由に変えた。これで「今日は休む」がずらした通知も一緒に取り消す。
- **上限の数え方は `pending` の最大 attempt + 1**。snooze1 が発火して保留から消えたあとでも snooze2 が残っていれば 3 回目は登録しない（`testSnoozeLimitCountsTheHighestAttemptEvenIfEarlierOnesAlreadyFired`）。base が違う識別子（他の枠・他の日・SAYDO 以外）は数に入れない。
- **上限に達したときは黙って登録しない**。「もう使えません」のような文言を出さない（企画原則 §22-1・§22-8）。`logger.info("snooze declined: ...")` だけを残す。
- **content の組み立ては `apply` と同じ経路**。`snooze` は `NotificationRegistration` を作って既存の `add(_:commitmentID:)` に渡すだけで、本文・`userInfo`・`interruptionLevel` の分岐を複製していない。`interruptionLevel` は元と同じ枠を渡すので `slot == .action` のときだけ `.timeSensitive` になる。
- **`PendingDiagnostics.logLine` は変更不要だった**。`countsBySlot` は `identifier.hasPrefix("\(slot.rawValue)-")` で数えるので `noon-20260904-snooze1` は `noon` に入り、`managedCount` にも入る。実測ログの `managed=` と `noon=` に再登録ぶんが含まれることをコードで確認した（`NotificationScheduler.swift` の `PendingDiagnostics.init(requests:)`）。
- **`Commitment` には触っていない**。`.snooze` は `AppDelegate` で return するので `SessionLauncher` にも渡らない。
## task_013 — オンボーディング・設定（+ task_019 の UI）

- 日時: 2026-09-04
- 状態: done（`scripts/build-ios.sh` と `scripts/test-ios.sh` が exit 0。実機項目とオンボーディングの初回体験は未検証）
- ブランチ: `task/013-onboarding-settings`（`integration` の 1042720 から分岐。第 2 波エージェント C）

### 作ったもの

| 変更 | 内容 |
|---|---|
| `App/Data/AppSettings.swift`（追加のみ） | 「話せない時を自動で使う時間帯」= `quietModeScheduleEnabled`（既定 false）/ `quietModeStart`（既定 9:00）/ `quietModeEnd`（既定 18:00）/ `isQuietMode(at:calendar:)`。`Key.all` に 3 キーを追加（`reset()` の対象に入る）。橋渡しとして `TimeOfDay.core` / `TimeOfDay.init(date:calendar:)` / `TimeOfDay.date(on:calendar:)` / `NotificationMode.core` / `AppSettings.notificationSettings`（`SaydoCore.NotificationSettings` へ変換）。既存のキーと既定値は変えていない |
| `App/Features/Onboarding/OnboardingCopy.swift`（新規） | オンボーディングの全文言 |
| `App/Features/Onboarding/PermissionsViewModel.swift`（新規） | `@MainActor @Observable`。マイク（`AVAudioApplication.shared.recordPermission` / `AVAudioApplication.requestRecordPermission()`）と通知（`NotificationScheduler.requestAuthorization()` / `authorizationStatus()`）の状態・要求・設定アプリへの導線 |
| `App/Features/Onboarding/AssetDownloadView.swift`（新規） | ja-JP の聞き取りアセットの状態と進捗、読み上げ音声の品質と追加手順 |
| `App/Features/Onboarding/OnboardingView.swift`（新規） | 7 段階（コンセプト → マイク → 通知 → 回数と時刻 → 一人で話せる時間 → 音声 → バックアップ注意）。`init(settings:onFinished:)`。完了で `hasCompletedOnboarding = true` → `NotificationScheduler.shared.reschedule(settings:)` → `onFinished()`。`OnboardingPrimaryButtonStyle` / `OnboardingSecondaryButtonStyle` も同ファイル |
| `App/Features/Settings/SettingsCopy.swift`（新規） | 設定画面の全文言と数値の書式 |
| `App/Features/Settings/SettingsView.swift`（新規） | 通知時刻・3 回モード・週末オフ・一人で話せる時間・TTS 音声選択・無音秒数・「話せない時」の時間帯・バックアップ注意・書き出し（`DataExporter.export()` + `ShareLink`）・全削除（確認ダイアログ → `Repository.deleteAll` → `AppSettings.reset()`）・開発者向け節。`init(settings:onDataDeleted:)` |
| `App/Data/Repository+Developer.swift`（新規） | `Repository.DeveloperStats` / `SessionCount` と `developerStats(now:windowDays:calendar:)`。`Repository.swift` 本体は触っていない |
| `Tests/SaydoTests/AppSettingsTests.swift`（追加のみ） | 6 件追加（既定値・境界・日跨ぎ・幅 0・往復と reset・`notificationSettings` 変換）。7 → 13 件 |

**触っていない**: `App/SaydoApp.swift`、`App/AppRouter.swift`（未作成）、`App/RootView.swift`（未作成）、`App/Features/Session/*`、`App/Notifications/*`、`App/Audio/*`、`project.yml`、`Packages/*`。`Saydo.xcodeproj` は生成物なのでコミットしない。

### 設計

- **`AppSettings` は `@Observable` ではない**（`UserDefaults` の薄い包み）。画面は複製（`SettingsView.Draft` / `OnboardingView` の `@State`）を持ち、`onChange` でまとめて書き戻す。通知に関わる値が変わったときだけ `reschedule` を呼び、時刻の輪を回している間に 30 件超の登録を繰り返さないよう 400 ms 遅らせて最後の 1 回だけ実行する。
- **`isQuietMode` の境界**: 開始と同じ時刻は含み、終了と同じ時刻は含まない。終了が開始より前なら日跨ぎ（22:00–6:00 なら 23:00 も 5:00 も中）。開始と終了が同じなら幅 0 として常に false。純計算部分は `AppSettings.isWithin(minutesFromMidnight:start:end:)` に切り出してテストしている。
- **ja-JP アセットの取得**（AssetDownloadView の根拠。読んだ API 名）: `TranscriptionService.prepare()` が `SpeechTranscriber.supportedLocales` / `installedLocales` を見て、無ければ `AssetInventory.assetInstallationRequest(supporting:)` → `downloadAndInstall()` まで行う。取得だけを始める API は無いので、`prepare()` を呼ぶことが「取得を始める手段」になる。進捗は `TranscriptionService.assetState`（`TranscriptionAssetState` = `.unknown` / `.unsupported` / `.installed` / `.downloading(Double)`）を読む。
- **読み上げ音声**: `SpeechSynthesisService.preferredJapaneseVoice()` と `SynthesisVoiceQuality` で品質を判定する。`AVSpeechSynthesisVoice` に enhanced / premium をアプリから取得する API は無いので、設定アプリでの手順を示すだけにした（fix-decisions P5.8）。
- **全削除の順序**: `Repository.deleteAll(cancelPendingNotifications:)` のコールバックで `NotificationScheduler.shared.removeAllManagedPending()` を起こし、戻ってから `AppSettings.reset()` → `onDataDeleted()`。コールバックは同期・`@Sendable` なので `Task { await … }` で MainActor へ渡している（待ち合わせはしていない。取り消しと保存データの削除は互いに独立）。
- **開発者向け節は `weeklyStats` に混ぜない**（fix-decisions P2.2）。`Repository+Developer.swift` の別メソッドにした。
## task_012 — Voice Timeline

- 日時: 2026-09-04
- 状態: done（`scripts/build-ios.sh` と `scripts/test-ios.sh` が exit 0。Instruments 計測と実機のレイアウト確認は未検証）
- ブランチ: `task/012-timeline`（`integration` の 1042720 から分岐。第 2 波エージェント B）
- 担当範囲: 画面部品のみ。TabView の導入と `RootView` への組み込みはエージェント A / 統合セッションの担当
## task_010 / task_011 — 昼・夜フローの配線と PlaybackCard / Today

- 日時: 2026-09-04
- 状態: wip（5 検証コマンドのうち走らせた 3 本が exit 0。実機・TestFlight #1 は未実施。昼の入口 `partial` は SaydoCore 側の 1 行が要るため未実装＝下の「統合時の継ぎ目」1 番）
- ブランチ / コミット: `task/010-noon-night`（`integration` の 1042720 から分岐。worktree `.worktrees/w2-F-010`）
- 担当: 第 2 波エージェント F（`docs/review/integration-decisions-2026-09-04.md` §B の表）

### 作ったもの

| ファイル | 中身 |
|---|---|
| `App/Features/Timeline/TimelineGrouping.swift` | `DaySection`（`id` = `date` = 日の開始時刻、`entries`）と `TimelineGrouping.sections(from:calendar:)`。`recordedAt` で日ごとに束ね、**記録がある日だけ**を新しい日から返す。セクション内は時刻の昇順 |
| `App/Features/Timeline/TimelineView.swift` | 記録タブ。`ScrollView` + `LazyVStack`、上部に `topAccessory`（統合時に `InsightCardView` が入る差し込み口）、日付セクション（`.sectionLabel`）、空状態 1 文。`@Query` で `VoiceEntry` を `recordedAt` 降順に全件取得し、並べ替えは必ず `TimelineGrouping` を通す |
| `App/Features/Timeline/VoiceEntryRow.swift` | ストロークのマイク（SF Symbols `mic`）+ 時刻（`.time`）+ 文字起こし（`.list` / `lineLimit(2)`）+ 32pt 再生ボタン。`audioPath == nil` の行は再生ボタンを出さない。再生中はマイク・時刻・文字起こし・再生グリフをアクセント色にする |
| `App/Features/Timeline/TimelinePlayback.swift` | `@MainActor @Observable`。`play(entry:)` / `stop()` / `nowPlayingID`。別の行を再生すると前を止める（同時再生の禁止）。`AudioFileStore.url(forRelativePath:)` で相対パスを解決し `Playing.play(_:preferReceiver: false)`。失敗は Logger に落として静かに止め、画面には何も出さない |
| `App/Features/Timeline/TimelineCopy.swift` | 空状態の 1 文「ここに、あなたの声が残っていく。」と再生ボタンの読み上げラベル。`*Copy.swift` なので lint の日本語リテラル警告の対象外 |
| `Tests/SaydoTests/TimelineGroupingTests.swift` | 3 日分（9/2 が 2 件、9/3 は「今日は休む」で 0 件、9/4 が 3 件・うち 1 件は `audioPath == nil`）の 6 件 |

### 設計上の判断（レビュー対象）

1. **`TimelineView` の init から `repository` を外した。** 指示の想定は `init(repository:player:topAccessory:)` だったが、
   `Repository` には日をまたいで全件を返す API が無く（`entries(for:)` は 1 日分）、`Repository.swift` は
   エージェント F の所有で触れない。実装計画 task_012 の implementation_steps も
   「`@Query` で `VoiceEntry` を `recordedAt` 降順に取得」と書いているため `@Query` を採った。
   `@Query` なら会話の直後に一覧が自動で更新される利点もある。
   現在の形は `init(player:audioFileStore:topAccessory:)` と、`Accessory == EmptyView` 版の
   `init(player:audioFileStore:)`（`audioFileStore` は既定 nil で、その場合 `AudioFileStore.applicationSupport()` を遅延で使う）。
2. **`commitment` を先読みする `FetchDescriptor` を使う。** `VoiceEntrySnapshot` は `commitmentID` を持つので
   1 行ごとにリレーションのフォールトが起きる。`relationshipKeyPathsForPrefetching = [\.commitment]` で
   まとめて取り、`commitmentID` に nil を入れて誤魔化すことはしていない。
3. **`TimelineLayout` / `TimelineQuery` を型の外に置いた。** `TimelineView` は総称型（`Accessory`）で、
   総称型の中には static な格納プロパティを置けない（初回ビルドがこれで落ちた）。
4. **`SaydoTheme` に無い寸法だけ画面側に置いた。** 色と文字階層は全て `SaydoTheme`。
   `Metric` に無い 32pt の再生ボタン・18×32 のマイク台座・レールの位置・画面余白は
   `VoiceEntryRow.Metric` と `TimelineLayout` に `docs/design/Timeline.dc.html` の値として置いた。
   `SaydoTheme.swift` は所有外なので変更していない。統合時に `Metric` へ移すかは判断待ち。
5. **再生ボタンは見た目 32pt・当たり判定 44pt。** design-notes の 32 を保ちつつ、タップ領域だけ広げた。
6. **「今日は休む」の日を消す分岐は書いていない。** `AppDelegate.handle(_:)` の通り `.rest` は
   当日の残りの保留通知を取り消すだけで `Commitment` も `VoiceEntry` も作らない。`@Query` は `VoiceEntry` を読むので、
   休んだ日はデータが無く、`TimelineGrouping` が記録のある日だけを返す結果として自然に現れない（R3 / R4）。
   `TimelineGroupingTests.testEmptyDayHasNoSection` がこれを固定している。
7. **`TimelineGroupingTests` で `Saydo.VoiceEntryKind` と明示した。** `SaydoCore` にも同名の `public enum` があり、
   `@testable import Saydo` と `import SaydoCore` の両方があるテスト側では曖昧になる（1 回目の test-ios がこれで落ちた）。
   アプリ側のコードでは自モジュールの型が優先されるので影響しない。

### 証拠

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/test-core.sh` | **0**（SaydoCore **208** / SaydoAI 33 / `lint-principles: OK`） | `docs/logs/task_009-residual-1.txt` |
| `scripts/build-ios.sh` | **0**（`generic/platform=iOS Simulator` の本来経路。フォールバック無し） | `docs/logs/task_009-residual-2.txt` |
| `scripts/test-ios.sh` | **0**（SaydoTests **94** / `lint-principles: OK`。iPhone 17 / iOS 26.3） | `docs/logs/task_009-residual-3.txt` |

`scripts/test-core.sh`（末尾）:

```
	 Executed 208 tests, with 0 failures (0 unexpected) in 0.036 (0.044) seconds
	 Executed 33 tests, with 0 failures (0 unexpected) in 18.280 (18.283) seconds
lint-principles: 対象 49 ファイル（App/ と Packages/*/Sources。Tests と Spikes は除外）
lint-principles: OK
EXIT=0
```
| `scripts/build-ios.sh` | **0** | `docs/logs/task_013-1.txt` |
| `scripts/test-ios.sh` | **0**（SaydoTests **95** / lint OK） | `docs/logs/task_013-2.txt` |
| `App/Data/CopyHistoryStore.swift`（新規） | **D2**。`protocol CopyHistoryStoring: Sendable`（`@MainActor`）と `UserDefaultsCopyHistoryStore`（JSON、`load(currentDay:)` が 3 日より古い記録を捨てる）。`UserDefaults` が非 Sendable なので `AppSettings` と同じく `@MainActor` 隔離で解決した（検査を外す属性は使っていない） |
| `App/Data/Models/Commitment.swift` | **D1**。`plannedPlace: String?` を追加（V1 のまま。配布済みビルド無し） |
| `App/Data/Repository.swift` | **D1**（`CommitmentSnapshot` / `CommitmentDraft` / `createCommitment` / `snapshot(of:)`）と **D8**（`startSessionLog` / `finishSessionLog` を `SessionViewModel.swift` の `extension Repository` からここへ移動。中身は 1 文字も変えていない） |
| `App/Features/Session/SessionViewModel.swift` | **D1 / D2 / D9 / R8**。下の「追加した公開 API」を参照 |
| `App/Features/Session/PlaybackCardView.swift`（新規） | 昼 N0 の画面。「朝のあなたからです。」（`.preface` / アクセント色）＋ `DeclarationRibbon`（design-notes の再生波形の式をそのまま実装。上下対称・再生済みはアクセント 3 層・未再生は `waveformIdle`・再生位置に 1.6px の縦線）＋宣言テキストを常に表示（声なしの日は `.question` の大きさ）＋「聞く」「耳に当てて聞く」。進捗バーは置いていない |
| `App/Features/Session/ListenModeSheet.swift`（新規） | R8 の確認。「イヤホンで聞く / 文字で読む」（塗り無し・高さ 46・ヘアライン区切り）。`onChoose: (ListenMode) -> Void` を受ける |
| `App/Features/Session/PlaybackCopy.swift`（新規） | 上 2 画面のボタン文言。`*Copy.swift` なので lint の日本語リテラル警告に出ない |
| `App/Features/Today/TodayView.swift`（新規） | ロゴ＋日付／「今日の約束」／宣言カード（行動文・`14:00・机で`・48px 再生ボタン。声なしなら再生ボタン無し）／通知の再許可導線／「今話す」64px ピル（宣言前 `.morning`・宣言後 `.adhoc`）／夜完了後は「今日はここまで」。一覧・チェックボックス・進捗率・連続日数は作っていない |
| `App/Features/Today/TodayCopy.swift`（新規） | Today 画面の文言 |
| `Tests/SaydoTests/SessionViewModelTests.swift` | 既存 14 件は**そのまま**（`testNightTomorrowBecomesNextMorningCarryover` の直接生成に `copyHistory: InMemoryCopyHistoryStore()` を足しただけ。`UserDefaults.standard` を汚さないため）。モック 3 種（`MockAudioSession` / `InMemoryCopyHistoryStore` / `MockPlayer.preferReceiverFlags`）とテスト 10 件を追加 |
| `Tests/SaydoTests/RepositoryTests.swift` | `plannedPlace` の保存・復元テスト 2 件 |

### `SessionViewModel` に追加した公開 API

```swift
enum ListenMode: String, Sendable, Equatable, Hashable, CaseIterable { case speaker, receiver, readText }

// init に 2 つ追加（どちらも既定値つき。既存の呼び出しは変えなくてよい）
init(..., audioFiles: AudioFileStore,
     audioSession: (any AudioSessionControlling)? = nil,
     copyHistory: any CopyHistoryStoring = UserDefaultsCopyHistoryStore(),
     timer: SessionTimer = .system, ...)

private(set) var listenModePrompt: Bool          // 立っている間は TTS も再生も始まっていない
private(set) var listenMode: ListenMode
private(set) var declarationDurationSec: Double  // 再生リボンの再生位置に使う
private(set) var declarationPlaybackStartedAt: Date?

func chooseListenMode(_ mode: ListenMode) async  // 止めてある命令列を流す
func replayDeclaration(preferReceiver: Bool = false) async  // PlaybackCard の 2 ボタン
```

R8 の止め方: `apply(_:)` が `.play(target: .declarationAudio)` を含む遷移を見つけ、`audioSession.requiresAudiblePlaybackConfirmation` が true なら **命令列を実行せずに退避** して `listenModePrompt` を立てる。`.speak(「朝のあなたからです。」)` はその命令列の 1 つ目なので、TTS も再生も始まらない。`.readText` を選ぶと `.speak` を飛ばし、`declarationTextToShow` に宣言テキストを載せて N1 へ進む。声なしの日は `.play(target: .declarationText)` なので確認そのものが出ない。

### 証拠

| コマンド | exit code | 結果 | ログ |
|---|---|---|---|
| `scripts/build-ios.sh` | **0** | `** BUILD SUCCEEDED **`。新規の warning 0 件（残る 1 件は既存の `DataExporter.swift:308`） | `docs/logs/task_010-1-build-ios.txt` |
| `scripts/test-ios.sh` | **0** | `Executed 101 tests, with 0 failures`（89 → 101）。lint OK | `docs/logs/task_010-2-test-ios.txt` |
| `scripts/test-core.sh` | **0** | SaydoCore 192 / SaydoAI 33、いずれも 0 failures。lint OK | `docs/logs/task_010-3-test-core.txt` |
| `scripts/build-mac.sh fm-probe` | 未実行 | task_010 / 011 の verify_commands に無い | — |

スイート別件数（iOS）: AppSettings 7 / AudioFileStore 8 / DataExporter 11 / DeepLink 18 / **Repository 19（17 → +2）** / **SessionViewModel 24（14 → +10）** / SilenceDetector 13 / Smoke 1 = 101。

`scripts/build-ios.sh`（末尾）:

```
Touch .../Build/Products/Debug-iphonesimulator/Saydo.app (in target 'Saydo' from project 'Saydo')
** BUILD SUCCEEDED **
EXIT=0
```

`scripts/test-ios.sh`（先頭と末尾）:

```
test-ios: scheme=Saydo device=iPhone 17 runtime=com.apple.CoreSimulator.SimRuntime.iOS-26-3 udid=9D2D913B-5C7B-4969-B86C-C69CDFE434E2
	 Executed 94 tests, with 0 failures (0 unexpected) in 0.256 (0.334) seconds
** TEST SUCCEEDED **
lint-principles: OK
EXIT=0
```

スイート別件数（SaydoTests、94）: AppSettings 7 / AudioFileStore 8 / DataExporter 11 / **DeepLink 23** / Repository 17 / SessionViewModel 14 / SilenceDetector 13 / Smoke 1。
SaydoCore の増分: NotificationPlan 25 → **37**、NotificationCopy 9 → **13**（192 → 208）。

生成された `App/Saydo.entitlements`:

```xml
<dict>
	<key>com.apple.developer.usernotifications.time-sensitive</key>
	<true/>
</dict>
```

`Saydo.xcodeproj/project.pbxproj`（生成物・非コミット）に `CODE_SIGN_ENTITLEMENTS = App/Saydo.entitlements;` が Debug / Release の両方に入り、`Saydo.app` の中にはコピーされていない（バンドル内容を `ls` で確認）。

lint の日本語リテラル WARN は **118 行のまま**（`integration-7-test-core-after-noon-fix.txt` と同数）。増やしていない。

### 既知の警告（本タスクの差分ではない）

`scripts/build-ios.sh` のフルビルドで `App/Features/Settings/DataExporter.swift:308:24: warning: use of protocol 'Error' as a type must be written 'any Error'` が 1 件出る。
出どころは task_019-core（`8a12578`）の `var copyError: Error?` で、本タスクの所有ファイルではないため直していない。
integration の `integration-3-build-ios-saydo.txt` は増分ビルドで当該ファイルを再コンパイルしておらず、この警告が記録されていなかった。

### task_009 done_definition との対応

| done_definition | 状態 | 根拠 |
|---|---|---|
| 実機で既定の 2 通知が届き、3 回モードで昼・夜も届く。タップでフローが自動開始 | **未検証**（実機） | 本タスクの範囲外（task_009-app の引き継ぎのまま） |
| pending に日数分の非繰り返しトリガーが登録され、当日分だけをスキップできる | **未検証**（実機） | 同上 |
| 通知の長押しから「今日は休む」が選べ、休んだ日が Timeline に出ない | **未検証**（実機） | カテゴリ登録のコードはあるが実機で長押ししていない |
| 通知許可が拒否・失効した状態で起動すると Today に再許可の導線が出る | 未着手（C / F の担当） | `NotificationHealth.needsAttention` は既にある |
| 行動時刻通知が朝の宣言後に `.timeSensitive` で登録される | コードは **done**、実効は **未検証** | `content.interruptionLevel = registration.slot == .action ? .timeSensitive : .active`（既存）＋ 本タスクでエンタイトルメントを追加 |
| `NotificationPlanTests` が緑で、全通知文言が Guardrails を通過する | **done** | `test-core.sh` exit 0。`testNoNotificationTextViolatesGuardrails` が `allTexts`（本文 6 + アクション 2）を、`testNoActionTitleViolatesGuardrails` が `actionTitles` を検査 |
| 「今は話せない」= 同じ通知を 60 分後に 1 件だけ再登録（同日 2 回まで）、Commitment に未達を記録しない | ロジックは **done**、実機は **未検証** | `NotificationPlanTests` の snooze 12 件、`DeepLinkTests` の snooze 5 件。`AppDelegate.handle` は `.snooze` で return |

### 未検証（人間・実機が必要）

- 通知を長押ししてアクションが「今は話せない」→「今日は休む」の順に 2 つ出ること。
- 「今は話せない」を選んだ 60 分後に同じ本文の通知が届くこと。3 回目を押しても増えないこと。
- Time Sensitive の実効（集中モード中に行動時刻通知が届くこと）。**シミュレータでは確認できない**。Apple Developer の App ID（`com.nonturn.saydo`）に **Time Sensitive Notifications** capability を付け、プロビジョニングプロファイルを作り直した実機ビルドが要る。capability を付けずに実機向けの自動署名でビルドすると、エンタイトルメント不一致で署名が通らないと見込んでいる（**本セッションでは未確認**。実機ビルドを行っていない）。`CODE_SIGNING_ALLOWED=NO` のシミュレータビルドには影響しないので、3 検証コマンドは exit 0 のままである（これは実測済み）。
- `PendingDiagnostics.logLine` の実測値（task_009 の「pending 上限を実機で記録する」）。再登録ぶんが `noon=` / `managed=` に乗ることはコードで確認したが、実機のログは未取得。

### 統合時の継ぎ目

1. **`AppRouter` が `.snooze` を無視すること**（エージェント A の所有）。`AppDelegate.handle` は `.snooze` で return するので `SessionLauncher.launch` に `.snooze` は到達しない。ただし `DeepLink.Action` に case が増えたので、`AppRouter` が `switch link.action` を網羅的に書いている場合はコンパイルエラーになる。`.open` 以外を無視する設計ならそのままで良い。**統合時に `AppRouter.launch` を目視確認すること**。
2. **再計画で保留中の再登録が消える**。`apply` → `removeAllManagedPending` は `-snooze<n>` も管理対象として消す。「今は話せない」を押した本人は 60 分以内にアプリを開かない想定なので通常は残るが、その間に別用でアプリを開いて `reschedule` が走ると、ずらした通知は消える。`removeAllManagedPending` を snooze だけ除外すると task_013 の「全削除」が snooze を消し残すため、**今回は消える側を選んだ**。挙動を変えるなら task_018 で判断する。
3. **日付をまたぐ再登録**。`snooze` の base は `now` の日付印で作るので、23:30 に押した通知の再登録は当日ぶん（`-yyyyMMdd-snooze1`）だが、翌 00:10 にもう一度押すと翌日の base（`snooze1`）になり、上限が日ごとにリセットされる。実装計画の「同日 2 回まで」の解釈としてこれを採った。
4. `NotificationCopy.actionTitles` は通知に並べる順（今は話せない → 今日は休む）を持つ。設定画面などで文言を再利用する場合はここから引く。

### 人間の確認待ち

1. Apple Developer の App ID `com.nonturn.saydo` に **Time Sensitive Notifications** capability を追加し、開発用プロビジョニングプロファイルを再発行する（実機ビルドの前に必要。Certificates, Identifiers & Profiles → Identifiers → com.nonturn.saydo → Time Sensitive Notifications にチェック → Profiles を再生成）。
2. 実機での通知長押し 2 アクション・60 分後の再通知・集中モード中の行動時刻通知の確認。
3. `App/Features/Settings/DataExporter.swift:308` の `Error?` → `(any Error)?`（本タスクの所有外。task_018 か task_019 の担当で直す）。
build-ios: scheme=Saydo
（中略）
2026-09-04 11:21:56.733 appintentsmetadataprocessor[12336:97562] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
** BUILD SUCCEEDED **
```

`scripts/test-ios.sh`（末尾）:

```
test-ios: scheme=Saydo device=iPhone 17 runtime=com.apple.CoreSimulator.SimRuntime.iOS-26-3 udid=9D2D913B-5C7B-4969-B86C-C69CDFE434E2
test-ios: 別の test-ios（pid=12356）が実行中。終わるまで待つ（lock=/var/folders/…/saydo-test-ios.lock）
Test Suite 'All tests' passed at 2026-09-04 11:22:42.130.
	 Executed 95 tests, with 0 failures (0 unexpected) in 0.410 (0.571) seconds
** TEST SUCCEEDED **
lint-principles: 対象 57 ファイル（App/ と Packages/*/Sources。Tests と Spikes は除外）
lint-principles: OK
```

スイート別件数: AppSettings **13**（+6）/ AudioFileStore 8 / DataExporter 11 / DeepLink 18 / Repository 17 / SessionViewModel 14 / SilenceDetector 13 / Smoke 1 = 95（統合時 89 から +6）。

- lint の WARN 行数は **118 行のまま**（本ブランチ着手前に同じツリーで計測した値と同数）。追加した 7 ファイルからの WARN は 0（`App/` 始まりの WARN 行なし）。
- ビルドの `warning:` は 3 件で、いずれも既存（`DataExporter.swift:308` の `any Error` 2 件と AppIntents のメタデータ 1 件）。追加分の警告なし。`@unchecked Sendable` / `nonisolated(unsafe)` は使っていない。

### done_definition との対応

task_013:

| done_definition | 状態 |
|---|---|
| 初回起動でオンボーディングが 1 回だけ表示される | **部品は満たした・配線は未**。`OnboardingView` の完了で `hasCompletedOnboarding = true` を書く（`AppSettingsTests` の往復テストで保存を確認）。`RootView` の分岐は A の担当で本ブランチには無いため、画面が 1 回だけ出ることは**未検証** |
| 2 回目以降、通知タップからノータップで会話が始まる | **未検証**（`AppRouter` / `SessionView` は A・F の担当。実機確認項目） |
| 設定で 3 回モード・週末オフ・『一人で話せる時間』を変更でき、変更が通知の再計画に反映される | **満たした**（`SettingsView` の該当行 → `AppSettings` へ保存 → `notificationSettings` を `NotificationScheduler.reschedule` へ渡す。変換は `testNotificationSettingsBridgeCarriesTheChosenValues` で確認。実機での pending 本数は未検証） |
| iCloud バックアップ無効時の注意文がオンボーディングと設定の両方にある | **満たした**（`OnboardingCopy.backupWarning` = 段階 7、`SettingsCopy.backupNotice` = データ節のフッタ） |
| phase-gate.js の実行結果が合格 | **未実施**。統合セッションが実行する（第 2 波の取り決め） |

task_019 の UI 部分:

| done_definition（UI に関わる分） | 状態 |
|---|---|
| zip に音声と JSON が含まれる | 中核は task_019 で確認済み。UI からは `DataExporter.export()` → `ShareLink(item: zipURL)` を繋いだ。**シミュレータ・実機での共有は未検証** |
| 全削除で空状態に戻る | `Repository.deleteAll` → `NotificationScheduler.removeAllManagedPending()` → `AppSettings.reset()` を繋いだ。`reset()` で `hasCompletedOnboarding` が false に戻ることは `testResetRestoresDefaults` で確認済み。**画面がオンボーディングへ戻ることは `RootView` 待ちで未検証** |
| 復元確認・容量実測 | 本タスクの範囲外（人間の実機作業。`docs/backup-restore-check.md`） |

### 開発者向け節に出せた値・出せなかった値

出せた（`Repository.developerStats`、直近 30 日）: 会話の完走率（全体と種別ごとの件数）、種別ごとの所要時間の中央値、宣言のあとの答えの内訳（`CommitmentOutcome` 別件数）、「もっと小さく」の平均回数、声を使わずに宣言した件数（`Commitment.isVoiceless`）、宣言が無かった日数。

出せなかった（記録が無いので画面に出していない）:

- **北極星指標**（3 日以内に「宣言 → 行動時刻通知タップ → やった / 少しやった」）。通知タップの記録が `SessionLog` にも `DeepLink` にも残らない。`SessionLog` に「どの通知から始まったか」を持たせないと出せない。
- **「今日は休む」の使用回数**。`NotificationScheduler.cancelRemainingToday` は呼ばれた記録を残さない（休みを `SessionLog` に残す実装は未着手。実装計画 §7.4 では「`SessionLog` にだけ休みとして残す」）。
- **R1 の「後で声で」の使用率**。宣言を後回しにしたことを表すフラグが `Commitment` に無い（`isVoiceless` は「声なしで宣言した」であって「後回しにした」ではない）。

### 未検証

- **実機・シミュレータで画面を 1 度も開いていない。** 検証はビルドとユニットテストのみ。オンボーディングの「初回だけ 2 つの権限ダイアログ」「2 回目以降ノータップ」は実機でしか確認できない。
- `ShareLink` での共有、`confirmationDialog` での全削除、`DatePicker` の連続変更で通知が再計画されること、`AssetDownloadView` の進捗表示（ja-JP アセットが未取得の端末が要る）は未確認。
- `AssetDownloadView` は `TranscriptionService.prepare()` を呼ぶ。シミュレータで `SpeechTranscriber` が ja-JP を持たない場合の分岐（`.unsupported` 表示）は実行していない。
- `phase-gate.js` は未実行（統合セッションの担当）。

### 統合時の継ぎ目

1. **`RootView` の分岐**: `AppSettings.shared.hasCompletedOnboarding == false` のとき `OnboardingView(onFinished:)` を出す。`onFinished` で自分の状態を更新して会話画面へ移る（`AppSettings` は `@Observable` ではないので、`RootView` 側に `@State` のフラグが要る）。
2. **「今日」右上の設定**: `.sheet { SettingsView(onDataDeleted:) }` で出す。`SettingsView` は自前で `NavigationStack` と「閉じる」を持つので、**外側で `NavigationStack` に包まない**。`onDataDeleted` で `hasCompletedOnboarding` を読み直し、オンボーディングへ戻す。
3. **`isQuietMode` の読み手**: `AppSettings.shared.isQuietMode(at: .now)` が true のセッションを、最初から選択肢 + テキスト経路で始める（TTS を文字表示 + 短いハプティクスに置換、マイクを自動で開かない）。読むのは `SessionViewModel` / `SessionView`（F / A の担当）。本ブランチは設定と判定だけを持ち、会話側は一切触っていない。
4. **TTS 音声の選択が効いていない**: `SettingsView` は `AppSettings.speechVoiceIdentifier` に保存するが、`SpeechSynthesisService.preferredJapaneseVoice()` は設定を読まず端末で最良の ja-JP 音声を選ぶ。`App/Audio/` は本ブランチの所有外なので直していない。**統合時に `preferredJapaneseVoice()` へ「保存された識別子があればそれを使う」を足す必要がある。** 足さない限り、設定画面の音声選択は表示だけで効かない。
5. **`OnboardingPrimaryButtonStyle` / `OnboardingSecondaryButtonStyle`** を `OnboardingView.swift` に置いた。A が `SessionView` 側で同じ役割のスタイルを作っている場合は、統合時にどちらかへ寄せる（名前は衝突しないようにしてある）。
6. `AppSettings.notificationSettings` が `AppSettings` → `SaydoCore.NotificationSettings` の唯一の変換口。起動時の再計画（A の `SaydoApp` / `AppRouter`）でもこれを使い、各画面で組み立て直さない。
7. `phase-gate.js` の実行は統合セッション。

### 人間の確認待ち

1. 実機で「初回だけマイクと通知の 2 ダイアログが出る」「2 回目以降はノータップで会話が始まる」を確認する（task_013 の done_definition 1・2）。
2. 実機で設定の時刻・3 回モード・週末オフを変えたあと、保留通知の本数と発火日が計画どおりかを `NotificationScheduler.logPendingDiagnostics()` の 1 行で確認する。
3. 実機で書き出しの `ShareLink` から zip を取り出し、全削除のあとオンボーディングに戻ることを確認する（task_019 の done_definition 2）。
4. ja-JP の読み上げ音声が enhanced / premium で入っていない端末で、設定アプリの手順どおりに追加できるかを確認する（fix-decisions P5.8、H6）。
| `scripts/build-ios.sh` | 0 | `docs/logs/task_012-1-build-ios.txt` |
| `scripts/test-ios.sh` | 0（SaydoTests **95** / lint OK） | `docs/logs/task_012-2-test-ios.txt` |
| （参考）レンダリングの一時確認 | 0（`ImageRenderer` 2 件） | `docs/logs/task_012-3-render-smoke.txt` |

スイート別件数（iOS）: AppSettings 7 / AudioFileStore 8 / DataExporter 11 / DeepLink 18 / Repository 17 /
SessionViewModel 14 / SilenceDetector 13 / Smoke 1 / **TimelineGrouping 6** = 95（`integration` の 89 から +6）。

`scripts/build-ios.sh`（末尾。全文は 30 行では収まらない 1 行が続くのでログを参照）:

```
ExtractAppIntentsMetadata (in target 'Saydo' from project 'Saydo')
2026-09-04 11:24:32.624 appintentsmetadataprocessor[14951:122276] warning: Metadata extraction skipped. No AppIntents.framework dependency found.
CopySwiftLibs .../Saydo.app (in target 'Saydo' from project 'Saydo')
Validate .../Saydo.app (in target 'Saydo' from project 'Saydo')
** BUILD SUCCEEDED **
```

`scripts/test-ios.sh`（テスト結果と lint の要点。末尾 30 行は既存 WARN の列挙が続くのでログを参照）:

```
test-ios: scheme=Saydo device=iPhone 17 runtime=com.apple.CoreSimulator.SimRuntime.iOS-26-3 udid=9D2D913B-5C7B-4969-B86C-C69CDFE434E2
Test Suite 'TimelineGroupingTests' passed at 2026-09-04 11:23:52.986.
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.018 (0.021) seconds
	 Executed 95 tests, with 0 failures (0 unexpected) in 0.436 (0.505) seconds
	 Executed 95 tests, with 0 failures (0 unexpected) in 0.436 (0.506) seconds
** TEST SUCCEEDED **
lint-principles: 対象 55 ファイル（App/ と Packages/*/Sources。Tests と Spikes は除外）
WARN: *Copy.swift 以外に日本語の文字列リテラルがある（文言は Copy に集約する）
（列挙 118 件。すべて Packages/SaydoCore と Packages/SaydoAI。App/Features/Timeline からは 0 件）
lint-principles: OK
```

lint の WARN は **118 件で `integration`（`docs/logs/integration-9-test-ios-theme-lock.txt`）と同数**。
新しく増やしていない。`@unchecked Sendable` / `nonisolated(unsafe)` / `URLSession` / `import Network` は追加していない。
自作の 5 ファイルからのコンパイラ警告は 0 件（`grep -c 'Features/Timeline.*warning:'` = 0）。

参考として、コミットしていない一時テスト（`ImageRenderer` で `TimelineView` を実際にレイアウトさせるだけのもの）を
1 回だけ流し、記録あり（2 日 × 3 件）と空状態のどちらも例外なく描けることを確認した（`Executed 2 tests, with 0 failures`）。
確認後にファイルは削除したので、`task_012-3-render-smoke.txt` は現ツリーには無いテストの記録である点に注意。

### done_definition との対応

| done_definition | 状態 | 根拠 |
|---|---|---|
| 当日の全エントリが時刻順に表示され再生できる | **一部検証** | 並び順は `TimelineGroupingTests.testEntriesWithinSectionAreOrderedByTime` で固定。再生は `TimelinePlayback` を書いたが、実際に音が鳴るところは未検証（実機・シミュレータでの操作が要る） |
| 7 日分 30 件で Instruments のフレーム落ち警告 0 件 | **未検証** | Instruments を回していない。`LazyVStack` + `commitment` の先読みまでが今回の手当て |
| 記録が無い日と「今日は休む」の日がセクションとして表示されない | **検証済み** | `testEmptyDayHasNoSection` / `testSectionsCoverOnlyRecordedDays`。根拠は上記「設計上の判断 6」 |
| 空状態に責める文言がない | **検証済み**（目視） | `TimelineCopy.empty` =「ここに、あなたの声が残っていく。」。`Guardrails.bannedPhrases`（未達成 / サボ / 怠け / 言い訳 / 甘え / なぜやらない / また逃げ）と `assertivePhrases`（失敗です 等）と「N 日連続」のいずれにも当たらない |
| （scope）TabView（今日 / 記録）の導入 | **担当外** | integration-decisions B の割り当てにより `RootView` はエージェント A の所有 |

### 未検証

1. **Instruments のフレーム落ち計測**（done_definition 2）。7 日分 30 件を投入した状態でのスクロール計測を行っていない。
2. **iPhone SE（4.7 インチ）× Dynamic Type xxxLarge のレイアウト確認**。文字は Dynamic Type で伸びるが、
   マイク台座（18×32）と再生ボタン（32pt）はグリフが潰れないよう固定サイズにしてある。
   xxxLarge で行の高さが伸びたときに縦レールが正しく伸びるかは実機で見ていない。
3. **実際の再生**。`.m4a` を持つエントリでの音の再生と、行を切り替えたときに前の再生が止まることを操作で確かめていない。
   `TimelinePlayback` の単体テストは書いていない（`Playing` の偽物を置く先が所有ファイルに無いため）。
4. **`topAccessory` に実物（`InsightCardView`）を入れた見た目**。エージェント E の成果物が未統合。

### 統合時の継ぎ目

1. **`RootView` の記録タブへの差し込み**。現在の init は次の 2 つ。

   ```swift
   TimelineView(player: player, audioFileStore: store) { InsightCardView(...) }   // 上部に差し込みあり
   TimelineView(player: player)                                                    // Accessory == EmptyView
   ```

   - `player` は `any Playing`（`VoicePlayer` をそのまま渡せる）。セッション側と同じインスタンスを共有してよい。
   - `audioFileStore` は省略可。省略すると `AudioFileStore.applicationSupport()` を遅延で使う。
   - `@Query` を使うので、`RootView` より上（`SaydoApp` の `.modelContainer(...)`）が既に入っている前提。
   - 画面は自前で `saydoGround()` を敷き、上部余白 62pt・左右 30pt を持つ。`NavigationStack` に入れる場合は
     二重の余白にならないか確認すること。
   - タブを離れると `onDisappear` で再生を止める。
2. **`topAccessory` の使い方**。ロゴ（SAYDO）の直下、最初の日付セクションの上に、左右 30pt の余白の内側で
   そのまま置かれる。差し込む側が自分で余白や区切りを持つ必要はない。データ不足のときは
   `EmptyView` を返してもらえば、`LazyVStack` の間隔だけが残る。
3. **`init` の引数が指示と違う**（設計上の判断 1）。`repository` は受け取らない。
   `RootView` 側が `Repository` を持っていても渡す必要はない。
4. **`VoiceEntry` → `VoiceEntrySnapshot` の変換が `Repository` と重複している**
   （`TimelineQuery.snapshot(of:)`）。`Repository` 側の同名メソッドが private なので画面側に置いた。
   統合で共通化するなら `Repository.swift`（F の所有）に internal な変換を出すのが素直。
5. **寸法定数**（設計上の判断 4）。`SaydoTheme.Metric` に 32pt / 44pt / 18pt を移すなら、
   `VoiceEntryRow.Metric` と `TimelineLayout` を差し替える。

### 人間の確認待ち

1. 実機（または Simulator）で記録タブを開き、(a) 7 日分 30 件のスクロールを Instruments で計測、
   (b) iPhone SE × xxxLarge でレールと行が崩れないか、(c) 行の再生と切り替えで音が正しく止まるか、を確認する。
   いずれも `RootView` に `TimelineView` が組み込まれてからでないと実行できない。
2. 空状態の文言「ここに、あなたの声が残っていく。」の採否。

### 環境メモ

`scripts/test-ios.sh` が 2 回、`Simulator device failed to launch com.nonturn.saydo.` /
`Application failed preflight checks` (`Busy`) で exit 65 になった。どちらもそのまま再実行すると exit 0 になった。
lock は test-ios 同士しか直列化しないため、他の worktree の `build-ios.sh` と重なるとシミュレータが取り合いになる可能性がある。
コードの失敗ではないが、他エージェントが同じ症状を見たときのために記録しておく。
    cd /Users/noritakasawada/AI_P/SAYDO/.worktrees/w2-F-010
    /usr/bin/touch -c .../Build/Products/Debug-iphonesimulator/Saydo.app

** BUILD SUCCEEDED **
```

`scripts/test-ios.sh`（抜粋。末尾 30 行は lint の既存 WARN 一覧なので、結果の行を引く）:

```
test-ios: scheme=Saydo device=iPhone 17 runtime=com.apple.CoreSimulator.SimRuntime.iOS-26-3 udid=9D2D913B-5C7B-4969-B86C-C69CDFE434E2
Test Suite 'RepositoryTests' passed at 2026-09-04 11:25:27.533.
	 Executed 19 tests, with 0 failures (0 unexpected) in 0.259 (0.266) seconds
Test Suite 'SessionViewModelTests' passed at 2026-09-04 11:25:27.632.
	 Executed 24 tests, with 0 failures (0 unexpected) in 0.088 (0.098) seconds
	 Executed 101 tests, with 0 failures (0 unexpected) in 0.547 (0.679) seconds
** TEST SUCCEEDED **
lint-principles: 対象 56 ファイル（App/ と Packages/*/Sources。Tests と Spikes は除外）
lint-principles: OK
```

lint の日本語リテラル WARN は 118 件で、**すべて `Packages/SaydoCore/Sources` 側の既存分**（D7 で今回は移さないと決めた列挙型の `displayName` と Flow のチップ文言）。`App/` からの WARN は 0 件で、追加した 5 ファイルは増やしていない（`grep '^    App/' docs/logs/task_010-2-test-ios.txt` が空）。

`scripts/test-core.sh`（結果の行）:

```
	 Executed 192 tests, with 0 failures (0 unexpected) in 0.086 (0.107) seconds
	 Executed 33 tests, with 0 failures (0 unexpected) in 22.409 (22.413) seconds
lint-principles: OK
```

### 追加したテスト 12 件

| テスト | 見ていること |
|---|---|
| `testPlannedPlaceIsSavedWithTheCommitment` | D1。「14時に自宅で」→ `Commitment.plannedPlace == "自宅"` |
| `testPlannedPlaceIsNilWhenNoPlaceWasSaid` | 場所を言わない日は nil（空文字を作らない） |
| `testCopyHistoryPersistsAcrossViewModels` | D2 / R5。ViewModel 2 つをまたいで同じ日に同じ文言が出ない |
| `testCopyHistoryDropsRecordsOlderThanThreeDays` | 3 日より古い記録を読み込み時に捨てる |
| `testListenModeIsAskedBeforeAnySoundStarts` | R8。確認が要る状況で `listenModePrompt` が立ち、`spokenLines` も `playedURLs` も空 |
| `testListenModeIsNotAskedWhenConfirmationIsNotRequired` | 要らない状況では尋ねずに鳴らす |
| `testReadTextModePlaysNothingAndShowsTheDeclaration` | 「文字で読む」で再生 0・「朝のあなたからです。」も読まない・宣言テキスト表示・N1 へ進む |
| `testReceiverModeRoutesToTheReceiverBeforePlaying` | 「耳に当てて聞く」で `applyOutputRoute(preferReceiver: true)` → `play(preferReceiver: true)` |
| `testVoicelessCommitmentShowsTextAndIsNeverAskedToChoose` | 声なしの日は確認も再生も無し。イントロだけ読み、本人の言葉は読み上げない |
| `testNoonRestoresTodaysActionAndPlaceFromTheCommitment` | D9。`plannedPlace` が戻り、N3 の促しに本人の言葉が入り、`shrinkCount` が 1 増える |
| `testPlannedTimeAndPlaceAreStoredAndReadBack`（Repository） | D1 の保存・復元 |
| `testPlannedPlaceStaysNilWhenItWasNotAsked`（Repository） | 同上（nil のまま） |

### done_definition の自己監査

#### task_010

| 条件 | 状況 | 根拠 |
|---|---|---|
| 行動時刻通知をタップすると宣言音声が再生され、その後の状態確認が完走する | ViewModel 側は済。**実機は未検証** | `testNoonStatusDoneEndsWithoutBlocker`（既存）と `testListenModeIsNotAskedWhenConfirmationIsNotRequired`。通知タップ → 画面表示は A の `AppRouter` / `SessionView` と合流してから |
| イヤホン未接続かつ `outputVolume` > 0.3 のとき、再生前に「イヤホンで聞く / 文字で読む」が出る | 済（判定は `AudioSessionController.requiresAudiblePlaybackConfirmation`。UI は `ListenModeSheet`） | `testListenModeIsAskedBeforeAnySoundStarts` / `testListenModeIsNotAskedWhenConfirmationIsNotRequired` |
| 声なし Commitment では宣言テキストが大きく表示され、TTS で読み上げない | 済 | `testVoicelessCommitmentShowsTextAndIsNeverAskedToChoose` と `PlaybackCardView.declarationText`（`declarationTextToShow != nil` のとき `.question` の大きさ） |
| 「まだ」で行動文が更新され `shrinkCount` が増える。「少しやった」は `partial` で終了 | 済 | `testNoonStatusNotYetGoesToBlockerAndShrink` / `testNoonStatusPartialIsTreatedAsProgress`（いずれも既存）＋ `testNoonRestoresTodaysActionAndPlaceFromTheCommitment` |
| `SessionViewModelTests` に昼フローの 3 分岐と入口 3 状態のテストがある | done / partial / notYet の 3 分岐と入口 3 状態は**ある**が、入口の「`partial` 済み」だけ**未実装**（継ぎ目 1） | 既存 6 件 + 追加分 |
| 昼フローの「まだ」経路で当日の `VoiceEntry` が 2 件（status / blocker）増える | 済 | `testNoonStatusNotYetGoesToBlockerAndShrink` が `status` 1 件・`blocker` 1 件を検証 |
| 昼フローが 1 分を超えない | 済（タイムボックス 60 秒は task_008 の実装） | `SessionViewModel.timebox(for:)`。実測は実機 |
| TestFlight 内部配布 #1 とビルド番号の記録 | **未実施**（人間の作業） | — |

#### task_011

| 条件 | 状況 | 根拠 |
|---|---|---|
| 実機で 夜 → 翌朝 の引き継ぎが動く | ロジックは済。**実機は未検証** | `testNightTomorrowBecomesNextMorningCarryover`（既存）。`persistCarryoverIfNeeded` は今回変更していない |
| E0 の前進なし分岐で表示されるチップが 2 つだけ | 済 | `testNightWithoutProgressShowsTwoChoices`（既存）が `[.shrinkMore, .moveToTomorrow]` を検証 |
| 夜の画面と発話に「未達成」「連続」が一切出ない | 済 | `GuardrailsTests`（SaydoCore 192 件に含まれる）が `DialogueCopy.allLines` を通す。今回足した `TodayCopy` / `PlaybackCopy` にも禁止句は無い（`Guardrails` の対象は生成文なので機械検査はしていない＝目視） |
| 引き継ぎのテストが緑 | 済 | 上記 |
| `AvoidanceItem.status` を夜の選択に応じて更新する（task_011 scope 3 番） | **未実装**。エージェント F の指示書の担当範囲（§7）に入っていない。`Repository` にも更新 API が無い | 継ぎ目 5 |

### 未検証

1. **実機**: 通知タップ → 宣言音声の再生、イヤホン未接続時の確認の出方、受話口 + 近接センサー、夜 → 翌朝の引き継ぎ。いずれも画面録画・実機が要る。
2. **TestFlight 内部配布 #1**（task_010 の done_definition 最後の 1 項目）。Archive と配布は人間の作業。
3. `PlaybackCardView` / `ListenModeSheet` / `TodayView` の**見た目**。コンパイルは通っているが、iPhone SE × Dynamic Type xxxLarge での収まりは実機・プレビュー未確認。
4. `DeclarationRibbon` の描画が版下（`docs/design/Playback.dc.html`）と一致するか。式は design-notes のとおりに写したが、目視での突き合わせは未実施。

### 統合時の継ぎ目

1. **【要判断】昼の入口が `partial` を拾わない**。計画 §7.2 の表と task_010 scope は「`outcome == done` **または** `partial`」で当日の `noon-yyyyMMdd` / `action-yyyyMMdd` を取り消して「今日はもう動けてる。」で終わる、と定めている。実装は `NoonFlow.entrance` が `entry.outcome == .done` だけを見ており、`partial` の日は N0 の再生からやり直しになる。直し方は `Packages/SaydoCore/Sources/SaydoCore/Flows/NoonFlow.swift` の 1 行を `if entry.outcome.isProgress { return .alreadyDone }` にし、`NoonFlowTests` の入口テスト（`Packages/SaydoCore/Tests/SaydoCoreTests/NoonFlowTests.swift:31` 付近）に `partial` の 1 行を足すだけ。**SaydoCore は F の所有ファイルではないので手を付けていない**。現行の `NoonFlowTests` は `partial → .playback` を assert していないので、この変更で落ちるテストは無い。
2. **`SessionView`（A）への差し込み**: `.playback` フェーズで `PlaybackCardView(viewModel: viewModel)`。R8 の確認は `viewModel.listenModePrompt` を見て `ListenModeSheet { mode in Task { await viewModel.chooseListenMode(mode) } }` を出す（`.sheet(isPresented:)` でも `.overlay` でもよい）。`listenModePrompt` が立っている間は `phase == .playback` で、発話も再生も始まっていない。
3. **`RootView`（A）への差し込み**: 「今日」タブに
   `TodayView(repository:player:notificationHealth:onStartSession:onOpenSettings:)`。
   `repository` は `Repository`（actor）、`player` は `VoicePlayer`、`notificationHealth` は `NotificationScheduler.health()` の結果（`nil` なら導線を出さない）、`onStartSession` は `AppRouter` の `SessionLauncher` に、`onOpenSettings` は `SettingsView`（C）に繋ぐ。`TodayView` は宣言音声の URL を自前の `AudioFileStore.applicationSupport()` で解決する。
4. **`AppRouter` / `SaydoApp`（A）**: `SessionViewModel` を作るところで `audioSession:` に `AudioSessionController` の実体を渡さないと R8 の確認は**出ない**（既定 nil = 確認しない）。`copyHistory:` は既定の `UserDefaultsCopyHistoryStore()` でよい。
5. **`AvoidanceItem.status` の更新**（task_011 scope 3 番）: 夜 E0 の `nightDecision`（`shrinkMore` / `moveToTomorrow`）と N3 の `dropToday` / `moveToTomorrow` に応じて `AvoidanceItem.status` を動かす処理がどこにも無い。`Repository` に更新メソッドを足すのが素直（`App/Data/Models/AvoidanceItem.swift` は F の所有外）。
6. **`App/Features/Session/PlaybackCopy.swift` を新規に足した**。指示書の作成リストには `TodayCopy.swift` しか無かったが、`PlaybackCardView` / `ListenModeSheet` のボタン文言を lint 対象外に置くため、integration-decisions §「検証と報告」の規約（画面専用の文言は `App/Features/<画面>/<画面>Copy.swift`）に従って作った。A が `SessionCopy.swift` を作っていても名前は衝突しない。
7. **design-notes との差**: `docs/design/design-notes.md` は N0 について「文字起こしは出さない（声を聴かせるため）」と書いているが、task_010 scope の最終項が「PlaybackCardView は宣言テキストを常に画面に表示し」と定めているので**後者に従った**（声なしの日だけ大きく出す、ではなく常に出す）。判断が要るなら統合時に。

### 人間の確認待ち

1. 継ぎ目 1（`NoonFlow.entrance` の `partial`）を第 2 波の統合で入れるか、task_018 に送るかの判断。
2. TestFlight 内部配布 #1（task_010 の done_definition）。Archive とビルド番号の記録。
3. 実機での R8 の確認（イヤホン未接続 × 音量 > 0.3 で本当に確認が出るか、受話口で鳴るか）と、昼 → 夜 → 翌朝の 1 日通しの動作。
