# S-B / S-C: SpeechSpike（SpeechAnalyzer + 録音 + 無音停止 + TTS 半二重 + 起動時間）

- タスク: `task_004`（`docs/task-list.json`）
- 対応するリスク: 実装計画 §0.4 の S-B・S-C、§7.3 音声パイプライン
- 実装: `Spikes/SpeechSpike/`（`SpeechSpikeApp.swift` / `SpikeView.swift` / `SpikeAudio.swift`）
- 記入日: **（実機計測時に記入）**
- 計測者: **（記入）**
- 実機: **（機種 / iOS バージョン / Apple Intelligence 対応可否を記入）**

このファイルの「確認済み」節は **iOS 26.2 SDK に対してコンパイルが通った事実**だけを書いている。
認識精度・無音停止・起動時間の数値は**まだ 1 件も計測していない**。実機での計測は人間の作業で、
下の「実機での計測手順」に沿って記入する。

---

## 1. 実装した構成

```
起動 or 通知タップ
  → AVAudioSession を .playAndRecord で有効化
  → AVSpeechSynthesizer で「今日、何から逃げたい？」を発話（この間は入力タップを張らない = 半二重）
  → didFinish 後にマイク権限を確認し、SpeechTranscriber(ja-JP) の導入状況を確認
  → 未導入なら AssetInventory.assetInstallationRequest(supporting:) でダウンロード（進捗表示）
  → AVAudioEngine の入力ノードにタップを 1 つ設置（1 入力 3 消費）
       (a) AVAudioFile へ AAC 32 kbps で書き込み（.m4a）
       (b) AVAudioConverter で解析形式へ変換し AnalyzerInput(buffer:) を AsyncStream へ yield
       (c) RMS を計算して波形と無音判定へ
  → RMS が閾値未満のまま 1.5 秒（1.2 / 1.5 / 2.0 を画面で切替）続いたら停止
  → analyzer.finalizeAndFinishThroughEndOfInput() → 確定文字起こしを表示
  → 録音した .m4a を AVAudioPlayer で再生
```

### 並行性の設計（実装計画 §7.3 / fix-decisions P4.6）

- `installTap` のクロージャは `@Sendable`（= nonisolated）。**状態変更を一切行わない**。
  クロージャが捕捉するのは Sendable な値だけ:
  `AsyncStream.Continuation` 2 本、`AVAudioFile`、`AVAudioConverter`、`AVAudioFormat`
  （`AVAudioFile` / `AVAudioConverter` / `AVAudioFormat` は iOS 26.2 SDK で `NS_SWIFT_SENDABLE`）。
- 画面の状態（波形・無音の進み・文字起こし・ログ）は `@MainActor @Observable final class SpikeController` だけが持つ。
  タップからは `TapEvent`（RMS と継続時間）を `AsyncStream` で送り、無音判定は @MainActor 側で行う。
- `@unchecked Sendable` と `nonisolated(unsafe)` は**使っていない**（`grep` で 0 件。コメント中の言及のみ）。
- Swift 6 モード（`-swift-version 6` / `SWIFT_STRICT_CONCURRENCY: complete`）で **警告 0 件**。

#### 詰まった 1 点と回避（次タスク以降が必ず踏む）

`AVAudioConverterInputBlock` は SDK で `NS_SWIFT_SENDABLE` なので、
入力ブロックへ非 Sendable な `AVAudioPCMBuffer` を渡せない。さらに、
複製先バッファへ**ポインタ経由で直接 memcpy すると region 解析が複製元と同じ region と見なす**ため、

```
error: sending 'copy.some' risks causing data races
note: task-isolated 'copy.some' is passed as a 'sending' parameter
```

で落ちる。回避は 2 段:

1. 入力バッファを一度 `[[Float]]`（Sendable）へ写してから新しい `AVAudioPCMBuffer` へ書き戻す。
   これで複製が入力バッファの region から切り離される。
2. その複製を `Mutex<AVAudioPCMBuffer?>`（標準ライブラリが Sendable を保証する型）に入れ、
   入力ブロックからは 1 回だけ取り出す（2 回目以降は `.noDataNow`）。

コストは 1 バッファ（4096 フレーム × 4 バイト ≒ 16 KB）につき memcpy 2 回。
`Packages` 側ではなくアプリ側の `VoiceCapture`（task_007）でも同じ処理が要る。

---

## 2. 確認済み / 不在の API（iOS 26.2 SDK・Xcode 26.2 / 17C52）

根拠: `iPhoneSimulator26.2.sdk/System/Library/Frameworks/Speech.framework/Modules/Speech.swiftmodule/arm64-apple-ios-simulator.swiftinterface`
と、実際に `scripts/build-ios.sh SpeechSpike` が exit 0 になったこと。

### 使って通ったもの

| API | 形 |
|---|---|
| `SpeechTranscriber(locale:preset:)` | `convenience init(locale: Locale, preset: SpeechTranscriber.Preset)` |
| `SpeechTranscriber.Preset.timeIndexedProgressiveTranscription` | 静的プロパティ。ほかに `transcription` / `transcriptionWithAlternatives` / `timeIndexedTranscriptionWithAlternatives` / `progressiveTranscription` |
| `SpeechTranscriber.isAvailable` | `static var isAvailable: Bool` |
| `SpeechTranscriber.supportedLocales` | `static var ... : [Locale] { get async }` |
| `SpeechTranscriber.installedLocales` | `static var ... : [Locale] { get async }` |
| `SpeechTranscriber.supportedLocale(equivalentTo:)` | `static func ... async -> Locale?` |
| `SpeechTranscriber.Result` | `range` / `resultsFinalizationTime` / `text: AttributedString` / `alternatives` |
| `SpeechModuleResult.isFinal` | プロトコル拡張のプロパティ（`Result` に直接は無い） |
| `SpeechAnalyzer(modules:options:)` | `actor`。`options` は省略可 |
| `SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith:)` | `static func ... ([any SpeechModule]) async -> AVAudioFormat?` |
| `SpeechAnalyzer.prepareToAnalyze(in:)` | プリウォーム用。`async throws` |
| `SpeechAnalyzer.start(inputSequence:)` | `AsyncSequence<AnalyzerInput>` を渡してすぐ戻る |
| `SpeechAnalyzer.finalizeAndFinishThroughEndOfInput()` | `async throws`。**`finalizeAndFinish` は `finalizeAndFinish(through:)` の形でしか存在しない** |
| `AnalyzerInput(buffer:)` | `struct AnalyzerInput: @unchecked Sendable`。`init(buffer:bufferStartTime:)` もある |
| `AssetInventory.status(forModules:)` | `async -> AssetInventory.Status`（`unsupported` / `supported` / `downloading` / `installed`） |
| `AssetInventory.assetInstallationRequest(supporting:)` | `async throws -> AssetInstallationRequest?`（不要なら nil） |
| `AssetInstallationRequest.progress` / `.downloadAndInstall()` | `Foundation.Progress` と `async throws` |
| `AssetInventory.reservedLocales` / `.reserve(locale:)` / `.maximumReservedLocales` | ロケールの割り当て。未割り当てだと `SFSpeechError.Code.assetLocaleNotAllocated` がある |
| `AVAudioApplication.requestRecordPermission(completionHandler:)` | iOS 17 以降の形。`AVAudioSession.requestRecordPermission` は使わない |
| `AVAudioSession.CategoryOptions.allowBluetoothHFP` | 後述 |

### 不在を確認したもの

- **`AnalyzerInputConverter` は iOS 26.2 SDK に存在しない。**
  `Speech.swiftinterface` に該当シンボルは無く、SDK の `System/Library/Frameworks` 配下を
  `grep -rl AnalyzerInputConverter` しても 0 件。
  → 実装計画 §7.3 と fix-decisions P4.1 の前提どおり、`AVAudioConverter` + `AnalyzerInput(buffer:)` で供給した。
  iOS 27 以降で追加された場合は `convertForAnalyzer(_:using:to:)` と `InputBufferSource` だけを差し替えれば足りる。
- `SpeechDetector`（無音・発話検出モジュール）は存在する（`SpeechDetector(detectionOptions:reportResults:)`、
  `SensitivityLevel` は `.low` / `.medium` / `.high`）。今回は RMS で実装したが、
  実機で RMS の閾値調整が難しい場合は `SpeechAnalyzer` のモジュールとして併用する選択肢がある（**未検証**）。

---

## 3. AVAudioSession の設定

```swift
try session.setCategory(
    .playAndRecord,
    mode: .default,                        // 画面で .voiceChat に切替可能
    options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
)
try session.setActive(true)
```

- **Bluetooth オプションの iOS 26.2 SDK での正式名は `.allowBluetoothHFP`**。
  ヘッダ（`AVAudioSessionTypes.h`）で旧 `AVAudioSessionCategoryOptionAllowBluetooth` は
  `API_DEPRECATED_WITH_REPLACEMENT("AVAudioSessionCategoryOptionAllowBluetoothHFP", ios(1.0, 8.0))` になっている。
  Swift 名は `AVAudioSession.CategoryOptions.allowBluetoothHFP`。A2DP 側は従来どおり `.allowBluetoothA2DP`。
- `.voiceChat` モードは `.allowBluetoothHFP` が設定されていることを要求する（ヘッダの注記）。切替検証のため両方入れてある。
- 消音スイッチの尊重（実装計画 §7.3 / retention R8）は**このスパイクの対象外**。
  `.playAndRecord` は消音スイッチを無視して再生するため、本実装（task_007）では
  イヤホン未接続 + 消音 ON のときに「イヤホンで聞く / 文字で読む」を出す分岐が別途必要。

### 録音ファイル

```swift
[
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: inputFormat.sampleRate,        // 入力に合わせる
    AVNumberOfChannelsKey: Int(inputFormat.channelCount),
    AVEncoderBitRateKey: 32_000,
]
```

`AVAudioFile` の `processingFormat` と入力タップの形式を一致させるため、標本化周波数とチャンネル数は
入力ノードの `outputFormat(forBus: 0)` に合わせている（iPhone の内蔵マイクは 1 ch のはずだが、
**実機で 1 ch になることは未確認**。画面の「音声形式」節に実測値が出る）。

---

## 4. 実機での計測手順（**人間の作業**）

前提: iOS 26.x の実機。ビルドは Xcode で `SpeechSpike` スキームを選んで実機へ Run する
（シミュレータランタイム未導入のため、現在 CI 的な検証はコンパイルのみ）。

### 4-1. 起動時に見るもの

1. アプリを起動すると自動で「今日、何から逃げたい？」を読み上げる。
2. 画面の「SpeechTranscriber のロケール」節を確認して下表に記入する。
3. `installedLocales に ja = なし` の場合はモデルのダウンロードが走る（進捗バー）。所要時間を記入する。
4. **音声認識の権限ダイアログ（「音声認識へのアクセス」）が出ないこと**を確認する。出るのはマイクだけのはず。

| 項目 | 実測 |
|---|---|
| `SpeechTranscriber.isAvailable` | |
| `supportedLocales` に ja あり / なし | |
| `installedLocales` に ja あり / なし | |
| `supportedLocale(equivalentTo: ja-JP)` の戻り値 | |
| `AssetInventory.status` | |
| モデルのダウンロード有無と所要時間 | |
| 出た権限ダイアログ（種類と文言） | |
| 入力の形式（画面の「音声形式」節） | |
| 解析の形式（同上） | |
| TTS 音声の名前と品質（ログ行「TTS 音声: …」） | |

### 4-2. 認識精度（10 文）— S-B の基準 1

読み上げが終わってから、次の 10 文を 1 文ずつ話す（1 文ごとに「もう一度」を押して録り直す）。
確定した文字起こしが**意味の通る文**なら ○、意味が変わっていれば ×。**8 文以上で合格**。

| # | 話す文 | 文字起こし結果 | ○ / × |
|---|---|---|---|
| 1 | 見積書を出すのが面倒で、ずっと後回しにしている | | |
| 2 | クライアントへの返信を三日ためている | | |
| 3 | 確定申告の書類を open していない、じゃなくて開いていない | | |
| 4 | 歯医者の予約を取るのが怖い | | |
| 5 | 請求書のチェックが終わっていない | | |
| 6 | 上司に相談するのが気まずくて避けている | | |
| 7 | five 分だけやる、じゃなくて五分だけやる | | |
| 8 | 明日の朝いちばんに、机に資料を置くだけやる | | |
| 9 | 何から手をつければいいのか分からない | | |
| 10 | 今日はそういう日だった、明日もっと小さくする | | |

合計: **___ / 10**（8 以上で合格）

補足で見ておくこと（自由記述）:

- 途中経過（volatile）の表示が体感でどれくらい遅れるか:
- 固有名詞・カタカナ語の崩れ方:

### 4-3. 無音停止（10 回）— S-B の基準 2

無音の秒数を 1.5 秒にして、1 文話してから黙る、を 10 回。
「言い終わる前に切れた」「10 秒以上黙っても切れない」は誤作動。**誤作動 1 回以下で合格**。

| 秒数 | 試行 10 回のうち誤作動 | 体感 |
|---|---|---|
| 1.2 秒 | | |
| **1.5 秒（既定）** | | |
| 2.0 秒 | | |

- 採用する秒数: **___ 秒**
- RMS の閾値（コード上の初期値 0.015）を変えた場合の値と理由:
- 静かな部屋 / 雑音のある場所での差:

### 4-4. 通知タップ → TTS 開始（5 回）— S-B の基準 3 / S-C

1. 「10 秒後に通知」を押し、**アプリをホームに戻すか画面をロックする**。
2. 10 秒後の通知をタップする。
3. 画面の「通知タップ → TTS 開始（5 回）」に秒数が自動で記録される
   （`didReceive` で `Date()` を取り、`AVSpeechSynthesizerDelegate.didStart` までの差）。
4. 5 回繰り返す。**1.5 秒以内が 5 回中 4 回以上で合格**。

| 回 | 秒数 | 状態（コールドスタート / バックグラウンド復帰） |
|---|---|---|
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |

1.5 秒以内: **___ / 5**

- 1.5 秒を超えた回の内訳（アプリの起動そのものか、セッション有効化か、TTS の準備か）:

### 4-5. 半二重と回り込み

1. モードを `.default` にして、スピーカー再生のまま読み上げ → 聞き取り、を 3 回。
   読み上げた文言（「今日、何から逃げたい？」）が文字起こしに混入するか。
2. 混入する場合はモードを `.voiceChat` に切り替えて同じことを 3 回。

| モード | 回り込みの混入 | 音質・音量の変化 |
|---|---|---|
| `.default` | | |
| `.voiceChat` | | |

- 採用するモード: **___**

### 4-6. 録音ファイル

- 15 秒ほど話して停止したときの `.m4a` のサイズ: **___ KB**（実装計画 §10 の見積もりは 60 KB/15 秒）
- 再生の音質（自分の声として聞けるか）:

---

## 5. 判定（**実機計測後に記入**）

| S-B / S-C の基準 | 目標 | 実測 | 判定 |
|---|---|---|---|
| 10 文中の意味が通る文字起こし | 8 文以上 | | |
| 無音停止の誤作動 | 10 回中 1 回以下 | | |
| 通知タップ → TTS 開始 1.5 秒以内 | 5 回中 4 回以上 | | |
| `AnalyzerInputConverter` を使わずに供給できた | 必須 | **達成**（AVAudioConverter + `AnalyzerInput(buffer:)` でビルド成功。動作は未検証） | |

### Go / No-Go: **（記入）**

3 つすべてを満たせば Go。

### No-Go の場合の代替（実装計画 §0.4）

- 認識精度が届かない場合: `SFSpeechRecognizer`（`requiresOnDeviceRecognition = true`）へフォールバックする。
  この場合のみ **音声認識の権限（`SFSpeechRecognizer.requestAuthorization`）が追加で必要**になり、
  Info.plist に `NSSpeechRecognitionUsageDescription` を足す。オンボーディングの権限説明も 1 つ増える。
- 無音停止が安定しない場合: `SpeechDetector` モジュールの併用、または「話し終わったら画面をタップ」への退避。
  ただし §22-2（入力を面倒にしない）に反するので、退避は最後の手段にする。
- 通知タップ → TTS が 1.5 秒に収まらない場合: 起動時のオーディオセッション有効化と
  `SpeechAnalyzer.prepareToAnalyze(in:)` のプリウォーム、TTS 音声の事前ロードを先に試す。

---

## 6. 未検証のまま残っていること

- **このスパイクは一度も実行していない。** iOS 26.x のシミュレータランタイムが未導入で、
  `scripts/build-ios.sh SpeechSpike` はコンパイルとリンクだけを検証している（`docs/PROGRESS.md` の task_001 / task_004）。
- したがって次のものはすべて未確認: 権限ダイアログの実際の種類、`bestAvailableAudioFormat` が返す実際の形式、
  RMS 閾値 0.015 の妥当性、TTS の回り込み量、`AssetInventory.reserve` の要否、録音ファイルのサイズ。
- `AVAudioFile.write(from:)` を入力タップ内（オーディオスレッド）で直接呼んでいる。
  実機でグリッチが出るなら、書き込みを別スレッドへ逃がす必要がある（**未検証**）。
