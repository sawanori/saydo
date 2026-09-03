# スパイク S-E — 行動時刻アラーム（AlarmKit）

- タスク: task_023
- ブランチ: `task/023-alarm-spike`
- ターゲット: `AlarmSpike`（`Spikes/AlarmSpike/`。SaydoCore に依存しない）
- SDK: `iPhoneSimulator26.2.sdk`（AlarmKit swiftinterface の user-module-version 2303.2.4）
- 状態: **コンパイルまで完了。実機挙動は全て未検証。**

要望は「おこして ME のようにアプリを開くまでアラームが消せない。本人の録音した声で大音量で鳴る。音量を下げても最大に戻る」。
本書は、この 4 点を AlarmKit で作れる範囲と作れない範囲に切り分け、実機でしか決まらない項目を人間の記入欄として残す。

---

## 0. 先に結論（API から確定していること）

| 要望 | AlarmKit 単体での可否 | 根拠 |
|---|---|---|
| ① アプリを開くまで消せない | **不可**（そのままでは作れない） | アラートには必ずシステムの停止手段がある。iOS 26.1 で `stopButton` は「もう使われない」として deprecated になり、アプリ側が停止ボタンを消すことも差し替えることもできなくなった。「開く」は `secondaryButton` であって停止の代わりではない。代替は §5 の連鎖アラーム |
| ② 本人の録音した声で鳴る | **可**（API 上は成立。実機未確認） | `sound:` は `ActivityKit.AlertConfiguration.AlertSound`。`.named(_:)` の SDK ドキュメントコメントが「アプリの main bundle または データコンテナの `Library/Sounds`」と明記している（§2.2） |
| ③ 大音量で鳴る | **一部可** | AlarmKit のアラームは Focus と消音スイッチを上書きする（Apple 公式）。ただし音量値そのものは端末設定に従う想定で、アプリからは指定できない。実機項目 (6) |
| ④ 音量を下げても最大に戻る | **不可** | バックグラウンドから出力音量を変更する公開 API は AlarmKit にも AVFAudio にも無い。`AVAudioSession.outputVolume` は `readonly`。MPVolumeView は前面表示が必要で、この用途には使えない。本スパイクは値を読むだけ |

①と④は「AlarmKit の設定次第で実現できる」ものではない。SAYDO の設計判断が要る（§7）。

---

## 1. 検証コマンドと結果

| コマンド | exit code | ログ |
|---|---|---|
| `scripts/build-ios.sh AlarmSpike` | **70** | `docs/logs/task_023-1.txt` |
| `xcodebuild -project Saydo.xcodeproj -target AlarmSpike -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build` | **0**（`** BUILD SUCCEEDED **`・ソース警告 0 件） | `docs/logs/task_023-2.txt` |
| `supportedModes` の実測（同ターゲットを 4 通りビルドしてメタデータを読む） | 全て 0 | `docs/logs/task_023-3.txt` |

`scripts/build-ios.sh` の 70 は task_001 / task_002 と同じ環境要因で、AlarmSpike の差分とは無関係。

```
xcodebuild: error: Unable to find a destination matching the provided destination specifier:
		{ generic:1, platform:iOS Simulator }

	Ineligible destinations for the "AlarmSpike" scheme:
		{ platform:iOS, id:dvtdevice-DVTiPhonePlaceholder-iphoneos:placeholder, name:Any iOS Device, error:iOS 26.2 is not installed. Please download and install the platform from Xcode > Settings > Components. }
```

`xcrun simctl runtime list` は `Total Disk Images: 0`。シミュレータランタイムが 1 つも入っていない。
`-target` 直指定（destination を要求しない）なら通るので、本スパイクの検証はこちらで行った。

---

## 2. 確認済み API

以下は全て `iPhoneSimulator26.2.sdk` の swiftinterface から引き写したもので、かつ AlarmSpike が**コンパイルを通した**ものだけを載せる。

### 2.1 `AlarmManager`

```swift
@_hasMissingDesignatedInitializers @available(iOS 26.0, *)
public class AlarmManager {
  public static let shared: AlarmKit.AlarmManager

  public func schedule<Metadata>(id: Alarm.ID, configuration: AlarmConfiguration<Metadata>) async throws -> Alarm
  public func countdown(id: Alarm.ID) throws
  public func cancel(id: Alarm.ID) throws
  public func stop(id: Alarm.ID) throws
  public func pause(id: Alarm.ID) throws
  public func resume(id: Alarm.ID) throws
  public var alarms: [Alarm] { get throws }
  public var alarmUpdates: some AsyncSequence<[Alarm], Never> { get }
  public var authorizationState: AuthorizationState { get }
  public func requestAuthorization() async throws -> AuthorizationState
  public var authorizationUpdates: some AsyncSequence<AuthorizationState, Never> { get }

  public enum AuthorizationState { case notDetermined, denied, authorized }
  public enum AlarmError: Error { case maximumLimitReached }
}
```

- `schedule` と `requestAuthorization` だけが `async`。**`cancel` / `stop` / `pause` / `resume` / `countdown` は同期の `throws`**。
- `alarms` は `get throws` なので `try AlarmManager.shared.alarms` と書く。
- `AlarmError` は `maximumLimitReached` の 1 ケースのみ。上限値そのものは SDK に定数として無い（実機項目）。
- `AlarmManager` は `Sendable` ではないクラスだが、`SWIFT_VERSION=6.0` + `SWIFT_STRICT_CONCURRENCY=complete` のまま
  **警告ゼロでコンパイルできた**。`@preconcurrency import` も `nonisolated(unsafe)` も要らない。

### 2.2 サウンド — `AlertConfiguration.AlertSound`

**AlarmKit ではなく ActivityKit の型で、enum ではなく struct。** `case` ではない。

```swift
// ActivityKit
public struct AlertSound : Swift.Equatable, Swift.Sendable {
  public static var `default`: ActivityKit.AlertConfiguration.AlertSound { get }
  public static func named(_ name: Swift.String) -> ActivityKit.AlertConfiguration.AlertSound
  public static func == (a: AlertSound, b: AlertSound) -> Swift.Bool
}
```

公開されているのはこの 2 つだけ。`.default` は static var、`.named(_:)` は static func。

ActivityKit の swiftdoc に入っているドキュメントコメント（`strings` で抽出）:

```
/// A function you use to configure a custom sound for a Live Activity update alert.
///     - name: The name of the sound file to use for the alert. Choose a file that's in your app's main bundle
///     or the `Library/Sounds` folder of your app's data container.
```

**これがスパイクの未確認事項「音声ファイルの置き場所」への SDK 側の回答**で、バンドル限定ではなく
`Library/Sounds`（＝書き込み可能なデータコンテナ）も対象と書かれている。ただしこれは ActivityKit の
Live Activity アラート用の記述であり、AlarmKit が同じ探索をするかは実機項目 (4) で確かめる。
形式と長さの制限はドキュメントコメントに書かれていない（通知音と同じ「30 秒以内・IMA4/µLaw/aLaw/リニア PCM」を仮定した）。

> **`import ActivityKit` が要る。** AlarmKit は `@_exported import AlarmKit` しかしておらず ActivityKit を再エクスポートしない。
> `import AlarmKit` だけで `AlertConfiguration` を書くと `error: cannot find type 'AlertConfiguration' in scope` になる（実際に踏んだ）。

### 2.3 `AlarmConfiguration`

```swift
public struct AlarmConfiguration<Metadata> where Metadata : AlarmMetadata {
  public init(countdownDuration: Alarm.CountdownDuration? = nil,
              schedule: Alarm.Schedule? = nil,
              attributes: AlarmAttributes<Metadata>,
              stopIntent: (any AppIntents.LiveActivityIntent)? = nil,
              secondaryIntent: (any AppIntents.LiveActivityIntent)? = nil,
              sound: ActivityKit.AlertConfiguration.AlertSound = .default)

  public static func timer(duration: TimeInterval, attributes: ..., stopIntent: ..., secondaryIntent: ..., sound: ...) -> AlarmConfiguration<Metadata>
  public static func alarm(schedule: Alarm.Schedule? = nil, attributes: ..., stopIntent: ..., secondaryIntent: ..., sound: ...) -> AlarmConfiguration<Metadata>
}
```

**`appEntityIdentifier:` という引数はこの SDK に存在しない。** タスク指示にあった
`alarm(schedule:attributes:appEntityIdentifier:stopIntent:secondaryIntent:sound:)` は 26.2 SDK では当たらない。

### 2.4 `AlarmPresentation.Alert` — stopButton が deprecated になっている

```swift
public struct Alert : Codable, Sendable {
  public var title: LocalizedStringResource

  @available(*, deprecated, message: "This property is not used anymore and will be removed.")
  public var stopButton: AlarmButton { get set }

  public var secondaryButton: AlarmButton?
  public var secondaryButtonBehavior: SecondaryButtonBehavior?

  @available(iOS 26.1, *)
  public init(title: LocalizedStringResource, secondaryButton: AlarmButton? = nil, secondaryButtonBehavior: SecondaryButtonBehavior? = nil)

  @available(iOS, deprecated: 26.1, message: "stopButton is deprecated and will no longer be used")
  public init(title: LocalizedStringResource, stopButton: AlarmButton, secondaryButton: AlarmButton? = nil, secondaryButtonBehavior: SecondaryButtonBehavior? = nil)

  public enum SecondaryButtonBehavior { case countdown, custom }
}
```

これは要望①に直接効く。**iOS 26.1 以降、停止ボタンはアプリの持ち物ではなくシステムが出すものになった。**
消すことも文言を変えることもできない。「アプリを開くまで消せない」は、この一点で AlarmKit 単体では成立しない。

deploymentTarget が 26.0 なので、AlarmSpike は `if #available(iOS 26.1, *)` で新旧 2 つの init を持つ。
26.0 側の分岐は deprecated な init を通るが、`deprecated: 26.1` は 26.0 実行時には適用されないため**警告は出ない**。

### 2.5 `AlarmButton` / `AlarmAttributes`

```swift
public struct AlarmButton : Codable, Sendable {
  public var text: LocalizedStringResource
  public var textColor: SwiftUICore.Color
  public var systemImageName: String
  public init(text: LocalizedStringResource, textColor: SwiftUICore.Color, systemImageName: String)
}

public struct AlarmAttributes<Metadata> : ActivityKit.ActivityAttributes, Sendable where Metadata : AlarmMetadata {
  public var presentation: AlarmPresentation
  public var metadata: Metadata?          // Optional
  public var tintColor: SwiftUICore.Color // 既定値なし・必須
  public init(presentation: AlarmPresentation, metadata: Metadata? = nil, tintColor: SwiftUICore.Color)
}
```

`AlarmButton` に `.stopButton` / `.snoozeButton` のような static メンバーは**存在しない**。毎回 3 引数で作る。
`AlarmMetadata` は `Codable & Hashable & Sendable` のマーカープロトコル。空 struct で足りる。

### 2.6 `Alarm.Schedule`

```swift
public enum Schedule : Codable, Equatable, Hashable, Sendable {
  case fixed(Foundation.Date)
  case relative(Relative)      // Relative.Time(hour:minute:) + Recurrence(.weekly([Locale.Weekday]) / .never)
}
public enum State { case scheduled, countdown, paused, alerting }
```

「2 分後」のような相対時刻は `.fixed(Date().addingTimeInterval(...))` で表す。`.relative` は時刻（時・分）と曜日繰り返し用。

### 2.7 存在しない / 誤っている API（推測で書かないための記録）

| 出どころ | 記述 | 26.2 SDK の実際 |
|---|---|---|
| タスク指示 | `alarm(..., appEntityIdentifier:, ...)` | その引数は無い |
| タスク指示 | 「停止ボタンは必須」 | 26.1 で `stopButton` は deprecated。26.1 以降の init には引数自体が無い |
| タスク指示 | `AlertSound` の「case」 | `case` ではない。struct の static var / static func |
| Xcode 同梱ドキュメント※ | 「AlarmKit は iOS 18 で導入」 | 全 API が `@available(iOS 26.0, *)` |
| Xcode 同梱ドキュメント※ | `AlarmButton(label:)`、`.stopButton` / `.snoozeButton` / `.pauseButton` / `.repeatButton` / `.resumeButton` | どれも存在しない |
| Xcode 同梱ドキュメント※ | `cancel` / `pause` / `resume` を `try await` で呼ぶ | 同期の `throws`。`await` は付かない |
| Xcode 同梱ドキュメント※ | `context.state.countdownEndDate` | `AlarmPresentationState` は `alarmID` と `mode` だけ |
| Xcode 同梱ドキュメント※ | `AlarmAttributes.metadata` が非 Optional | `Metadata?` |

※ `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/SwiftUI-AlarmKit-Integration.md`。
`NSAlarmKitUsageDescription` というキー名だけはこの文書に由来する（コンパイラでは検証できない。実機項目 (0)）。

---

## 3. supportedModes の罠（実測）

`openAppWhenRun` は iOS 26.0 で deprecated（`"Please provide 'supportedModes' instead"`）になり、
代わりに `static var supportedModes: IntentModes` を書くことになっている。
ところが AppIntents のメタデータ抽出は書き方によって別の値を吐く。同じターゲットを 4 通りビルドして
`AlarmSpike.app/Metadata.appintents/extract.actionsdata` の `actions.OpenSaydoIntent` を読んだ結果:

| `OpenSaydoIntent` の宣言 | 抽出された `supportedModes` | 抽出された `openAppWhenRun` |
|---|---|---|
| `static let supportedModes: IntentModes = .foreground(.immediate)` | **1** | false |
| `static let supportedModes: IntentModes = .background` | 1 | false |
| `static let openAppWhenRun = true`（`supportedModes` を書かない） | 2 | true |
| `static let supportedModes: IntentModes = .foreground` | **2** | true |

static func 形式の `.foreground(.immediate)` は定数畳み込みされず、`.background` と同じ 1 が書き出される。
**4 通りとも exit 0・警告 0 件**なので、書き間違えてもコンパイラは何も言わない。
「開く」を押してもアプリが前面に来ない、という形で実機でしか露見しない。

AlarmSpike は `static let supportedModes: IntentModes = .foreground` を採用した（抽出値 2）。
SAYDO 本体で AppIntent を書くときも同じ罠を踏むので、実装時にメタデータを確認すること。
実測ログは `docs/logs/task_023-3.txt`。

---

## 4. 実装した 3 つのサウンドパターン

`SpikeSoundMode`（`Spikes/AlarmSpike/AlarmSpikeApp.swift`）で画面から切り替える。

| | モード | 渡す値 | ファイル |
|---|---|---|---|
| (a) | `systemDefault` | `.default` | — |
| (b) | `bundledChime` | `.named("chime.caf")` | `Spikes/AlarmSpike/Resources/chime.caf` をバンドル同梱。ビルド後は `AlarmSpike.app/chime.caf` |
| (c) | `recordedDeclaration` | `.named("declaration.caf")` | 画面のボタンで 10 秒録音し `<container>/Library/Sounds/declaration.caf` に書く（バンドル外） |

**拡張子トグル**: `.named` に `.caf` を含めるか含めないかを画面で切り替えられる。
`UNNotificationSound.soundNamed` は拡張子込みだが `AlertSound.named` の仕様は SDK に書かれていないため、
実機の 1 ビルドで両方試せるようにした。

`chime.caf` の生成（この通りに実行すれば同じものが再現できる。外部素材は使っていない）:

```bash
python3 - <<'PY'
import math, struct, wave
sr, dur = 44100, 6.0
n = int(sr * dur)
frames = bytearray()
strikes = [(0.0, 880.0), (2.0, 1174.66), (4.0, 880.0)]  # ベル風の 3 打
for i in range(n):
    t = i / sr
    s = 0.0
    for onset, f0 in strikes:
        dt = t - onset
        if 0.0 <= dt < 1.9:
            env = math.exp(-3.0 * dt)
            s += env * (math.sin(2*math.pi*f0*dt)
                        + 0.5*math.sin(2*math.pi*f0*2.0*dt)
                        + 0.25*math.sin(2*math.pi*f0*2.76*dt))
    frames += struct.pack('<h', int(max(-1.0, min(1.0, s * 0.28)) * 32767))
with wave.open('Spikes/AlarmSpike/Resources/chime.wav', 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(bytes(frames))
PY
afconvert -f caff -d ima4 Spikes/AlarmSpike/Resources/chime.wav Spikes/AlarmSpike/Resources/chime.caf
rm Spikes/AlarmSpike/Resources/chime.wav
```

`afinfo` の実測:

```
File type ID:   caff
Data format:     1 ch,  44100 Hz, ima4 (0x00000000) 0 bits/channel, 34 bytes/packet, 64 frames/packet
estimated duration: 6.000000 sec
```

(c) の録音は `AVAudioRecorder` に `AVFormatIDKey: kAudioFormatAppleIMA4` / 44100 Hz / 1ch を渡して
同じ形式で `.caf` に書く。マイク権限は `AVAudioApplication.requestRecordPermission()`（iOS 17 以降の API。
`AVAudioSession.requestRecordPermission` は deprecated）。

XcodeGen は `.caf` を Resources コピーフェーズに自動で入れる（`chime.caf in Resources` を pbxproj で確認済み）。
ビルド済みバンドルにも 144686 バイトで入っている。

---

## 5. 連鎖アラームで①をどこまで近づけるか

停止ボタンは消せない。そこで「停止しても次が鳴る」構成にして、実質的に**アプリを開くまで終わらない**状態を作れるかを試す。

- 「2 分後に連鎖アラーム 5 件（1 分間隔）を登録」ボタンで、`.fixed` スケジュールの独立したアラームを 5 本入れる。
- 5 本の ID は `UserDefaults.standard`（App Group なし）に保存する。
- 各アラートの `secondaryButton` は「開く」、`secondaryButtonBehavior = .custom`、
  `secondaryIntent` は `OpenSaydoIntent`（`LiveActivityIntent`・`supportedModes = .foreground`）。
- `OpenSaydoIntent.perform()` が残り全部を `AlarmManager.shared.cancel(id:)` で取り消し、ログを UserDefaults に残す。

つまり「とめる」を押しても 1 分後にまた鳴り、「開く」を押したときだけ連鎖が止まる。
これが実機で意図どおり動くかが項目 (2)(3)。

> `secondaryIntent` は端末の初回ロック解除後のみ有効（Apple 公式）。再起動直後にロック解除していない状態は要注意。

---

## 6. 実機での確認手順と記入欄

実行者: 人間。iOS 26.x の実機に AlarmSpike を入れて行う。**シミュレータでは意味が無い**（ランタイム自体も未導入）。

準備:
1. `xcodegen generate` 後、Xcode で `AlarmSpike` スキームを実機へ Run。
2. 「AlarmKit の権限を要求」を押して `authorizationState` が「許可」になることを見る。

| # | 確認すること | 手順 | 結果 | 備考 |
|---|---|---|---|---|
| (0) | `NSAlarmKitUsageDescription` が正しいキーか | 権限ダイアログに Info.plist の日本語文が出るか | ☐ 出た / ☐ 出ない | キー名が違うとダイアログ表示時にクラッシュするのが通例 |
| (1) | 消音スイッチ + 集中モードで鳴るか | 消音スイッチ ON・集中モード ON にして (a) 既定音で連鎖登録 → 2 分待つ | ☐ 鳴った / ☐ 鳴らない |  |
| (2) | 停止しても次が鳴るか | (1) の状態で「とめる」を押し、1 分待つ | ☐ 次が鳴った / ☐ 鳴らない | 鳴らなければ連鎖案そのものが不成立 |
| (3) | 「開く」でアプリが起動し残りが消えるか | アラート上の「開く」を押す → アプリのログ欄と pending 一覧を見る | ☐ 起動した / ☐ しない<br>☐ 残りが消えた / ☐ 残った | §3 の supportedModes が効いているかの実地確認でもある |
| (4) | バンドル外（`Library/Sounds`）の音が鳴るか | 「宣言を 10 秒録音」→ サウンドを (c) にして連鎖登録 → 2 分待つ | ☐ 録音した声が鳴った / ☐ 既定音になった / ☐ 無音 | 既定音にフォールバックしたら「バンドル限定」の証拠 |
| (4b) | `.named` に拡張子は要るか | (4) を「.caf を含める」ON / OFF の両方で試す | ON: ☐ 鳴った / ☐ 鳴らない<br>OFF: ☐ 鳴った / ☐ 鳴らない |  |
| (4c) | バンドル同梱 (b) は鳴るか | サウンドを (b) にして連鎖登録 | ☐ 鳴った / ☐ 鳴らない | (4) と比べてバンドル / コンテナのどちらが効くかを切り分ける |
| (5) | アプリを強制終了しても鳴るか | 連鎖登録後、App Switcher から AlarmSpike をスワイプで終了 → 2 分待つ | ☐ 鳴った / ☐ 鳴らない | 鳴った場合、「開く」で `perform()` が走って残りが消えるかも見る |
| (6) | 音量は「設定 > サウンドと触覚」に従うか | 設定の着信音量を小さくして鳴らす。鳴っている間に音量ボタンを下げ、画面の `outputVolume` を見る | 設定小: ☐ 小さい / ☐ 最大<br>ボタンで下げた後: ☐ 下がったまま / ☐ 戻る | 「戻る」ならシステムが上書きしている。「下がったまま」なら要望④は完全に不可 |
| (7) | 同時に持てるアラーム数の上限 | 連鎖登録を繰り返して `AlarmError.maximumLimitReached` が出る件数を記録 | 上限: ____ 件 | SAYDO の 1 日あたりの本数設計に効く |
| (8) | Widget Extension 無しでアラートが出るか | 本スパイクは Widget Extension を持たない。(1) が鳴った時点で確認済みになる | ☐ 不要 / ☐ 必要だった | `AlarmAttributes` は `ActivityAttributes` に準拠している |

### Go / No-Go

| 判定 | 記入 |
|---|---|
| 日付 | ____ |
| 実行者 | ____ |
| 端末 / OS | ____ |
| **判定** | ☐ Go（AlarmKit を task_023 本実装で採用する）<br>☐ 条件付き Go（条件: ____________________）<br>☐ No-Go（代替: ____________________） |
| 判定理由 | |

---

## 7. 要望 4 点の整理（実機結果を入れて確定させる）

| 要望 | 現時点の判定 | 根拠 | 実機で覆る可能性 |
|---|---|---|---|
| ① アプリを開くまでアラームが消せない | **不可**。ただし連鎖アラームで「開くまで終わらない」までは近づけられる見込み | `stopButton` が 26.1 で deprecated＝停止手段はシステムのもの。アプリからは消せない | 無い（API の事実）。連鎖が成立するかは項目 (2)(3) |
| ② 本人の録音した声で鳴る | **可の見込み**（未検証） | `AlertSound.named` のドキュメントコメントが main bundle と `Library/Sounds` を挙げている | 項目 (4)(4b)(4c) で確定する |
| ③ 大音量で鳴る | **一部可**。Focus と消音は上書きされるが、音量値はアプリから決められない | Apple 公式（Focus / 消音の上書き）。音量指定の API は無い | 項目 (1)(6) |
| ④ 音量を下げても最大に戻る | **不可**（アプリの実装としては） | `AVAudioSession.outputVolume` は readonly。バックグラウンドから音量を変える公開 API が無い。MPVolumeView は不可 | システム側がアラーム中に音量を保持している可能性は項目 (6) で見る。**アプリが実装できるという意味では覆らない** |

### ①④を諦めた場合に SAYDO が取り得る方向（判断は人間）

1. **連鎖アラーム**（本スパイクの実装）。停止しても次が来る。うるささの責任をアプリが負う。企画原則 §22-1「責めない」との折り合いを別途決める必要がある。
2. アラート自体は 1 本にして、**「開く」を押したときの体験**（朝の宣言音声の再生）に価値を寄せる。企画原則 §22-10 に沿う。
3. ③④を「アラーム音量」ではなく「アプリを開いたあとの再生音量」で担保する。前面にいれば `AVAudioSession` を
   `.playback` で有効化して自前で鳴らせる。ただしこれも端末音量は超えられない。

---

## 8. スパイクのファイル

| パス | 内容 |
|---|---|
| `Spikes/AlarmSpike/AlarmSpikeApp.swift` | `@main`、`SpikeAlarmMetadata`、`AlarmChainStore`（UserDefaults）、`OpenSaydoIntent`、`SpikeSoundMode`、`AlarmSpikeModel` |
| `Spikes/AlarmSpike/AlarmSpikeView.swift` | 1 画面（権限 / サウンド / 連鎖 / pending 一覧 / 音量 / ログ） |
| `Spikes/AlarmSpike/Resources/chime.caf` | IMA4 / CAF / 6.000 秒 / 144686 バイト |
| `Spikes/AlarmSpike/Info.plist` | `NSAlarmKitUsageDescription` と `NSMicrophoneUsageDescription` |
| `project.yml` | `AlarmSpike` ターゲットとスキーム |

`AlarmSpike` は SaydoCore に依存しない。`App/` と `Packages/` は変更していない。
`scripts/lint-principles.sh` は `App/` と `Packages/*/Sources` だけを見るので `Spikes/` は対象外。
