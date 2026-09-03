# SAYDO App Review Notes / 審査メモ

- 作成日: 2026-09-04
- 対象タスク: task_020
- 対象バージョン: 1.0.0（Bundle ID: `com.nonturn.saydo`）
- 用途: §1（English）を App Store Connect の「App Review Information → Notes」にそのまま貼る。§2 は同じ内容の日本語控え。§3 以降は提出者（開発者）向けの手順とチェックであり、Apple には送らない。
- 根拠: `docs/implementation-plan.md` §0.1・§0.2・§6・§7.2・§7.3・§7.4・§8・§14、`docs/acceptance-checks.json` check_016。

---

## 1. English (paste this into App Review Notes)

### SAYDO — Review Notes (v1.0.0)

**Sign-in:** Not required. The app has no accounts and no server, so no demo credentials are needed.

**What the app does:** Each morning the user names one thing they are avoiding, says it out loud, narrows it down to a step that takes five minutes or less, picks a time and place, and records a short spoken commitment in their own voice. At the time they chose, a local notification arrives and plays that recording back to them. In the evening they record one thing that moved forward. The recording is the product: the app returns the user's own voice to them rather than instructing them.

#### 1. No network activity at all

- The app contains **no networking code**. There is no `URLSession`, no `Network` framework import, no third-party SDK, no analytics, no advertising, and no crash reporting.
- Nothing is uploaded. All recordings, transcripts, and settings stay in the app's container on the device (SwiftData plus AAC audio files under Application Support, with file protection applied).
- The App Store privacy answer is therefore "Data Not Collected."
- The only network activity that can occur is performed by iOS itself: downloading the Japanese speech recognition model and, optionally, a higher-quality Japanese speech synthesis voice. The app requests these through the system APIs; no user content is involved.
- You can verify this by searching the binary or the source for `URLSession` / `import Network` — there are zero occurrences. Our build script runs this check on every build.

#### 2. Microphone: when recording starts, and how the user can see it

Recording begins **only** in these two situations:

1. The user taps a local notification that the app scheduled at a time the user set, which opens the conversation screen, or
2. The user starts a session themselves from the app's Today screen.

In both cases:

- The app **speaks its question aloud first**, and recording starts only after speech synthesis has finished (the audio path is half-duplex: while the app is speaking, the microphone stream is not being consumed). The user therefore always hears the question before the microphone opens.
- **While the microphone is listening, a live waveform driven by the actual input level is displayed in the center of the screen at all times, together with a status line reading "聞いています…" ("Listening…").** The waveform is never shown when the microphone is not active, and the microphone is never active without the waveform. VoiceOver announces the same state.
- Recording stops automatically after 1.5 seconds of silence (user-adjustable to 1.2 / 1.5 / 2.0 seconds) and is capped per turn (20 seconds for answers, 30 seconds for the spoken commitment).
- The app never records while backgrounded or closed. There is no background audio mode for recording.
- The reason we start the microphone without a record button is the product's purpose: the app exists for people who avoid tasks, and every extra tap before speaking is a place to give up. This is stated in the app's App Store description and in the microphone usage string.

**If the user denies microphone access,** every part of the app still works using text input and on-screen choices. There is also a first-class "話せない時" ("can't speak right now") mode, switchable at any point during a conversation, that completes the same flow with choices and short typed answers. Please feel free to test the app entirely with the microphone denied.

**No speech recognition permission is requested.** Transcription uses `SpeechAnalyzer` / `SpeechTranscriber`, which run on device, so `NSSpeechRecognitionUsageDescription` does not apply and no audio is sent to Apple's servers for recognition.

#### 3. Notifications

- All notifications are **local** notifications (`UNCalendarNotificationTrigger`), scheduled on the device for times the user chooses during onboarding. There is no push server.
- Default is two per day: a morning check-in, plus one at the action time the user set that morning. A "3 times mode" in Settings adds midday and evening notifications. Weekends can be turned off.
- Every notification carries two actions: "今日は休む" ("take today off", which cancels the remaining notifications for that day) and "今は話せない" ("can't talk now", which re-delivers once 60 minutes later).
- The action-time notification uses the **Time Sensitive** interruption level, requested via the Time Sensitive Notifications entitlement. Justification: this notification is the product's core moment — it delivers, at a time the user themselves chose that morning, a recording of the user's own voice reminding them of a commitment they made. If it is held back by a Focus mode, the user misses the single moment the app exists for. Regular scheduled notifications use the default interruption level. No critical alerts are used.

#### 4. Apple Intelligence is not required

- **Every feature works on devices without Apple Intelligence**, including devices where the user has turned it off. Please test on whichever device you have; there is no reduced or locked mode.
- The app checks `SystemLanguageModel.default.availability` at launch. When the on-device model is unavailable, the same conversation runs with prepared wording and on-screen choices ("Tier B"). Screens, steps, stored data, and the notification behavior are identical.
- When the on-device model is available ("Tier A"), it phrases the follow-up question and suggests smaller steps. That processing is entirely on device. No Tier badge or upsell is shown to the user, and there is no purchase associated with either mode.
- A per-feature comparison is in the app's App Store description and in our documentation.

#### 5. Content and language

- The app is Japanese only (UI, speech recognition, and speech synthesis are all ja-JP).
- All generated wording passes a filter that rejects blaming phrasing before it is spoken or displayed; if generated text fails, prepared wording is used instead. The app never scores the user, never counts missed days, and never displays a completion rate.
- There is no user-to-user content, no sharing feature, and no web view.

#### 6. Purchases

- Version 1.0.0 is free and contains **no in-app purchases** and no subscriptions.

#### 7. How to test it quickly

The app is time-based by design, so please use the following to see the whole loop within a few minutes. Detailed steps are in section 3 of the accompanying document; the short version:

1. Complete onboarding (allow microphone and notifications; any times are fine).
2. On the Today screen, tap "今話す" to start the morning session immediately without waiting for a notification.
3. Answer each question by speaking, or tap the keyboard button at the bottom right to type instead. When asked for a time, say or choose a time **two or three minutes from now**.
4. Record the spoken commitment at the last step, then leave the app.
5. The action-time notification arrives at the time you set; tapping it plays your recording back and asks how it went.
6. To exercise the fixed morning / midday / evening notifications, open Settings, turn on "3 回モード" (3-times mode), set the three times to a few minutes apart starting a couple of minutes from now, then leave and reopen the app once so the schedule is rebuilt.

Thank you for reviewing. If anything is unclear, please contact snp.inc.info@gmail.com and we will respond the same day.

---

## 2. 日本語（同内容の控え。Apple には英語版を送る）

### SAYDO 審査メモ（v1.0.0）

**サインイン**: 不要。アカウントもサーバーも持たないため、デモアカウントの提供もない。

**アプリの内容**: 朝、逃げたいことをひとつ声に出し、5 分以下でできる大きさまで行動を小さくし、時刻と場所を決め、最後に自分の言葉で短い宣言を録音する。決めた時刻にローカル通知が届き、その録音がそのまま再生される。夜は前に進めたことをひとつ残す。録音そのものが製品であり、アプリが指示を出すのではなく、本人の声を本人に返す。

#### 1. 外部通信がゼロ

- ネットワーク通信のコードを含まない（`URLSession` なし、`Network` の import なし、外部 SDK・解析・広告・クラッシュレポートのいずれも組み込んでいない）。
- 送信は一切ない。録音・文字起こし・設定は端末内のアプリ領域に残る（SwiftData と Application Support 配下の AAC ファイル。ファイル保護属性あり）。
- したがって App Store のプライバシー表示は「データを収集しない」。
- 発生しうる通信は iOS 自身が行うものだけ: 日本語の音声認識モデルのダウンロードと、任意で高品質な日本語読み上げ音声のダウンロード。いずれもシステム API 経由で、ユーザーの内容物は関与しない。
- 検証方法: ソースを `URLSession` / `import Network` で検索すると 0 件。ビルドスクリプトが毎回この検査を実行している。

#### 2. マイク: いつ録音が始まり、どう見えているか

録音が始まるのは次の 2 つの場合のみ。

1. ユーザーが設定した時刻に鳴った本アプリのローカル通知をタップして会話画面に入ったとき
2. ユーザーが Today 画面から自分でセッションを開始したとき

いずれの場合も、

- **アプリが質問を読み上げ終わってから**録音が始まる（音声経路は半二重。読み上げ中はマイクの取り込みを消費しない）。したがってユーザーは必ず先に質問を聞く。
- **マイクが聞き取っている間は、実際の入力レベルで動く波形が画面中央に常時表示され**、状態行に「聞いています…」が出る。マイクが動いていないときに波形を出すことはなく、波形なしでマイクが動くこともない。VoiceOver も同じ状態を読み上げる。
- 1.5 秒の沈黙で自動停止する（設定で 1.2 / 1.5 / 2.0 秒）。1 回の聞き取りは最長 20 秒、宣言の録音は最長 30 秒。
- バックグラウンドや終了中に録音しない。録音用のバックグラウンドモードを持たない。
- 録音ボタンを押させない理由は製品の目的そのものにある。行動を避けてしまう人のためのアプリであり、話し始めるまでのタップ 1 つ 1 つが離脱点になる。この理由はストア説明文とマイクの用途説明文にも書いている。

**マイクを拒否した場合**、文字入力と選択肢だけで全機能を完走できる。会話の途中でいつでも切り替えられる「話せない時」モードも第一級の機能として用意している。マイクを拒否したままの審査も歓迎する。

**音声認識の許可は求めない**。文字起こしは端末内で動作する `SpeechAnalyzer` / `SpeechTranscriber` を使うため、`NSSpeechRecognitionUsageDescription` は該当せず、認識のために音声が Apple のサーバーへ送られることもない。

#### 3. 通知

- すべてローカル通知（`UNCalendarNotificationTrigger`）。オンボーディングでユーザーが選んだ時刻に、端末内で予定される。プッシュサーバーはない。
- 既定は 1 日 2 回（朝のチェックインと、その朝に本人が決めた行動時刻の 1 回）。設定の「3 回モード」で昼と夜が加わる。週末をオフにできる。
- すべての通知に 2 つのアクションを持つ。「今日は休む」（その日の残りの通知を取り消す）と「今は話せない」（60 分後に 1 回だけ再通知する）。
- 行動時刻の通知だけ **Time Sensitive** の割り込みレベルを使い、Time Sensitive Notifications エンタイトルメントを申請する。理由: この通知は製品の中心そのもので、その朝に本人が自分で決めた時刻に、本人が自分に向けて録音した声を届けるもの。集中モードで抑止されると、このアプリが存在する唯一の瞬間が失われる。他の定時通知は既定の割り込みレベル。Critical Alert は使わない。

#### 4. Apple Intelligence は必須ではない

- **Apple Intelligence 非対応の端末でも、オフにしている端末でも、全機能が動く。** 手元のどの端末で審査しても、機能が減った状態やロックされた状態にはならない。
- 起動時に `SystemLanguageModel.default.availability` を判定する。利用できない場合は、あらかじめ用意した文言と選択肢で同じ会話が進む（Tier B）。画面・手順・保存されるデータ・通知の挙動は同一。
- 利用できる場合（Tier A）は、追加の質問の言い回しと、行動を小さくする案の生成に使う。処理は端末内で完結する。ユーザーに Tier のバッジは見せず、どちらの場合も課金は関係しない。
- 機能ごとの差は `docs/app-store/metadata.md` §9.2 の表にまとめてあり、ストア説明文にも短い版を載せている。

#### 5. コンテンツと言語

- 日本語のみ（UI・音声認識・音声合成すべて ja-JP）。
- 生成されたすべての文言は、読み上げ・表示の前に責める言い回しを弾く検査を通る。通らなかった場合は用意された文言に置き換える。採点をしない。動けなかった日を数えない。達成率を表示しない。
- ユーザー同士のコンテンツ、共有機能、Web ビューのいずれも持たない。

#### 6. 課金

- v1.0.0 は無料で、**App 内課金とサブスクリプションを含まない**。

#### 7. 短時間で試す手順

時刻に依存する設計のため、下記の手順で数分のうちに全体を確認できる。詳細は §3 を参照。

1. オンボーディングを完了する（マイクと通知を許可。時刻は任意でよい）。
2. Today 画面の「今話す」で、通知を待たずに朝のセッションを開始する。
3. 各質問に声で答える（右下のキーボードボタンで文字入力に切り替えてもよい）。時刻を聞かれたら **2〜3 分後**の時刻を答える。
4. 最後のステップで宣言を録音し、アプリを離れる。
5. 設定した時刻に通知が届く。タップすると自分の録音が再生され、状態を聞かれる。
6. 朝・昼・夜の定時通知を試す場合は、設定で「3 回モード」を有効にし、3 つの時刻を「2 分後」から数分おきに設定して、一度アプリを閉じて開き直す（通知が再計画される）。

---

## 3. 提出者向け: 3 つの通知の時刻を変えて即時に試す手順

Apple には §1-7 の短い版を送る。以下は開発者と TestFlight テスターが使う詳しい版。

### 3.1 前提

- 通知は**繰り返しトリガーを使わず**、起動時と宣言時に「今日から一定日数分」を非繰り返しの `UNCalendarNotificationTrigger` として登録し直す設計（implementation-plan §7.4）。
- したがって **設定で時刻を変えたあと、一度アプリを閉じて開き直すと確実に再計画される**。時刻を変えた直後に通知が来ないときは、まずこれを行う。
- 端末の「設定 → 通知 → SAYDO」で通知が許可されていること。集中モードを有効にしている場合、行動時刻の通知（Time Sensitive）以外は抑止される。

### 3.2 手順（所要 10 分）

| # | 操作 | 期待される結果 |
|---|---|---|
| 1 | オンボーディングを完了する（マイク許可・通知許可・時刻は既定のまま） | Today 画面に「今話す」が出る |
| 2 | 設定を開き「3 回モード」を有効にする | 朝・昼・夜の 3 つの時刻欄が現れる |
| 3 | 朝を「現在時刻の 2 分後」、昼を「4 分後」、夜を「6 分後」に設定する | 設定画面に反映される |
| 4 | アプリを一度終了し、開き直す | 通知が再計画される（3.3 の確認方法を参照） |
| 5 | 2 分待つ | 朝の通知「今日、何から逃げそう？」が届く |
| 6 | 通知をタップする | Today 画面を経由せず会話画面が開き、1.5 秒以内に質問の読み上げが始まる。読み上げ終了後に波形が動き出す |
| 7 | 「クライアントへの返信」などと声で答える | 沈黙 1.5 秒で自動停止し、次の質問に進む |
| 8 | 理由の選択肢から 1 つ選ぶ | 行動を小さくする質問に進む |
| 9 | 「メールを開くだけ」と答える | 時刻と場所を聞かれる |
| 10 | 「◯時◯分に、机で」と、**現在時刻の 3 分後**を答える | 宣言の録音に進む |
| 11 | 「◯時◯分に、机で、メールを開きます」と録音する | 「受け取りました。◯時に、朝のあなたから届きます。」で終了 |
| 12 | アプリを閉じて待つ | 4 分後に昼の固定通知、3 分後に行動時刻の通知が届く（両者が 30 分以内に重なる場合、その日の昼の固定通知は取り消される仕様） |
| 13 | 行動時刻の通知をタップする | 「朝のあなたからです。」の後、手順 11 の録音がそのまま再生される。イヤホン未接続で音量が大きい場合は、先に「イヤホンで聞く／文字で読む」が出る |
| 14 | 「まだ」を選ぶ | 「何が止めてる？」→ 行動がさらに小さくなる |
| 15 | 6 分後の夜の通知をタップする | 「今日、少しでも前に進めたことは？」から夜のフローが始まる |
| 16 | 記録タブを開く | その日の全音声が時刻順に並び、各行を再生できる |

### 3.3 通知が予定されているかの確認

- 実機だけで確認する場合: 設定画面の最下部「開発者向け」節に、予定されている通知の一覧と件数を表示する（retention-strategy.md §4 の計測値と同じ節）。**要確認**: この一覧表示が task_013 の実装に含まれているか。含まれていなければ、この手順は Xcode の Console でのログ確認に置き換える。
- Xcode から確認する場合: デバッグ実行して `UNUserNotificationCenter.current().getPendingNotificationRequests` の結果をログに出す。識別子は `morning-yyyyMMdd` / `noon-yyyyMMdd` / `night-yyyyMMdd` / `action-yyyyMMdd` の形。

### 3.4 マイクを拒否した状態のテスト

1. iOS の「設定 → SAYDO → マイク」をオフにする。
2. アプリを開き、朝のセッションを開始する。
3. 期待: 画面上部に設定アプリへの導線が出て、すべてのステップが選択肢と文字入力で進む。宣言はテキストとして保存される。
4. 行動時刻の通知をタップすると、宣言音声の再生の代わりに**宣言テキストが画面に大きく表示され**、「朝のあなたからです。」だけが読み上げられる（本人の言葉を合成音声で読み直さない）。

### 3.5 Apple Intelligence 非対応の状態のテスト

- 対応機で試す場合: iOS の「設定 → Apple Intelligence と Siri」で Apple Intelligence をオフにし、アプリを起動し直す。
- 期待: 同じ画面・同じ手順で朝・昼・夜が完走する。理由の質問が定型の選択肢になり、行動を小さくする場面が「本人に言ってもらう」形になる。それ以外に違いは見えない。

---

## 4. 想定される指摘と、こちらの答え

| # | 指摘されうる点 | ガイドライン上の論点 | 用意する答え |
|---|---|---|---|
| 1 | 明示的な操作なしにマイクが起動する | 5.1.1（データの収集と保存） | §1-2 のとおり、起動条件は「本人が通知をタップ」または「本人が開始」の 2 つだけ。読み上げの後に開始し、聞き取り中は波形を常時表示する。用途説明文にも同じ内容を書いた。マイクを拒否しても全機能が使える |
| 2 | Time Sensitive エンタイトルメントの必要性 | 通知の割り込みレベル | §1-3 の理由。本人がその朝に決めた時刻に、本人の声を届ける通知に限って使用する。他の通知は既定レベル |
| 3 | 音声認識の許可を求めていない | 5.1.1 | `SpeechAnalyzer` のオンデバイス処理のため該当しない。`SFSpeechRecognizer` を使う実装は含まない |
| 4 | 「データを収集しない」表示の妥当性 | 5.1.2 | ネットワークコードが 0 件。`grep -rn "URLSession\|import Network" App Packages` の結果を提出時に手元に持っておく |
| 5 | 最低限の機能しかない / Web サイトの焼き直し | 4.2（Minimum Functionality） | 録音・オンデバイス音声認識・音声合成・ローカル通知・オンデバイス LLM を使うネイティブ体験であり、Web ビューを持たない |
| 6 | 健康・メンタルヘルスに関する主張 | 1.4.1 / 5.1.3 | 診断・治療・効果の主張をしていない。カテゴリもヘルスケアを選ばない。ストア説明文にも効果の約束を書いていない |
| 7 | 端末内のみの保存とバックアップ | — | iCloud バックアップの対象に含める。バックアップが無効な端末では端末内にのみ残る旨をオンボーディングと設定画面に表示している |
| 8 | 日本語のみ | — | 販売地域と言語の設定で日本語のみを宣言する |

---

## 5. 提出前チェックリスト

- [ ] `project.yml` の `MARKETING_VERSION` が `1.0.0`（現在 `0.1.0`）
- [ ] `NSMicrophoneUsageDescription` が `metadata.md` §10 の推奨版に更新済み、かつ実機の許可ダイアログで途中省略されない
- [ ] Time Sensitive Notifications エンタイトルメントが Provisioning Profile に含まれている
- [ ] `grep -rn "URLSession\|import Network" App Packages` が 0 件（結果を `docs/PROGRESS.md` に貼る）
- [ ] `scripts/build-ios.sh` と `scripts/test-ios.sh` が exit 0
- [ ] プライバシーポリシー URL が公開済みで、ログインなしで読める
- [ ] App のプライバシーの回答が「データを収集しない」
- [ ] スクリーンショット 6 枚（`metadata.md` §8）にダミーデータ以外が写っていない
- [ ] 輸出コンプライアンス: 暗号化を使用しない（`ITSAppUsesNonExemptEncryption = false`）
- [ ] 審査メモに §1 の英文を貼った
- [ ] 連絡先（snp.inc.info@gmail.com）が App Review Information に入っている

---

## 6. 要確認事項

1. Time Sensitive Notifications エンタイトルメントの申請が完了しているか（Apple Developer での申請が必要）。
2. 設定画面の「開発者向け」節に、予定されている通知の一覧が表示されるか（§3.3）。task_013 の実装内容と突き合わせる。
3. §3.2 の手順 12 の「昼の固定通知が取り消される」挙動を、実機で 1 度確認する（implementation-plan §7.4 の仕様どおりか）。
4. 審査メモに書いた「1.5 秒以内に読み上げが始まる」は S-C の合格基準（5 回中 4 回）である。実機の計測結果（`docs/spikes/speech-spike.md`）が未記入のため、**提出前に実測値を確認してから審査メモに残す**。基準を満たしていない場合は、この一文を審査メモから外す。
5. 販売地域を全世界にする場合、英語の審査メモに加えて英語のサポートページが要るか。
