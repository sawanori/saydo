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
